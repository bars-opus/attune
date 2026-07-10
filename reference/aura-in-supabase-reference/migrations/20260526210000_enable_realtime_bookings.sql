-- Enable Realtime on the bookings table so the PaymentWebView's
-- Supabase stream subscription can detect <1s when the Paystack
-- webhook inserts a booking row. Without this, the subscription
-- silently connects but never emits, forcing the user to wait for
-- the slower DB poll (4-8s) or verify-payment fallback (15s+).
--
-- Realtime publications are not part of normal RLS or schema — they
-- must be explicitly opted-in per table.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'bookings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE bookings;
  END IF;
END $$;
