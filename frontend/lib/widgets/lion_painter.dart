import 'dart:math' show cos, sin;
import 'package:flutter/material.dart';

// ======================================================================
// 🦁 ボスライオンのPainter（叫んでいる姿）
// ======================================================================
class LionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);

    paint.color = const Color(0xFF8B4513);
    for (var angle = 0; angle < 360; angle += 15) {
      final rad = angle * 3.14159 / 180;
      final x = center.dx + 55 * cos(rad);
      final y = center.dy + 50 * sin(rad);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 25, height: 40),
        paint,
      );
    }

    paint.color = const Color(0xFFFFA500);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 80, height: 85),
      paint,
    );

    paint.color = const Color(0xFFFFE4B5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 25),
        width: 50,
        height: 40,
      ),
      paint,
    );

    paint.color = const Color(0xFF8B0000);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 32),
        width: 35,
        height: 25,
      ),
      paint,
    );

    paint.color = const Color(0xFF4A0000);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 35),
        width: 25,
        height: 15,
      ),
      paint,
    );

    paint.color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 10, center.dy + 20),
        width: 6,
        height: 14,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 10, center.dy + 20),
        width: 6,
        height: 14,
      ),
      paint,
    );

    paint.color = const Color(0xFF4A2F00);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 10),
        width: 16,
        height: 12,
      ),
      paint,
    );

    paint.color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 20, center.dy - 15),
        width: 24,
        height: 20,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 20, center.dy - 15),
        width: 24,
        height: 20,
      ),
      paint,
    );

    paint.color = Colors.black;
    canvas.drawCircle(Offset(center.dx - 20, center.dy - 15), 6, paint);
    canvas.drawCircle(Offset(center.dx + 20, center.dy - 15), 6, paint);

    paint.color = Colors.white;
    canvas.drawCircle(Offset(center.dx - 22, center.dy - 17), 2, paint);
    canvas.drawCircle(Offset(center.dx + 18, center.dy - 17), 2, paint);

    paint.color = const Color(0xFF5C3317);
    paint.strokeWidth = 4;
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - 32, center.dy - 32),
      Offset(center.dx - 10, center.dy - 28),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + 32, center.dy - 32),
      Offset(center.dx + 10, center.dy - 28),
      paint,
    );

    paint.style = PaintingStyle.fill;
    paint.color = const Color(0xFF8B4513);
    canvas.drawCircle(Offset(center.dx - 35, center.dy - 35), 15, paint);
    canvas.drawCircle(Offset(center.dx + 35, center.dy - 35), 15, paint);
    paint.color = const Color(0xFFFFB6C1);
    canvas.drawCircle(Offset(center.dx - 35, center.dy - 35), 8, paint);
    canvas.drawCircle(Offset(center.dx + 35, center.dy - 35), 8, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}