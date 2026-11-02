// Spec 1 W3 (D19): every device key a protective setting uses, in prefs or
// in the Safety PIN's secure storage. Quick exit may never remove one. No
// discreet-icon choice exists in the app yet (W3 plan P-14).
const protectiveKeys = {
  'me_section_lock',
  'safety_pin_hash',
  'safety_pin_failures',
  'safety_pin_retry_at',
  'safety_pin_last_failure_at',
  'safety_pin_every_open',
  'safety_pin_expected',
  'safety_requires_unlock',
};
