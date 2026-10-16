import '../models/stroke.dart';

Map<String, Object?> strokeToMap(Stroke stroke) {
  return {
    'id': stroke.id,
    'page': stroke.pageIndex,
    'tool': stroke.tool.name,
    'argb': stroke.argb,
    'width': stroke.widthNorm,
    'at': DateTime.now().millisecondsSinceEpoch,
    'points': [
      for (final point in stroke.points) {'x': point.x, 'y': point.y},
    ],
    if (stroke.text.isNotEmpty) 'text': stroke.text,
    if (stroke.heightNorm > 0) 'height': stroke.heightNorm,
    if (stroke.folded) 'folded': true,
  };
}

Stroke? strokeFromRemote(
  Object? raw, {
  String? fallbackId,
  bool isPublic = true,
}) {
  final map = asStringMap(raw);
  if (map == null) return null;
  final idValue = map['id'];
  final id = idValue is String && idValue.isNotEmpty ? idValue : fallbackId;
  if (id == null || id.isEmpty) return null;
  final points = pointsFromRemote(map['points']);
  if (points.isEmpty) return null;
  final tool = _tool(map['tool']);
  final page = map['page'];
  final argb = map['argb'];
  final width = map['width'];
  if (tool == null || page is! num || argb is! num || width is! num) {
    return null;
  }
  final text = map['text'] is String ? map['text'] as String : '';
  if (tool == InkTool.note && text.trim().isEmpty) return null;
  final height = map['height'];
  return Stroke(
    id: id,
    pageIndex: page.toInt(),
    tool: tool,
    argb: argb.toInt(),
    widthNorm: width.toDouble(),
    points: points,
    isPublic: isPublic,
    text: text,
    heightNorm: height is num ? height.toDouble() : 0,
    folded: map['folded'] == true,
  );
}

int strokeSortKey(Object? raw) {
  final at = asStringMap(raw)?['at'];
  if (at is num) return at.toInt();
  return 0;
}

Map<String, Object?>? asStringMap(Object? raw) {
  if (raw is! Map) return null;
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

List<NormPoint> pointsFromRemote(Object? raw) {
  final indexed = <int, NormPoint>{};
  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      final point = _point(raw[i]);
      if (point != null) indexed[i] = point;
    }
  } else if (raw is Map) {
    for (final entry in raw.entries) {
      final index = int.tryParse(entry.key.toString());
      final point = _point(entry.value);
      if (index == null || point == null) continue;
      indexed[index] = point;
    }
  }
  final keys = indexed.keys.toList()..sort();
  return [for (final key in keys) indexed[key]!];
}

NormPoint? _point(Object? raw) {
  final map = asStringMap(raw);
  if (map == null) return null;
  final x = map['x'];
  final y = map['y'];
  if (x is! num || y is! num) return null;
  return NormPoint(x.toDouble(), y.toDouble());
}

bool sameLivePreview(Stroke? previous, Stroke? next) {
  if (previous == null || next == null) {
    return previous == null && next == null;
  }
  if (previous.id != next.id || previous.pageIndex != next.pageIndex) {
    return false;
  }
  if (previous.points.length != next.points.length) return false;
  if (previous.points.isEmpty) return true;
  final before = previous.points.last;
  final after = next.points.last;
  return before.x == after.x && before.y == after.y;
}

bool sameStoredStroke(Stroke previous, Stroke next) {
  if (previous.id != next.id ||
      previous.pageIndex != next.pageIndex ||
      previous.tool != next.tool ||
      previous.text != next.text ||
      previous.folded != next.folded) {
    return false;
  }
  if (previous.points.length != next.points.length) return false;
  for (var i = 0; i < previous.points.length; i++) {
    if (previous.points[i] != next.points[i]) return false;
  }
  return true;
}

InkTool? _tool(Object? raw) {
  if (raw == InkTool.pen.name) return InkTool.pen;
  if (raw == InkTool.highlighter.name) return InkTool.highlighter;
  if (raw == InkTool.laser.name) return InkTool.laser;
  if (raw == InkTool.note.name) return InkTool.note;
  return null;
}
