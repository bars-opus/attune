// supabase/functions/_shared/providers/stripe_provider.ts
import Stripe from "https://esm.sh/stripe@13.6.0";
import { PaymentProviderError } from "./port.ts";
import { retryFetch } from "../retry.ts";
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

export class StripeProvider implements PaymentProviderPort {
  readonly name = "stripe" as const;

  private readonly stripe: Stripe | null;
  private readonly webhookSecret: string;
  private readonly secretKey: string;

  constructor() {
    const key = Deno.env.get("STRIPE_SECRET_KEY");
    this.secretKey = key ?? "";
    this.stripe = key ? new Stripe(key, { apiVersion: "2023-10-16" }) : null;
    this.webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  }

  async initCheckout(
    input: InitCheckoutInput,
  ): Promise<InitCheckoutResult> {
    if (!this.stripe) {
      throw new PaymentProviderError("Stripe not configured", "unavailable", false);
    }
    const sessionParams: Stripe.Checkout.SessionCreateParams = {
      payment_method_types: ["card"],
      mode: "payment",
      customer_email: input.customerEmail,
      line_items: [{
        price_data: {
          currency: input.currency.toLowerCase(),
          product_data: {
            name: "Booking Deposit",
          },
          unit_amount: Math.round(input.amount * 100),
        },
        quantity: 1,
      }],
      success_url: input.callbackUrl,
      cancel_url: input.callbackUrl.replace("payment-success", "payment-cancelled"),
      metadata: {
        ...input.metadata,
        reference: input.reference,
      },
    };
    if (input.destinationAccountId) {
      sessionParams.payment_intent_data = {
        transfer_data: { destination: input.destinationAccountId },
      };
      if (input.platformFeeAmount !== undefined) {
        sessionParams.payment_intent_data.application_fee_amount =
          Math.round(input.platformFeeAmount * 100);
      }
    }

    let session: Stripe.Checkout.Session;
    try {
      session = await this.stripe.checkout.sessions.create(sessionParams, {
        idempotencyKey: input.reference,
      });
    } catch (e) {
      const err = e as { type?: string; message?: string; raw?: unknown };
      const category = err.type === "StripeInvalidRequestError"
        ? "invalid_request"
        : err.type === "StripeRateLimitError"
        ? "rate_limit"
        : "unavailable";
      throw new PaymentProviderError(
        err.message ?? "Stripe session create failed",
        category,
        category === "rate_limit",
        err.type,
        err.raw ?? err,
      );
    }
    return {
      checkoutUrl: session.url ?? "",
      providerReference: session.id,
    };
  }

  async verifyTransaction(
    input: VerifyTransactionInput,
  ): Promise<VerifyTransactionResult> {
    if (!this.stripe) {
      throw new PaymentProviderError(
        "Stripe not configured",
        "unavailable",
        false,
      );
    }
    let session: Stripe.Checkout.Session;
    try {
      session = await this.stripe.checkout.sessions.retrieve(input.reference);
    } catch (e) {
      const err = e as { type?: string; message?: string; raw?: unknown };
      const category = err.type === "StripeInvalidRequestError"
        ? "invalid_request"
        : err.type === "StripeRateLimitError"
        ? "rate_limit"
        : "unavailable";
      throw new PaymentProviderError(
        err.message ?? "Stripe session retrieve failed",
        category,
        category === "rate_limit",
        err.type,
        err.raw ?? err,
      );
    }
    const status: VerifyTransactionResult["status"] =
      session.payment_status === "paid" ? "success" :
      session.status === "expired" ? "abandoned" :
      session.payment_status === "no_payment_required" ? "success" : "pending";

    return {
      status,
      amount: (session.amount_total ?? 0) / 100,
      currency: (session.currency ?? "").toUpperCase(),
      paidAt: session.created
        ? new Date(session.created * 1000).toISOString()
        : undefined,
      providerTransactionId: session.id,
    };
  }

  async processPayout(
    input: ProcessPayoutInput,
  ): Promise<ProcessPayoutResult> {
    if (!this.secretKey) {
      throw new PaymentProviderError("Stripe not configured", "unavailable", false);
    }
    const amountCents = Math.round(input.amount * 100);
    let resp: Response;
    try {
      resp = await retryFetch(
        "https://api.stripe.com/v1/payouts",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${this.secretKey}`,
            "Content-Type": "application/x-www-form-urlencoded",
            "Idempotency-Key": input.reference,
          },
          body: new URLSearchParams({
            amount: amountCents.toString(),
            currency: input.currency.toLowerCase(),
            destination: input.destinationAccountId,
            description: input.reason ?? "Withdrawal",
          }).toString(),
        },
        { attempts: 3, baseDelayMs: 1000, label: "stripe.payout" },
      );
    } catch (e) {
      throw new PaymentProviderError(
        `Stripe payout failed: ${(e as Error).message}`,
        "unavailable",
        false,
        undefined,
        e,
      );
    }
    const data = await resp.json();
    if (data.error) {
      throw new PaymentProviderError(
        data.error.message ?? "Stripe payout returned error",
        "invalid_request",
        false,
        data.error.code,
        data.error,
      );
    }
    return {
      status: data.status === "paid" ? "success" : data.status === "failed" ? "failed" : "pending",
      providerTransferId: data.id,
    };
  }

  async verifyWebhookSignature(
    input: VerifyWebhookSignatureInput,
  ): Promise<boolean> {
    if (!this.stripe || !this.webhookSecret) {
      console.error("❌ Stripe not fully configured (missing keys)");
      return false;
    }
    if (!input.signatureHeader) return false;
    try {
      // SDK throws if signature is invalid or body has been tampered with.
      await this.stripe.webhooks.constructEventAsync(
        input.rawBody,
        input.signatureHeader,
        this.webhookSecret,
      );
      return true;
    } catch (err) {
      console.error(
        "Stripe webhook signature verification failed:",
        (err as Error).message,
      );
      return false;
    }
  }
}
