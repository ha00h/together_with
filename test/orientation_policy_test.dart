import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/theme/form_factor.dart';

void main() {
  test('폰은 세로만 허용한다', () {
    expect(orientationsForShortestSide(390), [DeviceOrientation.portraitUp]);
  });

  test('태블릿은 가로와 세로를 허용한다', () {
    expect(orientationsForShortestSide(744), [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  });
}
