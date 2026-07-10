// supabase/functions/_shared/providers/paystack_provider.ts
import type {
  InitCheckoutInput,
  InitCheckoutResult,
  PaymentProviderPort,
  ProcessPayoutInput,
  ProcessPayoutResult,
  VerifyTransactionInput,
  VerifyTransactionResult,
  VerifyWebhookSignatureInput,
} from "./port.ts";
import { PaymentProviderError } from "./port.ts";
import { retryFetch } from "../retry.ts";
import { sanitizeCurrency } from "../sanitize.ts";

const PAYSTACK_BASE_URL = "https://api.paystack.co";

export class PaystackProvider implements PaymentProviderPort {
  readonly name = "paystack" as const;

  private readonly webhookSecret: string;
  private readonly secretKey: string;

  constructor() {
    // Read at construction so a missing secret fails fast on instantiation,
    // not during signature verify.
    this.secretKey = Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";
    // Paystack signs webhooks with HMAC-SHA512(secretKey, body) — there is NO
    // separate webhook secret. Fall back to secretKey if the dedicated env
    // var isn't set; this matches Paystack's actual webhook contract.
    this.webhookSecret =
      Deno.env.get("PAYSTACK_WEBHOOK_SECRET") ?? this.secretKey;
  }

  async initCheckout(
    input: InitCheckoutInput,
  ): Promise<InitCheckoutResult> {
    if (!this.secretKey) {
      throw new PaymentProviderError(
        "Paystack secret key not configured",
        "unavailable",
        false,
      );
    }
    const currency = sanitizeCurrency(input.currency);
    // Append reference to callback so the WebView can pick it up from the URL.
    const sep = input.callbackUrl.includes("?") ? "&" : "?";
    const callbackUrl = `${input.callbackUrl}${sep}reference=${encodeURIComponent(input.reference)}`;

    const body: Record<string, unknown> = {
      amount: Math.round(input.amount * 100),
      email: input.customerEmail,
      currency,
      reference: input.reference,
      callback_url: callbackUrl,
      metadata: input.metadata ?? {},
    };
    if (input.destinationAccountId) {
      body.subaccount = input.destinationAccountId;
    }
    if (input.platformFeeAmount !== undefined) {
      body.transaction_charge = Math.round(input.platformFeeAmount * 100);
    }

    let resp: Response;
    try {
      resp = await retryFetch(
        `${PAYSTACK_BASE_URL}/transaction/initialize`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${this.secretKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(body),
        },
        { attempts: 3, baseDelayMs: 500, label: "paystack.initialize" },
      );
    } catch (e) {
      throw new PaymentProviderError(
        `Paystack initialize failed: ${(e as Error).message}`,
        "unavailable",
        false,
        undefined,
        e,
      );
    }
    const data = await resp.json();
    if (!data.status) {
      throw new PaymentProviderError(
        data.message ?? "Paystack initialize returned status=false",
        "invalid_request",
        false,
        undefined,
        data,
      );
    }
    return {
      checkoutUrl: data.data.authorization_url,
      providerReference: data.data.reference,
    };
  }

  async verifyTransaction(
    input: VerifyTransactionInput,
  ): Promise<VerifyTransactionResult> {
    if (!this.secretKey) {
      throw new PaymentProviderError(
        "Paystack secret key not configured",
        "unavailable",
        false,
      );
    }
    let resp: Response;
    try {
      resp = await retryFetch(
        `${PAYSTACK_BASE_URL}/transaction/verify/${encodeURIComponent(input.reference)}`,
        { headers: { Authorization: `Bearer ${this.secretKey}` } },
        { attempts: 3, baseDelayMs: 500, label: "paystack.verify" },
      );
    } catch (e) {
      // retryFetch throws Error on 4xx (terminal) or Response on 5xx after retries.
      throw new PaymentProviderError(
        `Paystack verify failed: ${(e as Error).message}`,
        "unavailable",
        false,
        undefined,
        e,
      );
    }
    const body = await resp.json();
    if (!body.status) {
      throw new PaymentProviderError(
        body.message ?? "Paystack verify returned status=false",
        "invalid_request",
        false,
        undefined,
        body,
      );
    }
    const d = body.data;
    const status: VerifyTransactionResult["status"] =
      d.status === "success" ? "success" :
      d.status === "abandoned" ? "abandoned" :
      d.status === "failed" ? "failed" : "pending";

    return {
      status,
      amount: (d.amount ?? 0) / 100,
      currency: (d.currency ?? "").toUpperCase(),
      paidAt: d.paid_at,
      providerTransactionId: String(d.id ?? d.reference ?? input.reference),
    };
  }

  async processPayout(
    input: ProcessPayoutInput,
  ): Promise<ProcessPayoutResult> {
    if (!this.secretKey) {
      throw new PaymentProviderError("Paystack not configured", "unavailable", false);
    }
    const amountKobo = Math.round(input.amount * 100);
    let resp: Response;
    try {
      resp = await retryFetch(
        `${PAYSTACK_BASE_URL}/transfer`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${this.secretKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            source: "balance",
            amount: amountKobo,
            recipient: input.destinationAccountId,
            reference: input.reference,    // Paystack's native idempotency primitive
            reason: input.reason ?? "Withdrawal",
          }),
        },
        { attempts: 3, baseDelayMs: 1000, label: "paystack.transfer" },
      );
    } catch (e) {
      throw new PaymentProviderError(
        `Paystack transfer failed: ${(e as Error).message}`,
        "unavailable",
        false,
        undefined,
        e,
      );
    }
    const body = await resp.json();
    if (!body.status) {
      throw new PaymentProviderError(
        body.message ?? "Paystack transfer returned status=false",
        "invalid_request",
        false,
        undefined,
        body,
      );
    }
    const d = body.data;
    return {
      status: d.status === "success" ? "success" : d.status === "failed" ? "failed" : "pending",
      providerTransferId: d.transfer_code,
    };
  }

  async verifyWebhookSignature(
    input: VerifyWebhookSignatureInput,
  ): Promise<boolean> {
    if (!this.webhookSecret) {
      console.error("❌ PAYSTACK_WEBHOOK_SECRET not configured");
      return false;
    }
    if (!input.signatureHeader) return false;

    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      enc.encode(this.webhookSecret),
      { name: "HMAC", hash: "SHA-512" },
      false,
      ["sign"],
    );
    const buf = await crypto.subtle.sign(
      "HMAC",
      key,
      enc.encode(input.rawBody),
    );
    const computed = Array.from(new Uint8Array(buf))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    return timingSafeEqualHex(computed, input.signatureHeader);
  }
}

/// Constant-time equality check for hex strings (HMAC signature comparison).
///
/// A naive `===` short-circuits on the first mismatching character, leaking
/// information about how much of the prefix matched via timing — an attacker
/// can iteratively guess the signature one byte at a time. This loops over
/// every character with a fixed-time XOR-and-OR so the comparison time is
/// independent of where the first mismatch occurs.
///
/// Length-mismatch returns false immediately; lengths are not the secret.
function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
