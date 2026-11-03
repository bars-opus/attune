// supabase/functions/start-fresh-account/index.ts — see handler.ts.
// Public (verify_jwt = false in supabase/config.toml): the app calls it with
// no session, after the access-token hook refused a code sign-in with
// account_dormant:<nonce>.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { type FreshStartClient, handleFreshStart } from "./handler.ts";

serve((req) =>
  handleFreshStart(req, {
    client: serviceRoleClient() as unknown as FreshStartClient,
    ipKey: Deno.env.get("OTP_HMAC_KEY"),
    log: (category) => console.log("start-fresh-account", category),
  })
);
