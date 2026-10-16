import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/stroke.dart';

class StrokePainter extends CustomPainter {
  StrokePainter({required this.strokes, this.expandNotes = false});

  final List<Stroke> strokes;
  final bool expandNotes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final notes = <Stroke>[];
    for (final stroke in strokes) {
      if (stroke.isNote) {
        notes.add(stroke);
      } else {
        _paintStroke(canvas, size, stroke);
      }
    }
    for (final note in notes) {
      _paintNote(canvas, size, note);
    }
  }

  void _paintStroke(Canvas canvas, Size size, Stroke stroke) {
    if (stroke.points.isEmpty) return;
    if (stroke.isLaser) {
      _paintLaser(canvas, size, stroke);
      return;
    }
    final paint = Paint()
      ..color = Color(stroke.argb)
      ..strokeWidth = (stroke.widthNorm * size.width).clamp(1, 64)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (stroke.points.length == 1) {
      final point = stroke.points.first;
      canvas.drawCircle(
        Offset(point.x * size.width, point.y * size.height),
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    final first = stroke.points.first;
    path.moveTo(first.x * size.width, first.y * size.height);
    for (var i = 1; i < stroke.points.length - 1; i++) {
      final current = stroke.points[i];
      final next = stroke.points[i + 1];
      path.quadraticBezierTo(
        current.x * size.width,
        current.y * size.height,
        ((current.x + next.x) / 2) * size.width,
        ((current.y + next.y) / 2) * size.height,
      );
    }
    final last = stroke.points.last;
    path.lineTo(last.x * size.width, last.y * size.height);
    canvas.drawPath(path, paint);
  }

  void _paintLaser(Canvas canvas, Size size, Stroke stroke) {
    final offsets = [
      for (final point in stroke.points)
        Offset(point.x * size.width, point.y * size.height),
    ];
    final color = Color(stroke.argb);
    if (offsets.length > 1) {
      for (var i = 1; i < offsets.length; i++) {
        final fade = i / (offsets.length - 1);
        canvas.drawLine(
          offsets[i - 1],
          offsets[i],
          Paint()
            ..color = color.withValues(alpha: 0.12 + 0.4 * fade)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
    }
    final tip = offsets.last;
    final radius = (size.shortestSide * 0.018).clamp(7.0, 16.0);
    canvas.drawCircle(
      tip,
      radius * 2.2,
      Paint()..color = color.withValues(alpha: 0.28),
    );
    canvas.drawCircle(tip, radius, Paint()..color = color);
    canvas.drawCircle(
      tip,
      radius * 0.35,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  void _paintNote(Canvas canvas, Size size, Stroke stroke) {
    if (stroke.points.isEmpty || stroke.text.isEmpty) return;
    final folded = stroke.folded && !expandNotes;
    final origin = stroke.points.first;
    final heightNorm = folded
        ? noteFoldHeightNorm
        : math.max(stroke.heightNorm, noteFoldHeightNorm);
    final rect = Rect.fromLTWH(
      origin.x * size.width,
      origin.y * size.height,
      stroke.widthNorm * size.width,
      heightNorm * size.height,
    );
    final radius = Radius.circular((rect.shortestSide * 0.12).clamp(4, 12));
    final card = RRect.fromRectAndRadius(rect, radius);
    canvas.drawRRect(
      card.shift(const Offset(1.5, 2)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(card, Paint()..color = Color(stroke.argb));
    canvas.drawRRect(
      card,
      Paint()
        ..color = const Color(0xFFE4D48A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final pad = (rect.width * 0.08).clamp(6.0, 16.0);
    final foldWidth = math.min(rect.width * 0.28, rect.width * 0.34);
    canvas.save();
    canvas.clipRRect(card);
    if (folded) {
      final headerText = TextPainter(
        text: TextSpan(
          text: stroke.text,
          style: TextStyle(
            color: const Color(noteInk),
            fontSize: (size.width * 0.026).clamp(11, 20),
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(8, rect.width - foldWidth - pad));
      headerText.paint(
        canvas,
        Offset(rect.left + pad, rect.top + (rect.height - headerText.height) / 2),
      );
    } else {
      final body = TextPainter(
        text: TextSpan(
          text: stroke.text,
          style: TextStyle(
            color: const Color(noteInk),
            fontSize: (size.width * 0.028).clamp(11, 22),
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(8, rect.width - pad * 2 - foldWidth));
      body.paint(canvas, Offset(rect.left + pad, rect.top + pad * 0.7));
    }
    canvas.restore();
    final foldStrip = folded ? rect.height : noteFoldHeightNorm * size.height;
    _paintChevron(
      canvas,
      Offset(rect.right - foldWidth / 2, rect.top + foldStrip / 2),
      math.min(7, foldStrip * 0.22),
      folded,
    );
  }

  void _paintChevron(Canvas canvas, Offset center, double span, bool folded) {
    final path = Path();
    if (folded) {
      path.moveTo(center.dx - span, center.dy - span * 0.35);
      path.lineTo(center.dx, center.dy + span * 0.4);
      path.lineTo(center.dx + span, center.dy - span * 0.35);
    } else {
      path.moveTo(center.dx - span, center.dy + span * 0.35);
      path.lineTo(center.dx, center.dy - span * 0.4);
      path.lineTo(center.dx + span, center.dy + span * 0.35);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(noteInk)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(StrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.expandNotes != expandNotes;
}
