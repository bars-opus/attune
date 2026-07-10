-- ============================================================
-- Patch: honour p_selected_worker_ids in generate_available_slots
-- Deployed: 2026-05-25
--
-- The previous version accepted p_selected_worker_ids but never
-- used it — it always fetched workers from slot_worker_assignments.
-- When a client pre-selects a worker the client-side filter
-- (slot_generation_controller.dart:170) requires that worker to
-- appear in available_workers, but it never did, so every slot
-- was discarded.
--
-- Fix: when p_selected_worker_ids is non-empty, pass those IDs
-- directly to get_available_workers (check availability for the
-- chosen workers). Fall back to slot_worker_assignments only when
-- no workers are pre-selected.
-- ============================================================

CREATE OR REPLACE FUNCTION generate_available_slots(
  p_shop_id                 UUID,
  p_date                    DATE,
  p_service_ids             UUID[],
  p_quantities              INT[],
  p_selected_worker_ids     UUID[] DEFAULT NULL,
  p_default_buffer_minutes  INT    DEFAULT NULL
)
RETURNS TABLE (
  slot_id                    UUID,
  service_name               TEXT,
  start_time                 TIMESTAMPTZ,
  end_time                   TIMESTAMPTZ,
  actual_end_time            TIMESTAMPTZ,
  price                      NUMERIC,
  available_workers          JSONB,
  remaining_spots            INT,
  requires_worker_selection  BOOLEAN,
  buffer_minutes             INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dow         INT;
  v_opens       TIME;
  v_closes      TIME;
  v_closed      BOOLEAN;
  v_svc         RECORD;
  v_svc_id      UUID;
  v_qty         INT;
  v_t           TIMESTAMPTZ;
  v_end         TIMESTAMPTZ;
  v_actual_end  TIMESTAMPTZ;
  v_buffer      INT;
  v_workers     JSONB;
  v_worker_ids  UUID[];
  v_capacity    INT;
  v_taken       INT;
  v_dur_min     INT;
  v_i           INT;
  v_use_selected BOOLEAN;
BEGIN
  -- Determine whether the caller pre-selected specific workers.
  v_use_selected := (p_selected_worker_ids IS NOT NULL
                     AND cardinality(p_selected_worker_ids) > 0);

  v_dow := EXTRACT(DOW FROM p_date)::INT;
  SELECT opens_at, closes_at, COALESCE(is_closed, false)
    INTO v_opens, v_closes, v_closed
  FROM   shop_opening_hours
  WHERE  shop_id = p_shop_id AND day_of_week = v_dow
  LIMIT  1;

  IF NOT FOUND OR v_closed THEN
    RETURN;
  END IF;

  v_i := 1;
  FOREACH v_svc_id IN ARRAY p_service_ids LOOP
    v_qty := COALESCE(p_quantities[v_i], 1);
    v_i := v_i + 1;

    SELECT s.* INTO v_svc
    FROM   appointment_slots s
    WHERE  s.id = v_svc_id;

    IF NOT FOUND THEN CONTINUE; END IF;

    v_buffer  := COALESCE(v_svc.buffer_minutes, p_default_buffer_minutes, 0);
    v_dur_min := extract_duration_minutes(v_svc.duration);

    -- Which worker IDs to check: pre-selected takes priority.
    IF v_use_selected THEN
      v_worker_ids := p_selected_worker_ids;
    ELSE
      SELECT ARRAY(
        SELECT swa.worker_id
        FROM   slot_worker_assignments swa
        WHERE  swa.slot_id = v_svc.id
      ) INTO v_worker_ids;
    END IF;

    v_t := (p_date + v_opens)::TIMESTAMPTZ;
    WHILE v_t::TIME <= v_closes - (v_dur_min || ' minutes')::INTERVAL LOOP
      v_end        := v_t + (v_dur_min || ' minutes')::INTERVAL;
      v_actual_end := v_end + (v_buffer || ' minutes')::INTERVAL;

      SELECT COALESCE(jsonb_agg(w), '[]'::jsonb) INTO v_workers
      FROM (
        SELECT * FROM get_available_workers(v_worker_ids, v_t, v_end) AS w
      ) AS w;

      IF v_svc.slot_type = 'group' THEN
        SELECT count(*) INTO v_taken
        FROM   booking_services bs
        JOIN   bookings b ON b.id = bs.booking_id
        WHERE  bs.slot_id = v_svc.id
          AND  bs.start_time = v_t
          AND  b.status NOT IN ('cancelled', 'no_show');

        v_capacity := COALESCE(v_svc.max_clients, 1);
        IF v_capacity - v_taken >= v_qty THEN
          slot_id                   := v_svc.id;
          service_name              := v_svc.service_name;
          start_time                := v_t;
          end_time                  := v_end;
          actual_end_time           := v_actual_end;
          price                     := COALESCE(v_svc.price, 0);
          available_workers         := v_workers;
          remaining_spots           := v_capacity - v_taken;
          requires_worker_selection := COALESCE(v_svc.select_preferred_worker, false);
          buffer_minutes            := v_buffer;
          RETURN NEXT;
        END IF;
      ELSE
        IF jsonb_array_length(v_workers) > 0
           OR COALESCE(v_svc.select_preferred_worker, false) = false THEN
          slot_id                   := v_svc.id;
          service_name              := v_svc.service_name;
          start_time                := v_t;
          end_time                  := v_end;
          actual_end_time           := v_actual_end;
          price                     := COALESCE(v_svc.price, 0);
          available_workers         := v_workers;
          remaining_spots           := NULL;
          requires_worker_selection := COALESCE(v_svc.select_preferred_worker, false);
          buffer_minutes            := v_buffer;
          RETURN NEXT;
        END IF;
      END IF;

      v_t := v_t + INTERVAL '15 minutes';
    END LOOP;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION generate_available_slots(UUID, DATE, UUID[], INT[], UUID[], INT) FROM public;
GRANT EXECUTE ON FUNCTION generate_available_slots(UUID, DATE, UUID[], INT[], UUID[], INT) TO authenticated;
