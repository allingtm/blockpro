import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/asset.dart';
import '../../theme/app_palettes.dart';
import '../../theme/app_theme_tokens.dart';

/// A compact info icon shown next to an asset title. Opens [showAssetInfoDialog]
/// with the asset's tooltip help (explanatory text + source links).
///
/// Renders nothing when the asset has no tooltip data, so callers can drop it
/// into a Row unconditionally. Its tap is handled by the IconButton, so it does
/// not trigger any surrounding card's onTap.
class AssetInfoButton extends StatelessWidget {
  const AssetInfoButton({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    if (!asset.hasTooltipInfo) return const SizedBox.shrink();
    final tokens = context.tokens;
    return IconButton(
      icon: const Icon(Icons.info_outline),
      iconSize: 20,
      color: tokens.brandIcon,
      tooltip: 'More information',
      padding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      onPressed: () => showAssetInfoDialog(context, asset),
    );
  }
}

/// Shows a modal with the asset's tooltip help. Sections hide independently when
/// their underlying field is empty.
Future<void> showAssetInfoDialog(BuildContext context, Asset asset) {
  final tokens = context.tokens;
  final text = asset.tooltipText;
  final urls = asset.tooltipUrlList;

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: tokens.cardSurface,
      title: Text(
        asset.displayName,
        style: TextStyle(fontWeight: FontWeight.w700, color: tokens.textStrong),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text != null && text.isNotEmpty) ...[
              _SectionHeader(title: 'What is it?'),
              const SizedBox(height: 8),
              Text(text, style: TextStyle(fontSize: 15, color: tokens.textMuted)),
            ],
            if (text != null && text.isNotEmpty && urls.isNotEmpty)
              const SizedBox(height: 20),
            if (urls.isNotEmpty) ...[
              _SectionHeader(title: 'Source(s)'),
              const SizedBox(height: 8),
              for (final url in urls)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: () => _launch(ctx, url),
                    child: Text(
                      url,
                      style: const TextStyle(
                        fontSize: 15,
                        color: kActionBlue,
                        decoration: TextDecoration.underline,
                        decorationColor: kActionBlue,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Section title with the app's hairline underline, echoing the design while
/// staying within the app theme.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: tokens.textStrong,
          ),
        ),
        const SizedBox(height: 6),
        Divider(height: 1, color: tokens.hairline),
      ],
    );
  }
}

/// Opens [url] in the external browser, showing a snackbar if it can't launch.
Future<void> _launch(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* fall through to snackbar */}
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}
