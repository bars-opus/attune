-- Algorithm Quality Review Checklist v3.1, item 2.5 (P0-U): resource limits
-- must be enforced per request, not just at the client. quoted_text was
-- given no server-side cap when it was added (20260827120000) — the client
-- truncates to 60 chars before display, but a bypassed/crafted request
-- could still write an unbounded string, unlike content (capped at 10000
-- chars, 20260705120000_chat_system_v1_2.sql). 200 chars gives headroom
-- above the client's 60-char preview (which already appends "...") without
-- permitting an actually-unbounded row.
ALTER TABLE public.messages
  ADD CONSTRAINT messages_quoted_text_length
    CHECK (quoted_text IS NULL OR char_length(quoted_text) <= 200);
