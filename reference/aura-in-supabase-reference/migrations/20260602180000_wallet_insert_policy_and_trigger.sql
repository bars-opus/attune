-- Allow shop owners to insert their own wallet row (client-side upsert path).
-- Previously only SELECT was allowed; INSERT was blocked by RLS, causing the
-- "Unable to create or fetch wallet" error on first load.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'wallets_owner_insert'
  ) THEN
    CREATE POLICY wallets_owner_insert ON wallets
      FOR INSERT TO authenticated
      WITH CHECK (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));
  END IF;
END $$;

-- Auto-create a wallet row whenever a shop is created, so the client never
-- needs to INSERT one manually.

CREATE OR REPLACE FUNCTION create_wallet_for_shop()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO wallets (shop_id)
  VALUES (NEW.id)
  ON CONFLICT (shop_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_wallet_on_shop_insert ON shops;

CREATE TRIGGER trg_create_wallet_on_shop_insert
  AFTER INSERT ON shops
  FOR EACH ROW EXECUTE FUNCTION create_wallet_for_shop();

-- Back-fill wallets for any existing shops that don't have one yet.
INSERT INTO wallets (shop_id)
SELECT id FROM shops
WHERE id NOT IN (SELECT shop_id FROM wallets)
ON CONFLICT (shop_id) DO NOTHING;
