// supabase/functions/send-sms-hook/index.ts — see handler.ts.
// Called by Supabase Auth (Send SMS Hook), signed with
// SEND_SMS_HOOK_SECRET; verify_jwt = false in supabase/config.toml.
// Every database call carries the handler's AbortSignal (review M-6).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { type Decision, handleSendSms } from "./handler.ts";
import { providersFrom } from "./providers.ts";

serve((req) => {
  const db = serviceRoleClient();
  return handleSendSms(req, {
    hookSecret: Deno.env.get("SEND_SMS_HOOK_SECRET"),
    hmacKey: Deno.env.get("OTP_HMAC_KEY"),
    alreadySent: async (deliveryHmac, signal) => {
      const { data, error } = await db.rpc("otp_hook_delivery_sent", { p_delivery_hmac: deliveryHmac })
        .abortSignal(signal);
      if (error || typeof data !== "boolean") throw new Error("otp_hook_delivery_sent_failed");
      return data;
    },
    markSent: async (deliveryHmac, signal) => {
      const { error } = await db.rpc("otp_mark_hook_delivery_sent", { p_delivery_hmac: deliveryHmac })
        .abortSignal(signal);
      if (error) throw new Error("otp_mark_hook_delivery_sent_failed");
    },
    // Its own RPC, nothing else in its transaction: the prefix's advisory
    // lock is held until it commits. p_user_id: the account the code signs
    // in to, so an existing account's code goes by SMS (final review I-2).
    decide: async (phoneHmac, country, prefix, userId, signal) => {
      const { data, error } = await db.rpc("otp_take_send_decision", {
        p_phone_hmac: phoneHmac,
        p_country: country,
        p_calling_prefix: prefix,
        p_user_id: userId,
      }).abortSignal(signal);
      if (error || !data) throw new Error("otp_take_send_decision_failed");
      return data as Decision;
    },
    providers: providersFrom((name) => Deno.env.get(name)),
    androidAppHashes: (Deno.env.get("ANDROID_SMS_APP_HASHES") ?? "")
      .split(",")
      .map((hash) => hash.trim())
      .filter((hash) => hash.length === 11),
    bump: async (key, signal) => {
      await db.rpc("bump_metric_server", { p_key: key }).abortSignal(signal);
    },
    nowSeconds: () => Math.floor(Date.now() / 1000),
    nowMs: () => Date.now(),
    log: (category) => console.log("send-sms-hook", category),
  });
});
