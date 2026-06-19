import 'package:blockpro/models/asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The v2 API sends `tooltipurls` / `assetregisteritems` as real JSON arrays,
  // but they used to be cast `as String?` (which threw on a List). fromJson now
  // normalises either shape into a JSON string the getters can decode.
  group('Asset.fromJson blob normalization', () {
    Map<String, dynamic> base(Map<String, dynamic> extra) => {
          'assetId': 'a1',
          'buildingId': 'b1',
          'taskname': 'Fire alarm bell test',
          ...extra,
        };

    test('parses tooltipurls / assetregisteritems sent as JSON arrays', () {
      final asset = Asset.fromJson(base({
        'tooltiptext': 'Please check this.',
        'tooltipurls': [
          {'tooltipurl': 'https://blockpro.co.uk/'},
          {'tooltipurl': 'https://www.google.com/'},
        ],
        'assetregisteritems': [
          {
            'registeritemref': 'Wallbox1',
            'registeritemfloor': '1st',
            'registeritemlocation': 'Landing',
          },
        ],
      }));

      expect(asset.tooltipUrlList,
          ['https://blockpro.co.uk/', 'https://www.google.com/']);
      expect(asset.registerItems, hasLength(1));
      expect(asset.registerItems.first.ref, 'Wallbox1');
      expect(asset.hasTooltipInfo, isTrue);
    });

    test('still parses the legacy bracket-less string format', () {
      final asset = Asset.fromJson(base({
        'tooltipurls': '{"tooltipurl": "https://blockpro.co.uk/"}',
      }));

      expect(asset.tooltipUrlList, ['https://blockpro.co.uk/']);
      expect(asset.hasTooltipInfo, isTrue);
    });

    test('empty arrays, empty strings and absent fields normalise to null', () {
      final empties = [
        Asset.fromJson(base({'tooltipurls': [], 'assetregisteritems': []})),
        Asset.fromJson(base({'tooltipurls': '', 'tooltiptext': ''})),
        Asset.fromJson(base({})),
      ];
      for (final asset in empties) {
        expect(asset.tooltipUrls, isNull);
        expect(asset.tooltipUrlList, isEmpty);
        expect(asset.hasTooltipInfo, isFalse);
      }
    });
  });

  group('Asset placement (floor / location)', () {
    Map<String, dynamic> base(Map<String, dynamic> extra) => {
          'assetId': 'a1',
          'buildingId': 'b1',
          'taskname': 'Fire door inspection',
          ...extra,
        };

    test('parses floor and location and reports hasPlacementInfo', () {
      final asset = Asset.fromJson(base({
        'location': 'Next to stairwell',
        'floor': '1st floor',
      }));

      expect(asset.floor, '1st floor');
      expect(asset.location, 'Next to stairwell');
      expect(asset.hasPlacementInfo, isTrue);
    });

    test('empty strings and absent fields normalise to null', () {
      final empties = [
        Asset.fromJson(base({'location': '', 'floor': ''})),
        Asset.fromJson(base({})),
      ];
      for (final asset in empties) {
        expect(asset.floor, isNull);
        expect(asset.location, isNull);
        expect(asset.hasPlacementInfo, isFalse);
      }
    });

    test('hasPlacementInfo is true when only one of the two is present', () {
      expect(
        Asset.fromJson(base({'floor': '1st floor'})).hasPlacementInfo,
        isTrue,
      );
      expect(
        Asset.fromJson(base({'location': 'Next to stairwell'}))
            .hasPlacementInfo,
        isTrue,
      );
    });
  });

  group('Asset.hasTooltipInfo', () {
    Asset asset({String? text, List<String> urls = const []}) => Asset(
          id: 'a1',
          buildingId: 'b1',
          taskName: 'Task',
          tooltipText: text,
          tooltipUrls: urls.isEmpty
              ? null
              : '[${urls.map((u) => '{"tooltipurl": "$u"}').join(',')}]',
        );

    test('true when only text is present', () {
      expect(asset(text: 'Info').hasTooltipInfo, isTrue);
    });

    test('true when only urls are present', () {
      expect(asset(urls: ['https://x.test/']).hasTooltipInfo, isTrue);
    });

    test('true when both are present', () {
      expect(
        asset(text: 'Info', urls: ['https://x.test/']).hasTooltipInfo,
        isTrue,
      );
    });

    test('false when neither is present', () {
      expect(asset().hasTooltipInfo, isFalse);
    });
  });
}
