import 'package:flutter/material.dart';

/// Original vector artwork; no external assets or network requests.
class JeepneyArt extends StatelessWidget {
  const JeepneyArt({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: const Size(300, 200), painter: _JeepneyPainter()),
  );
}

class _JeepneyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300, size.height / 200);
    final paint = Paint();
    void rect(
      double x,
      double y,
      double w,
      double h,
      Color color, [
      double radius = 4,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(radius),
        ),
        paint..color = color,
      );
    }

    const cream = Color(0xFFF5F1CE);
    const dark = Color(0xFF123C32);
    const light = Color(0xFFDBED9A);
    canvas.drawCircle(
      const Offset(170, 96),
      88,
      paint..color = const Color(0xFF2C7756),
    );
    canvas.drawOval(
      const Rect.fromLTWH(22, 163, 258, 18),
      paint..color = const Color(0xFF104C38),
    );
    canvas.drawPath(
      Path()
        ..moveTo(10, 148)
        ..lineTo(44, 148)
        ..moveTo(2, 133)
        ..lineTo(28, 133),
      paint
        ..color = light
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    paint.style = PaintingStyle.fill;
    rect(48, 74, 175, 69, cream, 12);
    rect(42, 65, 185, 11, light, 5);
    rect(57, 81, 35, 35, dark);
    rect(99, 81, 35, 35, dark);
    rect(141, 81, 35, 35, dark);
    rect(183, 81, 30, 35, dark);
    rect(65, 85, 3, 26, const Color(0xFF629580));
    rect(107, 85, 3, 26, const Color(0xFF629580));
    rect(149, 85, 3, 26, const Color(0xFF629580));
    rect(205, 111, 50, 32, cream, 6);
    rect(44, 128, 210, 22, light, 5);
    rect(39, 145, 224, 10, cream);
    rect(226, 119, 27, 9, dark, 2);
    rect(249, 132, 8, 8, const Color(0xFFFFD677), 3);
    rect(49, 133, 8, 7, const Color(0xFFE7A56A), 2);
    for (final x in [82.0, 219.0]) {
      canvas.drawCircle(Offset(x, 153), 19, paint..color = dark);
      canvas.drawCircle(Offset(x, 153), 10, paint..color = cream);
      canvas.drawCircle(
        Offset(x, 153),
        4,
        paint..color = const Color(0xFF82A883),
      );
    }
    rect(120, 132, 55, 11, dark, 3);
    rect(128, 136, 39, 3, cream, 1);
    rect(231, 90, 7, 18, cream, 3);
    rect(220, 96, 13, 3, cream, 1);
    canvas.drawCircle(const Offset(253, 50), 4, paint..color = light);
    canvas.drawCircle(const Offset(46, 46), 3, paint..color = light);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
