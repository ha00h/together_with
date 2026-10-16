import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/features/workspace/document_view.dart';
import 'package:together_with/features/workspace/workspace_screen.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/stroke.dart';
import 'package:together_with/state/session_controller.dart';

void main() {
  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .openAsHost(
          title: '수학',
          documentPath: '/tmp/missing-swipe.png',
          documentKind: DocumentKind.image,
          pageCount: 3,
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WorkspaceScreen()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  Future<void> twoFingers(
    WidgetTester tester,
    Offset delta, {
    bool withPencil = false,
  }) async {
    final center = tester.getCenter(find.byKey(const Key('page-stage')));
    TestGesture? pencil;
    if (withPencil) {
      pencil = await tester.startGesture(
        center + const Offset(0, 120),
        pointer: 9,
        kind: PointerDeviceKind.stylus,
      );
    }
    final a = await tester.startGesture(
      center - const Offset(0, 30),
      pointer: 1,
    );
    await tester.pump(const Duration(milliseconds: 16));
    final b = await tester.startGesture(
      center + const Offset(0, 30),
      pointer: 2,
    );
    for (var i = 0; i < 6; i++) {
      await a.moveBy(delta / 6);
      await b.moveBy(delta / 6);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await pencil?.up();
    await tester.pump();
  }

  testWidgets('두 손가락으로 밀면 페이지가 넘어가고 판서는 남지 않는다', (tester) async {
    final container = await open(tester);
    session() => container.read(sessionProvider)!;

    await twoFingers(tester, const Offset(-200, 0));
    expect(session().pageIndex, 1);
    expect(session().publicStrokes, isEmpty);
    expect(session().liveStroke, isNull);

    await twoFingers(tester, const Offset(-200, 0));
    expect(session().pageIndex, 2);
    await twoFingers(tester, const Offset(-200, 0));
    expect(session().pageIndex, 2);

    await twoFingers(tester, const Offset(200, 0));
    expect(session().pageIndex, 1);

    await twoFingers(tester, const Offset(-20, -200));
    expect(session().pageIndex, 1);
  });

  testWidgets('페이지가 바뀌면 새 페이지가 밀려 들어온다', (tester) async {
    final container = await open(tester);
    double opacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(DocumentView),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    expect(opacity(), 1);
    container.read(sessionProvider.notifier).goToPage(1);
    await tester.pump();
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(), 1);
  });

  testWidgets('한 손가락은 그대로 판서한다', (tester) async {
    final container = await open(tester);
    final center = tester.getCenter(find.byKey(const Key('page-stage')));
    final finger = await tester.startGesture(center);
    for (var i = 0; i < 6; i++) {
      await finger.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pump();
    final session = container.read(sessionProvider)!;
    expect(session.pageIndex, 0);
    expect(session.publicStrokes, hasLength(1));
  });

  Future<void> drawLine(WidgetTester tester, Offset from) async {
    final finger = await tester.startGesture(from);
    for (var i = 0; i < 6; i++) {
      await finger.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pump();
  }

  testWidgets('지우개로 문지르다 두 손가락으로 넘기면 판서는 지워지지 않는다', (tester) async {
    final container = await open(tester);
    session() => container.read(sessionProvider)!;
    final center = tester.getCenter(find.byKey(const Key('page-stage')));
    final line = center - const Offset(0, 30);
    await drawLine(tester, line);
    expect(session().publicStrokes, hasLength(1));
    container.read(sessionProvider.notifier).selectTool(CanvasTool.eraser);

    final a = await tester.startGesture(line - const Offset(60, 0), pointer: 1);
    for (var i = 0; i < 4; i++) {
      await a.moveBy(const Offset(-10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(session().publicStrokes, isEmpty);
    final b = await tester.startGesture(center + const Offset(0, 30), pointer: 2);
    await tester.pump();
    expect(session().publicStrokes, hasLength(1));
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(-30, 0));
      await b.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();

    expect(session().pageIndex, 1);
    expect(session().publicStrokes, hasLength(1));
    expect(session().publicStrokes.single.pageIndex, 0);
  });

  testWidgets('한 손가락 지우개는 그대로 지운다', (tester) async {
    final container = await open(tester);
    final center = tester.getCenter(find.byKey(const Key('page-stage')));
    await drawLine(tester, center);
    container.read(sessionProvider.notifier).selectTool(CanvasTool.eraser);
    await drawLine(tester, center - const Offset(20, 0));
    expect(container.read(sessionProvider)!.publicStrokes, isEmpty);
  });

  testWidgets('펜슬을 대고 있으면 두 손가락이 닿아도 넘기지 않는다', (tester) async {
    final container = await open(tester);
    await twoFingers(tester, const Offset(-200, 0), withPencil: true);
    expect(container.read(sessionProvider)!.pageIndex, 0);
  });
}
