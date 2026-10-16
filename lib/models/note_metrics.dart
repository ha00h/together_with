import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'stroke.dart';

double noteHeightNorm(String text, double aspectRatio) {
  const pageWidth = 1000.0;
  final ratio = aspectRatio <= 0 ? 1 / 1.4142 : aspectRatio;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: pageWidth * 0.028, height: 1.25),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: pageWidth * noteWidthNorm - 28);
  final pageHeight = pageWidth / ratio;
  final box = painter.height + 28;
  return (box / pageHeight).clamp(0.1, 0.5);
}

bool noteContains(Stroke note, NormPoint point) {
  if (!note.isNote || note.points.isEmpty) return false;
  return strokeHits(note, point, slop: 0);
}

bool noteFoldHit(Stroke note, NormPoint point) {
  if (!noteContains(note, point)) return false;
  final origin = note.points.first;
  final foldWidth = math.min(note.widthNorm * 0.28, 0.12);
  final foldBottom = origin.y +
      (note.folded ? note.noteBoxHeight : noteFoldHeightNorm);
  return point.x >= origin.x + note.widthNorm - foldWidth &&
      point.y <= foldBottom;
}
