import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/features/home/create_room_screen.dart';
import 'package:together_with/features/home/home_screen.dart';
import 'package:together_with/features/workspace/workspace_screen.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/theme/app_theme.dart';

const _portrait = Size(744, 1133);
const _landscape = Size(1133, 744);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '아이패드 세로·가로 화면을 이미지로 저장한다',
    skip: Platform.environment['CAPTURE_SCREENS'] != '1',
    (tester) async {
      await tester.runAsync(_loadKoreanFont);
      final pagePath = (await tester.runAsync(_writeWorksheet))!;
      final out = Directory('screenshots');
      if (out.existsSync()) out.deleteSync(recursive: true);
      out.createSync();

      final shots = <_Shot>[
        _Shot('home-portrait', _portrait, const HomeScreen()),
        _Shot('home-landscape', _landscape, const HomeScreen()),
        _Shot('create-portrait', _portrait, const CreateRoomScreen()),
        _Shot('create-landscape', _landscape, const CreateRoomScreen()),
        _Shot(
          'workspace-portrait',
          _portrait,
          const WorkspaceScreen(),
          documentPath: pagePath,
        ),
        _Shot(
          'workspace-landscape',
          _landscape,
          const WorkspaceScreen(),
          documentPath: pagePath,
        ),
      ];

      for (final shot in shots) {
        await _capture(tester, shot, '${out.path}/${shot.name}.png');
      }

      expect(out.listSync().length, shots.length);
    },
  );
}

class _Shot {
  const _Shot(this.name, this.size, this.home, {this.documentPath});

  final String name;
  final Size size;
  final Widget home;
  final String? documentPath;
}

Future<void> _capture(WidgetTester tester, _Shot shot, String path) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final documentPath = shot.documentPath;
  if (documentPath != null) {
    container
        .read(sessionProvider.notifier)
        .openAsHost(
          title: '분수 수업',
          documentPath: documentPath,
          documentKind: DocumentKind.image,
        );
  }

  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(shot.size.width * 2, shot.size.height * 2);
  const padding = FakeViewPadding(top: 24, bottom: 20);
  tester.view.padding = padding;
  tester.view.viewPadding = padding;

  final theme = buildAppTheme();
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('shot'),
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'NanumSquareRound'),
            primaryTextTheme: theme.primaryTextTheme.apply(
              fontFamily: 'NanumSquareRound',
            ),
          ),
          home: shot.home,
        ),
      ),
    ),
  );
  await tester.pump();
  if (shot.documentPath != null) {
    for (var i = 0; i < 40; i++) {
      if (find.byType(RawImage).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(
      find.byType(RawImage),
      findsOneWidget,
      reason: '문서 이미지가 화면에 그려지지 않았습니다.',
    );
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadKoreanFont() async {
  final bytes = await File(
    '/Library/Fonts/NanumSquareRoundR.ttf',
  ).readAsBytes();
  final loader = FontLoader('NanumSquareRound')
    ..addFont(
      Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(bytes))),
    );
  await loader.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final icons = await File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  await (FontLoader('MaterialIcons')..addFont(
        Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(icons))),
      ))
      .load();
}

Future<String> _writeWorksheet() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(800, 1100);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 800, 8),
    Paint()..color = const Color(0xFF0F6E6B),
  );

  void text(String value, Offset offset, double fontSize) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'NanumSquareRound',
              fontSize: fontSize,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: const Color(0xFF1C1917),
              fontFamily: 'NanumSquareRound',
              fontSize: fontSize,
            ),
          )
          ..addText(value);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 720));
    canvas.drawParagraph(paragraph, offset);
  }

  text('분수 문제', const Offset(48, 48), 36);
  text('1. 색칠된 부분을 분수로 나타내시오.', const Offset(48, 120), 22);
  for (var i = 0; i < 4; i++) {
    canvas.drawRect(
      Rect.fromLTWH(48 + i * 90, 190, 80, 80),
      Paint()
        ..color = i < 3 ? const Color(0xFF0F6E6B) : const Color(0xFFFFFFFF)
        ..style = i < 3 ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
  text('2. 다음 식을 계산하시오.', const Offset(48, 320), 22);
  text('3/4 + 1/2 =', const Offset(48, 370), 28);
  for (var i = 0; i < 8; i++) {
    canvas.drawLine(
      Offset(48, 480 + i * 64),
      Offset(752, 480 + i * 64),
      Paint()..color = const Color(0xFFE7E1D8),
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${Directory.systemTemp.path}/together_with_worksheet.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file.absolute.path;
}
