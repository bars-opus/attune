/// G1's birth-year rules (Spec 1 §3.2): four digits, not after this year,
/// not before 1900. Under 18 by year alone goes to X1; exactly 18 passes,
/// because A2's full date decides.
enum GuestYearError { fourDigits, future, check }

GuestYearError? validateGuestYear(String text, {required int currentYear}) {
  final value = text.trim();
  if (!RegExp(r'^[0-9]{4}$').hasMatch(value)) return GuestYearError.fourDigits;
  final year = int.parse(value);
  if (year > currentYear) return GuestYearError.future;
  if (year < 1900) return GuestYearError.check;
  return null;
}

bool isUnder18ByYear(int year, {required int currentYear}) =>
    currentYear - year < 18;

/// The year on the person's own calendar at [now]: G1 compares against it,
/// not the UTC year, which on a 31 December evening west of Greenwich is
/// already the next one. [utcOffset] defaults to this device's offset at
/// [now]; tests pass it so the answer doesn't depend on the machine.
int localCalendarYear(DateTime now, {Duration? utcOffset}) =>
    now.toUtc().add(utcOffset ?? now.toLocal().timeZoneOffset).year;
