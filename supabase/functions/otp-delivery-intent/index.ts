// supabase/functions/otp-delivery-intent/index.ts — see handler.ts.
// Public (verify_jwt = false in supabase/config.toml): the app calls it
// before sign-in. Per-IP and per-number caps live in otp_record_intent.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { handleIntent } from "./handler.ts";

serve((req) =>
  handleIntent(req, {
    hmacKey: Deno.env.get("OTP_HMAC_KEY"),
    record: async (intent) => {
      const { error } = await serviceRoleClient().rpc("otp_record_intent", intent);
      if (error) throw new Error("otp_record_intent_failed");
    },
    log: (category) => console.log("otp-delivery-intent", category),
  })
);
