import '../data/planning_models.dart';
import 'planning_money.dart';

/// How an Expenses block's lines are ordered on this device.
enum PlanningExpenseSort { added, lowest, highest }

/// Which partner's payments an Expenses block shows; null id is everyone.
class PlanningExpensePayer {
  const PlanningExpensePayer(this.id);
  final String? id;

  @override
  bool operator ==(Object other) => other is PlanningExpensePayer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One viewer's way of looking at an Expenses block. It changes only what
/// this person sees, never the expenses themselves.
class PlanningExpenseView {
  const PlanningExpenseView({this.sort = PlanningExpenseSort.added, this.paidBy});
  final PlanningExpenseSort sort;

  /// Show only what this member paid; null shows everyone's.
  final String? paidBy;

  PlanningExpenseView withSort(PlanningExpenseSort sort) => PlanningExpenseView(sort: sort, paidBy: paidBy);
  PlanningExpenseView withPayer(String? paidBy) => PlanningExpenseView(sort: sort, paidBy: paidBy);
}

/// [items] as [view] shows them. Amounts compare in whole currency units,
/// so ¥1,000 is not "more" than GH₵50 just for having no cents; a line
/// with no amount goes last either way. Ties keep the order added.
List<PlanningItem> planningExpenseRows(List<PlanningItem> items, PlanningExpenseView view) {
  final rows = [for (final i in items) if (view.paidBy == null || i.paidBy == view.paidBy) i];
  if (view.sort == PlanningExpenseSort.added) return rows;
  double? whole(PlanningItem i) {
    if (i.amountMinor == null) return null;
    var divisor = 1;
    for (var d = planningCurrencyDigits(i.currency ?? ''); d > 0; d--) {
      divisor *= 10;
    }
    return i.amountMinor! / divisor;
  }

  final indexed = [for (var n = 0; n < rows.length; n++) (n, rows[n], whole(rows[n]))];
  indexed.sort((a, b) {
    final (an, _, av) = a;
    final (bn, _, bv) = b;
    if (av == null || bv == null) {
      if (av == null && bv == null) return an.compareTo(bn);
      return av == null ? 1 : -1;
    }
    final byAmount = view.sort == PlanningExpenseSort.lowest ? av.compareTo(bv) : bv.compareTo(av);
    return byAmount != 0 ? byAmount : an.compareTo(bn);
  });
  return [for (final (_, item, _) in indexed) item];
}

/// Per currency: the sum of [items], and how much of it is marked paid.
Map<String, ({int total, int paid})> planningExpenseTotals(List<PlanningItem> items) {
  final out = <String, ({int total, int paid})>{};
  for (final i in items) {
    if (i.amountMinor == null || i.currency == null) continue;
    final t = out[i.currency!] ?? (total: 0, paid: 0);
    out[i.currency!] = (total: t.total + i.amountMinor!, paid: t.paid + (i.isChecked ? i.amountMinor! : 0));
  }
  return out;
}

/// What an Expenses chart slice stands for, which sets its colour.
enum PlanningChartSlice { paid, unpaid, left }

/// What an Expenses block's chart shows: a slice per line, biggest first,
/// in whole units of the currency with the most spent, each paid or not.
/// With [budgetLeft] in that currency and above zero, a last slice shows
/// what's left of the budget. Past [limit] slices the smallest lines share
/// one "Other", paid only if all of them are. Null with fewer than two
/// amounts, when a chart would say nothing. Other currencies are left out,
/// never converted, and [otherCurrencies] says so.
({
  String currency,
  List<({String label, double value, PlanningChartSlice kind})> slices,
  bool otherCurrencies,
})? planningExpenseChart(
  List<PlanningItem> items, {
  ({int minor, String currency})? budgetLeft,
  int limit = 8,
}) {
  final totals = planningExpenseTotals(items);
  if (totals.isEmpty) return null;
  final currency = totals.entries.reduce((a, b) => b.value.total > a.value.total ? b : a).key;
  var divisor = 1;
  for (var d = planningCurrencyDigits(currency); d > 0; d--) {
    divisor *= 10;
  }
  final lines = [
    for (final i in items)
      if (i.currency == currency && i.amountMinor != null && i.amountMinor! > 0)
        (
          label: i.text,
          value: i.amountMinor! / divisor,
          kind: i.isChecked ? PlanningChartSlice.paid : PlanningChartSlice.unpaid,
        ),
  ];
  if (lines.length < 2) return null;
  final indexed = [for (final (n, l) in lines.indexed) (n, l)]
    ..sort((a, b) {
      final byValue = b.$2.value.compareTo(a.$2.value);
      return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
    });
  var slices = [for (final (_, l) in indexed) l];
  final left = budgetLeft != null && budgetLeft.currency == currency && budgetLeft.minor > 0
      ? (label: 'Left in budget', value: budgetLeft.minor / divisor, kind: PlanningChartSlice.left)
      : null;
  final room = left == null ? limit : limit - 1;
  if (slices.length > room) {
    final rest = slices.skip(room - 1);
    slices = [
      ...slices.take(room - 1),
      (
        label: 'Other',
        value: rest.fold<double>(0, (sum, l) => sum + l.value),
        kind: rest.every((l) => l.kind == PlanningChartSlice.paid) ? PlanningChartSlice.paid : PlanningChartSlice.unpaid,
      ),
    ];
  }
  return (currency: currency, slices: [...slices, if (left != null) left], otherCurrencies: totals.length > 1);
}
