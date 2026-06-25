// Helpers for interpreting scanned QR-code payloads.

/// Bubble ids look like `<digits>x<digits>`, e.g.
/// `1771864899143x375085884294525250`.
final _bubbleId = RegExp(r'^\d+x\d+$');

/// The host the production on-site QR codes point at. We only trust an `asset`
/// param when it arrives on this host, so an unrelated URL that happens to carry
/// an `asset` query param is rejected.
const _onSiteHost = 'app.blockpro.co.uk';

/// Pulls a Bubble asset id out of a scanned QR payload.
///
/// The QR codes in circulation encode the on-site URL, e.g.
/// `https://app.blockpro.co.uk/on-site?asset=1771864899143x375085884294525250`,
/// so we extract the `asset` query parameter — but only from our own
/// [_onSiteHost], and only when its value is a well-formed Bubble id. As a
/// tolerant fallback we also accept a bare Bubble id in case future codes encode
/// it directly. Returns `null` for anything else.
String? assetIdFromScan(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  final uri = Uri.tryParse(s);
  if (uri != null && uri.host.isNotEmpty) {
    // A URL: trust only our on-site host, and only a well-formed id. `Uri.host`
    // is already lowercased, so the host comparison is case-insensitive.
    if (uri.host != _onSiteHost) return null;
    final asset = uri.queryParameters['asset'];
    return (asset != null && _bubbleId.hasMatch(asset)) ? asset : null;
  }

  // Tolerant fallback: a bare Bubble id encoded directly.
  return _bubbleId.hasMatch(s) ? s : null;
}
