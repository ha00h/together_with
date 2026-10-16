import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/models/page_insert.dart';
import 'package:together_with/models/stroke.dart';

Stroke _on(int page) => Stroke(
  id: 'p$page',
  pageIndex: page,
  tool: InkTool.pen,
  argb: 0xFF000000,
  widthNorm: 0.004,
  points: const [NormPoint(0.1, 0.1)],
  isPublic: false,
);

void main() {
  test('변경 기록은 저장 형식으로 오가도 그대로다', () {
    final ops = [
      const DocumentOp.blank(version: 2, at: 1, aspectRatio: 0.7),
      const DocumentOp.delete(version: 3, at: 0),
      const DocumentOp.append(version: 4, path: 'rooms/A/part-4.pdf'),
    ];
    final back = documentOpsFrom([for (final op in ops) op.toMap()]);
    expect(back.map((op) => op.type).toList(), [
      DocumentOpType.blank,
      DocumentOpType.delete,
      DocumentOpType.append,
    ]);
    expect(back[1].at, 0);
  });

  test('다시 들어온 참여자의 노트는 삽입과 삭제를 차례로 따라간다', () {
    final notes = [_on(0), _on(1), _on(2)];
    final shifts = pageShiftsOf(const [
      DocumentOp.blank(version: 2, at: 1, aspectRatio: 0.7),
      DocumentOp.delete(version: 3, at: 0),
    ]);
    final result = shiftForPageChanges(notes, shifts, fromVersion: 1);
    expect(
      {for (final stroke in result) stroke.id: stroke.pageIndex},
      {'p1': 1, 'p2': 2},
    );
    expect(shiftPage(2, shifts, fromVersion: 1), 2);
    expect(shiftPage(0, shifts, fromVersion: 1), 0);
    expect(shiftForPageChanges(notes, shifts, fromVersion: 3), notes);
  });
}
