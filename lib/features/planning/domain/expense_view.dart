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

/// What a chart slice stands for, which sets its colour: an expense or row
/// paid or not, a table row that is simply counted (its table has no yes/no
/// column), or what's left of the budget.
enum PlanningChartSlice { paid, unpaid, counted, left }

typedef PlanningChart = ({
  String currency,
  List<({String label, double value, PlanningChartSlice kind})> slices,
  bool otherCurrencies,
});

typedef PlanningChartLine = ({String label, int minor, String currency, PlanningChartSlice kind});

/// What an Expenses block's lines look like as a chart: a slice per line,
/// biggest first, in whole units of the currency with the most spent, each
/// paid or not. With [budgetLeft] in that currency and above zero, a last
/// slice shows what's left of the budget. Past [limit] slices the smallest
/// lines share one "Other", paid only if all of them are. Null with fewer
/// than two amounts, when a chart would say nothing. Other currencies are
/// left out, never converted, and [otherCurrencies] says so.
PlanningChart? planningExpenseChart(
  List<PlanningItem> items, {
  ({int minor, String currency})? budgetLeft,
  int limit = 8,
}) => _chart(
  [
    for (final i in items)
      if (i.amountMinor != null && i.currency != null)
        (
          label: i.text,
          minor: i.amountMinor!,
          currency: i.currency!,
          kind: i.isChecked ? PlanningChartSlice.paid : PlanningChartSlice.unpaid,
        ),
  ],
  budgetLeft: budgetLeft,
  limit: limit,
);

/// A Budget's breakdown: the lines of what it counts — every Expenses
/// block's, one Expenses block's, or a table's rows (named by their first
/// text cell, their money cells added up, paid by their first yes/no
/// column) — in the budget's currency, with what's left of its target.
PlanningChart? planningBudgetChart(
  PlanningBlock budget,
  List<PlanningBlock> blocks, {
  required String planCurrency,
  int limit = 8,
}) {
  final computed = budget.budget;
  final currency = budget.targetCurrency ?? planCurrency;
  final source = computed?.source ?? PlanningBudgetSource.all;
  final lines = <PlanningChartLine>[];
  if (source == PlanningBudgetSource.table) {
    final table = blocks.where((b) => b.id == computed?.sourceBlockId).firstOrNull;
    if (table == null) return null;
    final text = table.columns.where((c) => c.type == PlanningColumnType.text).firstOrNull;
    final money = [for (final c in table.columns) if (c.type == PlanningColumnType.money) c];
    final paid = table.columns.where((c) => c.type == PlanningColumnType.check).firstOrNull;
    for (final (n, row) in table.items.indexed) {
      final minor = money.fold<int>(0, (sum, c) {
        final v = row.cells[c.key];
        return v is num ? sum + v.toInt() : sum;
      });
      final label = text == null ? null : row.cells[text.key];
      lines.add((
        label: label is String && label.trim().isNotEmpty ? label : 'Row ${n + 1}',
        minor: minor,
        currency: planCurrency,
        kind: paid == null
            ? PlanningChartSlice.counted
            : (row.cells[paid.key] == true ? PlanningChartSlice.paid : PlanningChartSlice.unpaid),
      ));
    }
  } else {
    for (final b in blocks) {
      if (b.type != PlanningBlockType.expenses) continue;
      if (source == PlanningBudgetSource.expenses && b.id != computed?.sourceBlockId) continue;
      for (final i in b.items) {
        if (i.amountMinor == null || i.currency == null) continue;
        lines.add((
          label: i.text,
          minor: i.amountMinor!,
          currency: i.currency!,
          kind: i.isChecked ? PlanningChartSlice.paid : PlanningChartSlice.unpaid,
        ));
      }
    }
  }
  final target = budget.targetMinor;
  return _chart(
    lines,
    currency: currency,
    budgetLeft: target == null ? null : (minor: target - (computed?.spentMinor ?? 0), currency: currency),
    limit: limit,
  );
}

PlanningChart? _chart(
  List<PlanningChartLine> lines, {
  String? currency,
  ({int minor, String currency})? budgetLeft,
  int limit = 8,
}) {
  final totals = <String, int>{};
  for (final l in lines) {
    totals[l.currency] = (totals[l.currency] ?? 0) + l.minor;
  }
  if (totals.isEmpty) return null;
  final shown = currency ?? totals.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  var divisor = 1;
  for (var d = planningCurrencyDigits(shown); d > 0; d--) {
    divisor *= 10;
  }
  final kept = [
    for (final l in lines)
      if (l.currency == shown && l.minor > 0) (label: l.label, value: l.minor / divisor, kind: l.kind),
  ];
  if (kept.length < 2) return null;
  final indexed = [for (final (n, l) in kept.indexed) (n, l)]
    ..sort((a, b) {
      final byValue = b.$2.value.compareTo(a.$2.value);
      return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
    });
  var slices = [for (final (_, l) in indexed) l];
  final left = budgetLeft != null && budgetLeft.currency == shown && budgetLeft.minor > 0
      ? (label: 'Left in budget', value: budgetLeft.minor / divisor, kind: PlanningChartSlice.left)
      : null;
  final room = left == null ? limit : limit - 1;
  if (slices.length > room) {
    final rest = slices.skip(room - 1);
    final kinds = {for (final l in rest) l.kind};
    slices = [
      ...slices.take(room - 1),
      (
        label: 'Other',
        value: rest.fold<double>(0, (sum, l) => sum + l.value),
        // Paid (or counted) only if all of them are.
        kind: kinds.length == 1 ? kinds.single : PlanningChartSlice.unpaid,
      ),
    ];
  }
  return (
    currency: shown,
    slices: [...slices, if (left != null) left],
    otherCurrencies: totals.keys.any((c) => c != shown),
  );
}
