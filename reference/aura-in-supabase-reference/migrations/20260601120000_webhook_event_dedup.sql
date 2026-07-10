-- Webhook event-ID idempotency table.
--
-- Both Paystack and Stripe replay events on transient failures (and Stripe
-- does so aggressively — multiple deliveries of the same event.id within
-- seconds is common during retries). The booking-row idempotency check we
-- already have catches `charge.success` replays for the same reference, but
-- doesn't catch:
--   * a wallet-credit replay (transfer.success → handleTransferSuccess)
--   * two different event types with overlapping side-effects
--   * any non-booking event we add later
--
-- The fix: insert the provider event_id at the top of the handler under a
-- UNIQUE constraint. ON CONFLICT DO NOTHING returns zero rows → the event
-- was already processed → return 200 without re-doing anything.

CREATE TABLE IF NOT EXISTS processed_webhook_events (
  -- Composite primary key: provider + event_id. Different providers can
  -- legitimately have the same event_id (different ID-spaces).
  provider     TEXT NOT NULL,
  event_id     TEXT NOT NULL,
  event_type   TEXT,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (provider, event_id)
);

-- Garbage collect after 30 days. Webhook providers don't replay older than
-- their own retention windows (Stripe: 3 days, Paystack: 72h).
CREATE INDEX IF NOT EXISTS processed_webhook_events_gc_idx
  ON processed_webhook_events (processed_at);

COMMENT ON TABLE processed_webhook_events IS
  'Idempotency log for webhook handlers. Insert event_id under UNIQUE before doing any side-effect; on conflict, the event was already processed — return 200.';
