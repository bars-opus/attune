// supabase/functions/dating-device-check/index.ts
// Spec 2 W8b (§4.7): serves request.ts with the live user check, the
// service-role client and the IP table shipped as this function's static
// file (ip_country.bin, built at deploy time; none: every IP unresolved).
// The table is read once per instance (tableOnce); one that can't be used
// is logged once, as ip_table_unavailable.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { tableOnce } from "./ip_country.ts";
import { handleRequest } from "./request.ts";

const resolver = tableOnce(new URL("./ip_country.bin", import.meta.url));

serve((req) => handleRequest(req, { requireUser, client: serviceRoleClient, resolver }));
