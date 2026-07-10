# Attune Context

Attune is a relationship intelligence product for couples. This glossary captures product-language decisions that should stay consistent across specs, code, copy, and implementation discussions.

## Language

**36 Questions Journey**:
The full Attune experience inspired by the 36 Questions tradition, completed across three chapters of twelve questions each. It is one journey made of multiple chapter sessions, not a single mandatory 36-question sitting.
_Avoid_: 36 Questions game as a single 12-question game, batch

**Chapter**:
One twelve-question part of the 36 Questions Journey, with a distinct vulnerability level: warm up, deeper, or vulnerable. A chapter starts only after both partners opt in to that chapter.
_Avoid_: Batch, level as the user-facing container

**Chapter Session**:
The concrete play session for one chapter of a 36 Questions Journey. Each chapter session has its own invitation, acceptance, expiry, rounds, and optional chapter reflection.
_Avoid_: One giant 36-round session

**Chapter Reflection**:
A small optional AI observation shown after a completed chapter when there is a clear shared theme. It is lighter than a final journey-level observation and must not make clinical or verdict-like claims.
_Avoid_: Insight report, diagnosis, score

**Journey Reflection**:
The final AI observation shown after all three chapters of a 36 Questions Journey are complete. It has more ceremony than a Chapter Reflection because it is earned across the full journey.
_Avoid_: Verdict, relationship report, compatibility assessment

**Answer Removal**:
A user's ability to remove their own vulnerable free-text answer from completed game history while preserving the chapter's structure. Removed answers are shown as intentionally removed, not silently erased from the shared record.
_Avoid_: Partner-controlled deletion, permanent exposure of vulnerable text

**Conflict Translator**:
A private, opt-in chat tool that helps the sender rewrite their own draft message into clearer need expression before sending. It is self-facing only: the recipient never knows a message was rewritten, and the tool must not appear automatically or frame the user's original message as wrong.
_Avoid_: Generic AI writing assistant, automatic rephrase suggestion, message fixer, recipient-visible rewrite label

**Communal Obligation Need**:
A proposed root-need category for conflicts shaped by family duties, community expectations, traditional practices, social respectability, or obligations beyond the couple. It is especially relevant for Ghanaian and West African relationship contexts and must remain review-gated until clinical/cultural validation.
_Avoid_: Forcing extended-family pressure into only autonomy or fairness, treating communal duty as inherently unhealthy

## Example Dialogue

Developer: "Should we start the next batch after the couple finishes the first twelve questions?"

Domain expert: "Call it a chapter, not a batch. A chapter is a human-facing part of the 36 Questions Journey, and both partners must opt in before the next one starts."

Developer: "Do we show the AI result after every chapter?"

Domain expert: "Yes, but the chapter reflection is small and optional. The journey reflection is the larger afterglow moment after all thirty-six questions are complete."
