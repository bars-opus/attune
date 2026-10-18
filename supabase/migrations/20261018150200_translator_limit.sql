-- Spec 8 (plan review I9): a per-person daily limit for the translator (it
-- had none). Counted by the server against auth.uid() only; nothing about
-- what was written is kept. Grants in 20261018150210.
CREATE TABLE IF NOT EXISTS public.translator_daily_use (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day date NOT NULL,
  uses int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);
ALTER TABLE public.translator_daily_use ENABLE ROW LEVEL SECURITY;

-- True (and counted) while today's uses are under 30.
CREATE OR REPLACE FUNCTION public.reserve_translator_use()
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_uses int;
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;
  INSERT INTO public.translator_daily_use AS t (user_id, day, uses)
  VALUES (v_uid, (now() AT TIME ZONE 'UTC')::date, 1)
  ON CONFLICT (user_id, day) DO UPDATE SET uses = t.uses + 1
  WHERE t.uses < 30
  RETURNING uses INTO v_uses;
  -- Keep a month of counts at most.
  DELETE FROM public.translator_daily_use
  WHERE user_id = v_uid AND day < (now() AT TIME ZONE 'UTC')::date - 30;
  RETURN v_uses IS NOT NULL;
END;
$$;
