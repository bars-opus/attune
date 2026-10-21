-- Each person's own order for the movable cards on Conversations (below
-- the chat): Journals, Together, and any added later. Stored in
-- user_preferences, which is already private to its owner (RLS
-- preferences_private) and granted to authenticated. Null means the
-- default order. Card ids are short lowercase names; at most 20.
ALTER TABLE public.user_preferences
  ADD COLUMN IF NOT EXISTS home_card_order text[];

ALTER TABLE public.user_preferences
  DROP CONSTRAINT IF EXISTS user_preferences_home_card_order_ok;
ALTER TABLE public.user_preferences
  ADD CONSTRAINT user_preferences_home_card_order_ok CHECK (
    home_card_order IS NULL OR (
      cardinality(home_card_order) <= 20
      AND array_to_string(home_card_order, ',') ~ '^[a-z_]{1,32}(,[a-z_]{1,32})*$'
    )
  );
