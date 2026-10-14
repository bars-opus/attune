# UI sounds

`chat_send.wav` and `chat_receive.wav` are **placeholder** sine tones.

Before launch they must be replaced with the professionally-designed, warm,
short (~150–250ms) send/receive sounds approved in cultural/clinical review
(see the chat delight spec §3.6 and §7). Keep the same filenames so no code
changes are needed to swap them (real files may be .wav or re-encoded MP3 —
if switching to .mp3, update the two paths in
`lib/core/ui/feedback/sound_service.dart`).

## Game sounds

The Games UI calls `soundServiceProvider.play(AppSound.game*)` at the relevant
interaction beats. Paint Ball's five lightweight synthesized cues are checked
in and can be regenerated with `dart run tool/generate_paint_ball_sounds.dart`.
They are intentionally restrained and should still receive the same final
cultural/clinical sound review as the chat clips.

| File | Moment |
|------|--------|
| `game_match.wav` | This or That — both partners aligned (celebratory) |
| `game_card_flip.wav` | Truth or Dare — card flip |
| `game_reveal.wav` | round result / answer reveal |
| `game_tap.wav` | option / choice selection |
| `game_complete.wav` | session finished (end screen) |
| `game_fire.wav` | Paint Ball shot leaves cover |
| `game_hit.wav` | Paint Ball direct hit |
| `game_miss.wav` | Paint Ball miss/opening reveal |
| `game_knockout.wav` | Paint Ball final life |
| `game_penalty_reveal.wav` | losing partner sees their prompt |

**Wiring note (2026-10-14).** `game_hit`, `game_miss` and `game_knockout` were
generated and mapped here but played by no code at all, so the game's loudest
moment was silent. They are now played from
`paint_ball_provider.dart` via `paintBallRoundCue`, which also decides the
precedence: a knockout outranks the hit that caused it, and an opening shot
plays the miss cue because it resolves nothing.

The synthesis itself is better than earlier notes implied -- the generator
produces frequency-swept chirps, damped noise bursts, layered partials and
attack/release envelopes, not sine tones. **The cultural/clinical review gate
below still applies**: these are restrained placeholders, and nothing here
claims they have been reviewed.

## Streak sounds

Generated with `dart run tool/generate_streak_sounds.dart`. Capture gestures
remain haptic-only while the microphone is live so app audio is never baked
into the streak itself.

| File | Moment |
|------|--------|
| `streak_capture_ready.wav` | a valid take has stopped and is ready to review |
| `streak_send.wav` | the approved take enters the chat outbox |

Keep them short (~150–300ms), warm, and consistent with the chat sounds; run
them through the same cultural/clinical review before launch.

## Voice-note sounds

Generated with `dart run tool/generate_voice_note_sounds.dart`. Recording,
locking, pausing and resuming remain haptic-only while the microphone is live;
audio cues play only after the recorder has closed.

| File | Moment |
|------|--------|
| `voice_send.wav` | a valid voice note has stopped and enters the chat outbox |
| `voice_delete.wav` | the captured take has been discarded |
