-- Weekly generation schedule (Spec §6.4) and the v1 config as a DRAFT.
--
-- Two deliberate safety properties here:
--
--   1. The config is inserted as state='draft', NOT 'active'. The table's
--      own CHECK refuses 'active' without clinical, product, fairness and
--      safety review refs -- Spec §2.1's gate-erosion pre-commitment
--      expressed as a constraint. This migration cannot and must not
--      activate it; a reviewer does that with the refs recorded.
--
--   2. run_dating_candidate_generation returns early unless
--      dating_candidate_generation is enabled AND an active config exists.
--      With the flag false and the config draft, the cron job runs weekly
--      and does nothing, which is what we want in place before launch: the
--      schedule is proven working long before it is allowed to write.

-- Jitter: a fixed minute past the hour rather than :00, so generation does
-- not contend with every other weekly job on the instance (§6.4 load
-- controls). Sunday 03:17 UTC is off-peak for the launch region.
SELECT cron.unschedule('dating-candidate-generation')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation');

SELECT cron.schedule(
  'dating-candidate-generation',
  '17 3 * * 0',
  $$SELECT public.run_dating_candidate_generation()$$
);

-- The v1 configuration. Every number the algorithm uses lives here rather
-- than in code (§6.2 forbids placeholder constants in the scorer), so
-- tuning is a reviewed config change with its own hash and review refs.
--
-- Weights are a starting proposal for clinical review, NOT approved values.
-- They are equal-weighted across the four dimensions on purpose: any other
-- split would be a clinical claim about which dimension predicts fit, and
-- nobody has reviewed such a claim yet.
--
-- love_language is absent, and its absence is load-bearing (§6.1). It is
-- not present with weight 0 -- a zero weight is one edit away from live.
INSERT INTO public.dating_algorithm_configs (version, state, config, config_hash)
VALUES (
  'alignment_v1',
  'draft',
  jsonb_build_object(
    'transform_version', 'alignment_v1_transforms_1',
    'weights', jsonb_build_object(
      'attachment_anxiety',   jsonb_build_object('kind','scalar','weight',1.0),
      'attachment_avoidance', jsonb_build_object('kind','scalar','weight',1.0),
      'communication_style',  jsonb_build_object('kind','scalar','weight',1.0),
      'conflict_style',       jsonb_build_object('kind','scalar','weight',1.0),
      'relationship_priorities', jsonb_build_object('kind','set','weight',1.0)
    ),
    -- Scale bounds per instrument. A rescaled quiz is a config change.
    'scales', jsonb_build_object(
      'attachment_anxiety',   jsonb_build_object('min',0,'max',100),
      'attachment_avoidance', jsonb_build_object('min',0,'max',100),
      'communication', jsonb_build_object('key','directness','min',0,'max',100),
      'conflict',      jsonb_build_object('key','repair','min',0,'max',100)
    ),
    -- Band thresholds on the normalized [0,1] score.
    'bands', jsonb_build_object('promising', 0.75, 'some', 0.5),
    -- Below this share of available evidence, no band above limited_signal
    -- may be shown regardless of score (§6.5 false precision).
    'min_confidence_for_band', 0.5,
    'reason_similar_threshold', 0.7,
    'max_reasons', 3,
    'max_open_introductions', 5,
    'introduction_ttl', '7 days',
    'scan_limit', 200,
    'batch_user_limit', 500,
    'max_attempts', 3,
    -- Maps a stated intention to the priority set that gets compared.
    -- Reviewed copy, not inferred.
    'intention_priorities', jsonb_build_object(
      'long_term',  jsonb_build_array('commitment','future_planning','stability'),
      'intentional', jsonb_build_array('commitment','emotional_depth','pace'),
      'friendship',  jsonb_build_array('companionship','shared_activities')
    ),
    -- §6.3 approved language. Every displayed reason comes from this table,
    -- keyed by a scored feature id -- never authored per pair, never by an
    -- LLM (§6.2 explainability fidelity).
    'phrases', jsonb_build_object(
      'communication_style', jsonb_build_object(
        'similar', 'You both described preferring a similar way of talking things through.',
        'differs', 'You may talk things through differently; that can be something to explore.'),
      'conflict_style', jsonb_build_object(
        'similar', 'You described approaching disagreements in similar ways.',
        'differs', 'You may approach conflict differently; that can be something to explore.'),
      'relationship_priorities', jsonb_build_object(
        'similar', 'You named several similar relationship priorities.',
        'differs', 'You named different relationship priorities.'),
      'attachment_anxiety', jsonb_build_object(
        'similar', 'You described needing similar amounts of reassurance.'),
      'attachment_avoidance', jsonb_build_object(
        'similar', 'You described needing similar amounts of space.')
    )
  ),
  'alignment_v1_draft_1'
)
ON CONFLICT (version) DO NOTHING;
