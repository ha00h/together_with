import 'stroke.dart';

/// `count` > 0 inserts pages before `at`; `count` < 0 removes pages from `at`.
class PageShift {
  const PageShift({
    required this.version,
    required this.at,
    required this.count,
  });

  final int version;
  final int at;
  final int count;

  bool get removes => count < 0;

  int get removedEnd => at - count;

  bool dropsPage(int page) => removes && page >= at && page < removedEnd;

  int mapPage(int page) {
    if (removes) {
      if (page >= removedEnd) return page + count;
      return page >= at ? at : page;
    }
    return page >= at ? page + count : page;
  }
}

enum DocumentOpType { blank, append, delete }

class DocumentOp {
  const DocumentOp.blank({
    required this.version,
    required int this.at,
    required double this.aspectRatio,
  }) : type = DocumentOpType.blank,
       path = null;

  const DocumentOp.append({required this.version, required String this.path})
    : type = DocumentOpType.append,
      at = null,
      aspectRatio = null;

  const DocumentOp.delete({required this.version, required int this.at})
    : type = DocumentOpType.delete,
      aspectRatio = null,
      path = null;

  final DocumentOpType type;
  final int version;
  final int? at;
  final double? aspectRatio;
  final String? path;

  PageShift? get shift => switch (type) {
    DocumentOpType.blank => PageShift(version: version, at: at!, count: 1),
    DocumentOpType.delete => PageShift(version: version, at: at!, count: -1),
    DocumentOpType.append => null,
  };

  Map<String, Object?> toMap() => switch (type) {
    DocumentOpType.blank => {
      'v': version,
      'type': 'blank',
      'at': at,
      'aspect': aspectRatio,
    },
    DocumentOpType.append => {'v': version, 'type': 'append', 'path': path},
    DocumentOpType.delete => {'v': version, 'type': 'delete', 'at': at},
  };
}

List<DocumentOp> documentOpsFrom(Object? raw) {
  if (raw is! List) return const [];
  final ops = <DocumentOp>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final version = item['v'];
    if (version is! num) continue;
    final at = item['at'];
    switch (item['type']) {
      case 'blank':
        final aspect = item['aspect'];
        if (at is! num || aspect is! num) continue;
        ops.add(
          DocumentOp.blank(
            version: version.toInt(),
            at: at.toInt(),
            aspectRatio: aspect.toDouble(),
          ),
        );
      case 'append':
        final path = item['path'];
        if (path is! String || path.isEmpty) continue;
        ops.add(DocumentOp.append(version: version.toInt(), path: path));
      case 'delete':
        if (at is! num) continue;
        ops.add(DocumentOp.delete(version: version.toInt(), at: at.toInt()));
    }
  }
  ops.sort((a, b) => a.version.compareTo(b.version));
  return ops;
}

List<PageShift> pageShiftsOf(List<DocumentOp> ops) => [
  for (final op in ops) ?op.shift,
];

List<Stroke> shiftForPageChanges(
  List<Stroke> strokes,
  List<PageShift> shifts, {
  required int fromVersion,
}) {
  var result = strokes;
  for (final shift in shifts) {
    if (shift.version <= fromVersion) continue;
    result = [
      for (final stroke in result)
        if (!shift.dropsPage(stroke.pageIndex))
          shift.mapPage(stroke.pageIndex) == stroke.pageIndex
              ? stroke
              : stroke.copyWith(pageIndex: shift.mapPage(stroke.pageIndex)),
    ];
  }
  return result;
}

int shiftPage(int page, List<PageShift> shifts, {required int fromVersion}) {
  var result = page;
  for (final shift in shifts) {
    if (shift.version > fromVersion) result = shift.mapPage(result);
  }
  return result;
}
