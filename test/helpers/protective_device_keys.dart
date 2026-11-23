// Spec 1 W3 (D19): every device key a protective setting uses, in prefs or
// in the Safety PIN's secure storage. Quick exit may never remove one. The
// discreet-icon choice (Spec 2 W8b, R-80) is the phone's own (a launcher
// alias, iOS's alternate icon), never a key the app writes.
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
