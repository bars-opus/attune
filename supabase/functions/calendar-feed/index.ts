// Together calendar feed (spec §6.4). Public by design (verify_jwt = false):
// the 256-bit link token is the credential; only its hash reaches the DB.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { handleFeedRequest } from "./handler.ts";
import type { FeedItem } from "./ics.ts";

serve((req) =>
  handleFeedRequest(req, async (hash) => {
    const { data, error } = await serviceRoleClient().rpc("together_calendar_feed", {
      p_token_hash: hash,
    });
    if (error) throw error;
    return (data as { items: FeedItem[] } | null) ?? null;
  })
);
