# UI sounds

`chat_send.wav` and `chat_receive.wav` are **placeholder** sine tones.

Before launch they must be replaced with the professionally-designed, warm,
short (~150–250ms) send/receive sounds approved in cultural/clinical review
(see the chat delight spec §3.6 and §7). Keep the same filenames so no code
changes are needed to swap them (real files may be .wav or re-encoded MP3 —
if switching to .mp3, update the two paths in
`lib/core/ui/feedback/sound_service.dart`).

## Games sounds (NOT YET ADDED — code seams live)

The Games UI already calls `soundServiceProvider.play(AppSound.game*)` at the
right moments. The clips below are referenced by
`AudioPlayerSoundService._assets` but are **not yet in this directory** — until
they are, each is a silent per-asset no-op (loading is guarded individually, so
missing game clips never break chat sounds). Drop the designed audio here with
these exact filenames and they activate with no code change:

| File | Moment |
|------|--------|
| `game_match.wav` | This or That — both partners aligned (celebratory) |
| `game_card_flip.wav` | Truth or Dare — card flip |
| `game_reveal.wav` | round result / answer reveal |
| `game_tap.wav` | option / choice selection |
| `game_complete.wav` | session finished (end screen) |

Keep them short (~150–300ms), warm, and consistent with the chat sounds; run
them through the same cultural/clinical review before launch.
