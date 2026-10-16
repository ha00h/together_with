import 'dart:math' as math;

enum InkTool { pen, highlighter, laser, note }

enum CanvasTool { pen, highlighter, eraser, laser, note }

const laserInk = 0xFFFF2D2D;
const notePaper = 0xFFFFF4B8;
const notePrivatePaper = 0xFFD6E8FF;
const noteInk = 0xFF1C1917;
const noteWidthNorm = 0.34;
const noteFoldHeightNorm = 0.072;

class NormPoint {
  const NormPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is NormPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class Stroke {
  const Stroke({
    required this.id,
    required this.pageIndex,
    required this.tool,
    required this.argb,
    required this.widthNorm,
    required this.points,
    required this.isPublic,
    this.text = '',
    this.heightNorm = 0,
    this.folded = false,
  });

  final String id;
  final int pageIndex;
  final InkTool tool;
  final int argb;
  final double widthNorm;
  final List<NormPoint> points;
  final bool isPublic;
  final String text;
  final double heightNorm;
  final bool folded;

  bool get isLaser => tool == InkTool.laser;

  bool get isNote => tool == InkTool.note;

  double get noteBoxHeight => folded ? noteFoldHeightNorm : heightNorm;

  Stroke copyWith({List<NormPoint>? points, bool? folded, int? pageIndex}) {
    return Stroke(
      id: id,
      pageIndex: pageIndex ?? this.pageIndex,
      tool: tool,
      argb: argb,
      widthNorm: widthNorm,
      points: points ?? this.points,
      isPublic: isPublic,
      text: text,
      heightNorm: heightNorm,
      folded: folded ?? this.folded,
    );
  }
}

NormPoint normalizePoint(double dx, double dy, double width, double height) {
  return NormPoint((dx / width).clamp(0.0, 1.0), (dy / height).clamp(0.0, 1.0));
}

bool strokeHits(Stroke stroke, NormPoint point, {double slop = 0.02}) {
  if (stroke.points.isEmpty) return false;
  if (stroke.isNote) {
    final origin = stroke.points.first;
    return point.x >= origin.x &&
        point.x <= origin.x + stroke.widthNorm &&
        point.y >= origin.y &&
        point.y <= origin.y + stroke.noteBoxHeight;
  }
  final threshold = math.max(slop, stroke.widthNorm / 2);
  if (stroke.points.length == 1) {
    return _distance(stroke.points.first, point) <= threshold;
  }
  for (var i = 0; i < stroke.points.length - 1; i++) {
    if (_distanceToSegment(point, stroke.points[i], stroke.points[i + 1]) <=
        threshold) {
      return true;
    }
  }
  return false;
}

double _distance(NormPoint a, NormPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _distanceToSegment(NormPoint point, NormPoint a, NormPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return _distance(point, a);
  final t = (((point.x - a.x) * dx) + ((point.y - a.y) * dy)) / lengthSquared;
  final clamped = t.clamp(0.0, 1.0);
  return _distance(point, NormPoint(a.x + clamped * dx, a.y + clamped * dy));
}
