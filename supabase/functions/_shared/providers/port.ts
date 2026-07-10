// supabase/functions/_shared/providers/port.ts
//
// Provider-agnostic payment port. Adapters in this directory implement this
// interface; edge functions call through `registry.getProvider(name)` instead
// of branching on provider name.

export type PaymentProviderName =
  | "paystack"
  | "stripe"
  | "flutterwave"
  | "razorpay";

export interface InitCheckoutInput {
  /** Major units (e.g. 50.00, not 5000). Adapters convert to minor. */
  amount: number;
  /** ISO 4217, uppercased. */
  currency: string;
  /** Caller-controlled idempotency key. Forwarded to provider-native idempotency. */
  reference: string;
  customerEmail: string;
  /** Deep-link back into the app (e.g. nanoembryo://payment-success). */
  callbackUrl: string;
  metadata?: Record<string, string>;
  /** Paystack subaccount code or Stripe connected account id. */
  destinationAccountId?: string;
  /** Major units, taken from the gross before destination split. */
  platformFeeAmount?: number;
}

export interface InitCheckoutResult {
  checkoutUrl: string;
  providerReference: string;
  expiresAt?: string;
}

export interface VerifyTransactionInput {
  reference: string;
}

export interface VerifyTransactionResult {
  status: "success" | "pending" | "failed" | "abandoned";
  /** Major units. */
  amount: number;
  currency: string;
  paidAt?: string;
  providerTransactionId: string;
}

export interface ProcessPayoutInput {
  amount: number;
  currency: string;
  destinationAccountId: string;
  reference: string;
  reason?: string;
}

export interface ProcessPayoutResult {
  status: "pending" | "success" | "failed";
  providerTransferId: string;
  estimatedArrival?: string;
}

export interface VerifyWebhookSignatureInput {
  rawBody: string;
  signatureHeader: string;
}

export interface PaymentProviderPort {
  readonly name: PaymentProviderName;
  initCheckout(input: InitCheckoutInput): Promise<InitCheckoutResult>;
  verifyTransaction(
    input: VerifyTransactionInput,
  ): Promise<VerifyTransactionResult>;
  processPayout(input: ProcessPayoutInput): Promise<ProcessPayoutResult>;
  verifyWebhookSignature(input: VerifyWebhookSignatureInput): Promise<boolean>;
}

export type PaymentErrorCategory =
  | "declined"
  | "insufficient_funds"
  | "invalid_request"
  | "unavailable"
  | "rate_limit"
  | "unknown";

export class PaymentProviderError extends Error {
  constructor(
    message: string,
    readonly category: PaymentErrorCategory,
    readonly retryable: boolean,
    readonly providerCode?: string,
    readonly providerRaw?: unknown,
  ) {
    super(message);
    this.name = "PaymentProviderError";
  }
}
