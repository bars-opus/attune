# Chat sounds

`chat_send.wav` and `chat_receive.wav` are **placeholder** sine tones.

Before launch they must be replaced with the professionally-designed, warm,
short (~150–250ms) send/receive sounds approved in cultural/clinical review
(see the chat delight spec §3.6 and §7). Keep the same filenames so no code
changes are needed to swap them (real files may be .wav or re-encoded MP3 —
if switching to .mp3, update the two paths in
`lib/core/ui/feedback/sound_service.dart`).
