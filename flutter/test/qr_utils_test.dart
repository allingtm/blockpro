import 'package:blockpro/utils/qr_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('assetIdFromScan', () {
    const id = '1771864899143x375085884294525250';

    test('extracts the asset id from the on-site URL', () {
      expect(
        assetIdFromScan('https://app.blockpro.co.uk/on-site?asset=$id'),
        id,
      );
    });

    test('extracts the asset id regardless of other query params / order', () {
      expect(
        assetIdFromScan('https://app.blockpro.co.uk/on-site?foo=1&asset=$id'),
        id,
      );
    });

    test('trims surrounding whitespace', () {
      expect(assetIdFromScan('  https://app.blockpro.co.uk/on-site?asset=$id '),
          id);
    });

    test('accepts a bare Bubble id as a fallback', () {
      expect(assetIdFromScan(id), id);
      expect(assetIdFromScan('  $id  '), id);
    });

    test('matches the on-site host case-insensitively', () {
      expect(
        assetIdFromScan('https://APP.BLOCKPRO.CO.UK/on-site?asset=$id'),
        id,
      );
    });

    test('returns null for a URL without an asset param', () {
      expect(assetIdFromScan('https://app.blockpro.co.uk/on-site'), isNull);
      expect(assetIdFromScan('https://example.com/?asset='), isNull);
    });

    test('rejects an asset param on a foreign host', () {
      expect(assetIdFromScan('https://example.com/?asset=$id'), isNull);
      expect(assetIdFromScan('https://evil.com/on-site?asset=$id'), isNull);
      // Lookalike host that merely contains the real one is not a match.
      expect(
        assetIdFromScan('https://app.blockpro.co.uk.evil.com/?asset=$id'),
        isNull,
      );
    });

    test('rejects a malformed asset value on the on-site host', () {
      expect(
        assetIdFromScan('https://app.blockpro.co.uk/on-site?asset=hello'),
        isNull,
      );
      expect(
        assetIdFromScan('https://app.blockpro.co.uk/on-site?asset=12345'),
        isNull,
      );
    });

    test('returns null for unrelated / garbage payloads', () {
      expect(assetIdFromScan('just some text'), isNull);
      expect(assetIdFromScan(''), isNull);
      expect(assetIdFromScan('   '), isNull);
    });
  });
}
