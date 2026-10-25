// supabase/functions/send-sms-hook/messages.ts
//
// Spec 1 §4.5: the code's words, per channel. No vendor, no name.

/// iOS fills the code from the domain-bound last line (and `other` gets the
/// same text); Android's SMS Retriever needs "<#>" first and the app's
/// 11-character hash last. Without a hash, Android gets the plain text and
/// the app's consent prompt reads it instead.
export function smsText(
  otp: string,
  platform: string,
  androidAppHash: string | undefined,
): string {
  const line = `Your Attune code is ${otp}. It expires in 10 minutes. Don't share it.`;
  if (platform === "android" && androidAppHash) {
    return `<#> ${line}\n${androidAppHash}`;
  }
  return `${line}\n\n@invite.attune.barsopus.com #${otp}`;
}

/// Read out twice, a digit at a time.
export function voiceText(otp: string): string {
  const digits = otp.split("").join(", ");
  return `Your Attune code is ${digits}. Again: ${digits}.`;
}
