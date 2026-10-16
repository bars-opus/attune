/// Whether this device can take a location fix for Attune right now.
/// Self-facing only: the partner never learns any of this.
enum LocationAccess { granted, denied, serviceOff }
