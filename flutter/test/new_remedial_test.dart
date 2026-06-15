import 'package:blockpro/models/asset.dart';
import 'package:blockpro/models/new_remedial.dart';
import 'package:blockpro/models/register_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Asset.registerItems', () {
    Asset asset(String? raw) => Asset(
          id: 'a1',
          buildingId: 'b1',
          taskName: 'Task',
          assetRegisterItems: raw,
        );

    test('parses the bracket-less comma-separated format', () {
      final items = asset(
        '{"registeritemref": "Wallbox1", "registeritemfloor": "1st", '
        '"registeritemlocation": "Landing"},'
        '{"registeritemref": "Wallbox2", "registeritemfloor": "1st", '
        '"registeritemlocation": "Landing"}',
      ).registerItems;

      expect(items.length, 2);
      expect(items.first.ref, 'Wallbox1');
      expect(items.first.floor, '1st');
      expect(items.first.location, 'Landing');
      expect(items.last.ref, 'Wallbox2');
    });

    test('parses an already-bracketed array', () {
      final items =
          asset('[{"registeritemref": "CP1"}]').registerItems;
      expect(items.single.ref, 'CP1');
      expect(items.single.floor, isNull);
    });

    test('returns empty for null, empty, and malformed input', () {
      expect(asset(null).registerItems, isEmpty);
      expect(asset('').registerItems, isEmpty);
      expect(asset('not json at all').registerItems, isEmpty);
    });
  });

  group('RegisterItem', () {
    test('displayLabel composes ref, floor and location', () {
      expect(
        const RegisterItem(ref: 'Wallbox1', floor: '1st', location: 'Landing')
            .displayLabel,
        'Wallbox1 — 1st, Landing',
      );
      expect(const RegisterItem(ref: 'Wallbox1').displayLabel, 'Wallbox1');
    });
  });

  group('NewRemedial', () {
    test('toJson uses API field names and omits empty optionals', () {
      const r = NewRemedial(title: '  Fix door  ', priority: 'High');
      final json = r.toJson();
      expect(json, {
        'remedialname': 'Fix door',
        'remedialpriority': 'High',
      });
    });

    test('round-trips all fields', () {
      const r = NewRemedial(
        title: 'Fix door',
        location: 'Lobby',
        description: 'Hinge broken',
        priority: 'Low',
        registerItems: [RegisterItem(ref: 'CP1', floor: 'G')],
      );
      final restored = NewRemedial.fromJson(r.toJson());
      expect(restored.title, 'Fix door');
      expect(restored.location, 'Lobby');
      expect(restored.description, 'Hinge broken');
      expect(restored.priority, 'Low');
      expect(restored.registerItems.single.ref, 'CP1');
      expect(restored.registerItems.single.floor, 'G');
    });

    test('isBlank when the trimmed title is empty', () {
      expect(const NewRemedial(title: '   ').isBlank, isTrue);
      expect(const NewRemedial(title: 'x').isBlank, isFalse);
    });

    test('fromJson defaults a missing priority to Low', () {
      expect(NewRemedial.fromJson({'remedialname': 'X'}).priority, 'Low');
    });
  });
}
