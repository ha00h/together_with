import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 화면을 가로로 눕힌 상태. 세로/가로 레이아웃을 가른다.
bool isLandscape(BuildContext context) {
  return MediaQuery.orientationOf(context) == Orientation.landscape;
}

/// iPad처럼 짧은 변이 넓은 화면. 같은 방향 안에서의 여백과 글자 크기에 쓴다.
bool isTablet(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide >= 600;
}

const tabletShortestSide = 600.0;

/// 폰은 세로만, 태블릿은 가로와 세로를 연다.
List<DeviceOrientation> orientationsForShortestSide(double shortestSide) {
  if (shortestSide >= tabletShortestSide) {
    return const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
  }
  return const [DeviceOrientation.portraitUp];
}

void applyOrientationPolicy(double shortestSide) {
  if (shortestSide <= 0) return;
  SystemChrome.setPreferredOrientations(
    orientationsForShortestSide(shortestSide),
  );
}
