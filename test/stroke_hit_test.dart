import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/models/stroke.dart';

void main() {
  const stroke = Stroke(
    id: 's',
    pageIndex: 0,
    tool: InkTool.pen,
    argb: 0xFF000000,
    widthNorm: 0.01,
    points: [NormPoint(0.1, 0.1), NormPoint(0.4, 0.1)],
    isPublic: true,
  );

  test('선분 위 점은 맞는다', () {
    expect(strokeHits(stroke, const NormPoint(0.25, 0.1)), isTrue);
  });

  test('멀리 떨어진 점은 빗나간다', () {
    expect(strokeHits(stroke, const NormPoint(0.25, 0.4)), isFalse);
  });
}
