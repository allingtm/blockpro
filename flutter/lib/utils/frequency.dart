/// Helpers for the free-text `frequency` field on assets (e.g. "7 Day(s)",
/// "1 Month(s)", "2 Week(s)", "1 Year(s)").
///
/// Used to optimistically recompute an asset's next due date locally after an
/// inspection is completed, so its card turns green immediately rather than
/// waiting for the next server sync.
library;

/// Parse a frequency string and return the next due date relative to
/// [from] (defaults to today). Returns `null` when the string can't be
/// confidently parsed — callers should then leave the due date unchanged and
/// rely on the next sync.
DateTime? nextDueDate(String? frequency, {DateTime? from}) {
  if (frequency == null) return null;
  final match = RegExp(r'(\d+)\s*([a-zA-Z]+)').firstMatch(frequency.trim());
  if (match == null) return null;

  final amount = int.tryParse(match.group(1)!);
  if (amount == null || amount <= 0) return null;

  final unit = match.group(2)!.toLowerCase();
  final base = from ?? DateTime.now();
  final day = DateTime(base.year, base.month, base.day);

  if (unit.startsWith('day')) {
    return day.add(Duration(days: amount));
  }
  if (unit.startsWith('week')) {
    return day.add(Duration(days: amount * 7));
  }
  if (unit.startsWith('month')) {
    return DateTime(day.year, day.month + amount, day.day);
  }
  if (unit.startsWith('year')) {
    return DateTime(day.year + amount, day.month, day.day);
  }
  return null;
}
