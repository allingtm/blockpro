import 'package:blockpro/utils/asset_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed "now" so the cases don't depend on the wall clock.
  final now = DateTime(2026, 6, 16, 9, 30);
  DateTime day(int y, int m, int d) => DateTime(y, m, d);

  group('statusForDates', () {
    test('overdue due date is red, regardless of yellowDate', () {
      expect(
        statusForDates(dueDate: day(2026, 6, 15), now: now),
        AssetStatus.red,
      );
      // Red wins even if the yellow threshold also passed.
      expect(
        statusForDates(
            dueDate: day(2026, 6, 15), yellowDate: day(2026, 6, 1), now: now),
        AssetStatus.red,
      );
    });

    test('due today is not overdue (date-only comparison)', () {
      expect(
        statusForDates(dueDate: day(2026, 6, 16), now: now),
        AssetStatus.green,
      );
    });

    test('amber once today is on/after yellowDate but not yet overdue', () {
      // yellowDate in the past, due date in the future → amber.
      expect(
        statusForDates(
            dueDate: day(2026, 7, 1), yellowDate: day(2026, 6, 10), now: now),
        AssetStatus.amber,
      );
      // yellowDate is exactly today → amber (inclusive).
      expect(
        statusForDates(
            dueDate: day(2026, 7, 1), yellowDate: day(2026, 6, 16), now: now),
        AssetStatus.amber,
      );
    });

    test('green while today is before yellowDate', () {
      expect(
        statusForDates(
            dueDate: day(2026, 7, 1), yellowDate: day(2026, 6, 20), now: now),
        AssetStatus.green,
      );
    });

    test('no yellowDate means no amber phase — green until overdue', () {
      // A future due date with no yellow threshold stays green (the old 7-day
      // heuristic would have made this amber).
      expect(
        statusForDates(dueDate: day(2026, 6, 18), now: now),
        AssetStatus.green,
      );
    });

    test('no dates at all is green', () {
      expect(statusForDates(now: now), AssetStatus.green);
    });
  });
}
