import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PaystackProvider } from "./paystack_provider.ts";

// Set env BEFORE importing/instantiating the provider so its constructor sees it.
Deno.env.set("PAYSTACK_WEBHOOK_SECRET", "test_webhook_secret");

Deno.test("PaystackProvider.verifyWebhookSignature: valid HMAC-SHA512 → true", async () => {
  const provider = new PaystackProvider();
  const body = '{"event":"charge.success","data":{"reference":"abc"}}';
  const sig = await hmacSha512Hex("test_webhook_secret", body);
  const ok = await provider.verifyWebhookSignature({
    rawBody: body,
    signatureHeader: sig,
  });
  assertEquals(ok, true);
});

Deno.test("PaystackProvider.verifyWebhookSignature: tampered body → false", async () => {
  const provider = new PaystackProvider();
  const body = '{"event":"charge.success","data":{"reference":"abc"}}';
  const sig = await hmacSha512Hex("test_webhook_secret", body);
  const ok = await provider.verifyWebhookSignature({
    rawBody: body + "tampered",
    signatureHeader: sig,
  });
  assertEquals(ok, false);
});

Deno.test("PaystackProvider.verifyWebhookSignature: empty signature → false", async () => {
  const provider = new PaystackProvider();
  const ok = await provider.verifyWebhookSignature({
    rawBody: '{"x":1}',
    signatureHeader: "",
  });
  assertEquals(ok, false);
});

// Helper: compute HMAC-SHA512 hex (matches Paystack's signature format).
async function hmacSha512Hex(secret: string, payload: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const buf = await crypto.subtle.sign("HMAC", key, enc.encode(payload));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

import { assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PaymentProviderError } from "./port.ts";

Deno.env.set("PAYSTACK_SECRET_KEY", "sk_test_dummy");

// Stub global fetch — restore after each test.
function stubFetch(handler: (url: string, init?: RequestInit) => Response | Promise<Response>) {
  const original = globalThis.fetch;
  globalThis.fetch = (input, init) =>
    Promise.resolve(handler(input.toString(), init as RequestInit));
  return () => { globalThis.fetch = original; };
}

Deno.test("PaystackProvider.verifyTransaction: success → maps to result", async () => {
  const restore = stubFetch((url) => {
    if (url.includes("/transaction/verify/")) {
      return new Response(JSON.stringify({
        status: true,
        data: {
          status: "success",
          amount: 5000,           // 5000 kobo = 50.00
          currency: "GHS",
          paid_at: "2026-05-18T10:00:00Z",
          id: 12345,
          reference: "test_ref_1",
        },
      }), { status: 200 });
    }
    return new Response("not found", { status: 404 });
  });
  try {
    const provider = new PaystackProvider();
    const result = await provider.verifyTransaction({ reference: "test_ref_1" });
    assertEquals(result.status, "success");
    assertEquals(result.amount, 50);          // converted to major units
    assertEquals(result.currency, "GHS");
    assertEquals(result.providerTransactionId, "12345");
    assertEquals(result.paidAt, "2026-05-18T10:00:00Z");
  } finally { restore(); }
});

Deno.test("PaystackProvider.verifyTransaction: failed → status=failed", async () => {
  const restore = stubFetch(() =>
    new Response(JSON.stringify({
      status: true,
      data: { status: "failed", amount: 5000, currency: "GHS", id: 1, reference: "x" },
    }), { status: 200 })
  );
  try {
    const provider = new PaystackProvider();
    const result = await provider.verifyTransaction({ reference: "x" });
    assertEquals(result.status, "failed");
  } finally { restore(); }
});

Deno.test("PaystackProvider.verifyTransaction: abandoned → status=abandoned", async () => {
  const restore = stubFetch(() =>
    new Response(JSON.stringify({
      status: true,
      data: { status: "abandoned", amount: 0, currency: "GHS", id: 1, reference: "x" },
    }), { status: 200 })
  );
  try {
    const provider = new PaystackProvider();
    const result = await provider.verifyTransaction({ reference: "x" });
    assertEquals(result.status, "abandoned");
  } finally { restore(); }
});

Deno.test("PaystackProvider.verifyTransaction: 401 from API → throws unavailable+non-retryable", async () => {
  const restore = stubFetch(() =>
    new Response(JSON.stringify({ status: false, message: "Invalid key" }), { status: 401 })
  );
  try {
    const provider = new PaystackProvider();
    await assertRejects(
      () => provider.verifyTransaction({ reference: "x" }),
      PaymentProviderError,
    );
  } finally { restore(); }
});

Deno.test("PaystackProvider.initCheckout: returns authorization URL + reference", async () => {
  const restore = stubFetch((url, init) => {
    if (url.endsWith("/transaction/initialize")) {
      const body = JSON.parse(init?.body as string);
      // Adapter must convert major→minor units.
      assertEquals(body.amount, 5000);
      assertEquals(body.email, "buyer@example.com");
      assertEquals(body.currency, "GHS");
      assertEquals(body.reference, "ref_abc");
      return new Response(JSON.stringify({
        status: true,
        data: {
          authorization_url: "https://checkout.paystack.com/x",
          reference: "ref_abc",
          access_code: "ac_xyz",
        },
      }), { status: 200 });
    }
    return new Response("not found", { status: 404 });
  });
  try {
    const provider = new PaystackProvider();
    const result = await provider.initCheckout({
      amount: 50,
      currency: "GHS",
      reference: "ref_abc",
      customerEmail: "buyer@example.com",
      callbackUrl: "nanoembryo://payment-success",
    });
    assertEquals(result.checkoutUrl, "https://checkout.paystack.com/x");
    assertEquals(result.providerReference, "ref_abc");
  } finally { restore(); }
});

Deno.test("PaystackProvider.initCheckout: forwards subaccount + platform fee", async () => {
  let received: any;
  const restore = stubFetch((url, init) => {
    if (url.endsWith("/transaction/initialize")) {
      received = JSON.parse(init?.body as string);
      return new Response(JSON.stringify({
        status: true,
        data: { authorization_url: "u", reference: "r" },
      }), { status: 200 });
    }
    return new Response("nf", { status: 404 });
  });
  try {
    const provider = new PaystackProvider();
    await provider.initCheckout({
      amount: 100,
      currency: "GHS",
      reference: "r",
      customerEmail: "x@y.z",
      callbackUrl: "x://y",
      destinationAccountId: "ACCT_sub1",
      platformFeeAmount: 2.9,
    });
    assertEquals(received.subaccount, "ACCT_sub1");
    assertEquals(received.transaction_charge, 290); // 2.9 → 290 minor
  } finally { restore(); }
});

Deno.test("PaystackProvider.initCheckout: provider 400 → throws PaymentProviderError", async () => {
  const restore = stubFetch(() =>
    new Response(JSON.stringify({ status: false, message: "Invalid email" }), { status: 400 })
  );
  try {
    const provider = new PaystackProvider();
    await assertRejects(
      () => provider.initCheckout({
        amount: 50, currency: "GHS", reference: "r",
        customerEmail: "bad", callbackUrl: "x://y",
      }),
      PaymentProviderError,
    );
  } finally { restore(); }
});

Deno.test("PaystackProvider.processPayout: kobo conversion + reference idempotency", async () => {
  let received: any;
  const restore = stubFetch((url, init) => {
    if (url.endsWith("/transfer")) {
      received = JSON.parse(init?.body as string);
      return new Response(JSON.stringify({
        status: true,
        data: { transfer_code: "trf_xyz", status: "pending", reference: received.reference },
      }), { status: 200 });
    }
    return new Response("nf", { status: 404 });
  });
  try {
    const provider = new PaystackProvider();
    const result = await provider.processPayout({
      amount: 100,
      currency: "GHS",
      destinationAccountId: "RCP_abc",
      reference: "wd_idempotency_1",
      reason: "Withdrawal",
    });
    assertEquals(received.amount, 10000);
    assertEquals(received.recipient, "RCP_abc");
    assertEquals(received.reference, "wd_idempotency_1");
    assertEquals(received.reason, "Withdrawal");
    assertEquals(result.providerTransferId, "trf_xyz");
    assertEquals(result.status, "pending");
  } finally { restore(); }
});

Deno.test("PaystackProvider.processPayout: status=false → invalid_request", async () => {
  const restore = stubFetch(() =>
    new Response(JSON.stringify({ status: false, message: "Insufficient balance" }), { status: 200 })
  );
  try {
    const provider = new PaystackProvider();
    await assertRejects(
      () => provider.processPayout({
        amount: 50, currency: "GHS", destinationAccountId: "RCP_x",
        reference: "wd_x",
      }),
      PaymentProviderError,
    );
  } finally { restore(); }
});
