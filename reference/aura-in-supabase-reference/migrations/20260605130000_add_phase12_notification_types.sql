-- Phase 12 — extend notification_type enum with the three new categories
-- emitted by the autonomous retention loop.
--
-- Live DB confirmed `notification_type` is a custom enum
-- (typname = `notification_type`, query 2026-06-05). No defensive
-- discovery DO block needed; bare ALTER TYPE ... ADD VALUE IF NOT EXISTS
-- is idempotent.

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'rebook_nudge';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'review_request';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'recovery_checkin';
