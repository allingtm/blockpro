import 'package:flutter/material.dart';

/// White square frame with corner brackets and the word "BlockPro" inside.
/// Drawn by CustomPainter so we don't need a raster asset.
class BlockProLogo extends StatelessWidget {
  const BlockProLogo({
    super.key,
    this.size = 44,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BlockProLogoPainter(color: color),
      ),
    );
  }
}

class _BlockProLogoPainter extends CustomPainter {
  _BlockProLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final cornerLen = size.width * 0.30;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    final r = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final path = Path()
      // top-left
      ..moveTo(r.left, r.top + cornerLen)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + cornerLen, r.top)
      // top-right
      ..moveTo(r.right - cornerLen, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + cornerLen)
      // bottom-right
      ..moveTo(r.right, r.bottom - cornerLen)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - cornerLen, r.bottom)
      // bottom-left
      ..moveTo(r.left + cornerLen, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - cornerLen);
    canvas.drawPath(path, paint);

    final text = TextPainter(
      text: TextSpan(
        text: 'BlockPro',
        style: TextStyle(
          color: color,
          fontSize: size.width * 0.18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    text.paint(
      canvas,
      Offset(
        (size.width - text.width) / 2,
        (size.height - text.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _BlockProLogoPainter old) =>
      old.color != color;
}
