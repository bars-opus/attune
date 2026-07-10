// supabase/functions/_shared/providers/registry.ts
import type { PaymentProviderName, PaymentProviderPort } from "./port.ts";
import { PaystackProvider } from "./paystack_provider.ts";
import { StripeProvider } from "./stripe_provider.ts";

// Factory map (not singleton) so adapters lazily construct. Importing this
// module is safe even when secrets for one provider are missing — the error
// is deferred to the moment `getProvider(name)` is called.
const adapters: Partial<Record<PaymentProviderName, () => PaymentProviderPort>> = {
  paystack: () => new PaystackProvider(),
  stripe: () => new StripeProvider(),
  // Add flutterwave/razorpay here when adapters exist.
};

export function getProvider(name: PaymentProviderName): PaymentProviderPort {
  const factory = adapters[name];
  if (!factory) {
    throw new Error(`Payment provider '${name}' is not configured`);
  }
  return factory();
}

export function isProviderEnabled(name: PaymentProviderName): boolean {
  return name in adapters;
}
