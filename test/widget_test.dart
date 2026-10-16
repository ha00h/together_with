import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/app.dart';
import 'package:together_with/features/workspace/workspace_screen.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/session.dart';
import 'package:together_with/state/session_controller.dart';

void main() {
  testWidgets('홈에 수업 시작과 입장 코드가 있다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TogetherApp()));
    expect(find.text('함께 보자'), findsOneWidget);
    expect(find.text('발표자로 수업 열기'), findsOneWidget);
    expect(find.text('입장하기'), findsOneWidget);
  });

  testWidgets('세로는 아래 도구, 가로는 옆 도구', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .openAsHost(
          title: '수학',
          documentPath: '/tmp/missing.pdf',
          documentKind: DocumentKind.pdf,
        );

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WorkspaceScreen()),
        ),
      );
      await tester.pump();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAt(const Size(390, 844));
    expect(find.byKey(const Key('portrait-dock')), findsOneWidget);
    expect(find.byKey(const Key('landscape-rail')), findsNothing);

    await pumpAt(const Size(1024, 1366));
    expect(find.byKey(const Key('portrait-dock')), findsOneWidget);
    expect(find.text('펜'), findsWidgets);

    await pumpAt(const Size(1366, 1024));
    expect(find.byKey(const Key('landscape-rail')), findsOneWidget);
    expect(find.byKey(const Key('portrait-dock')), findsNothing);
    expect(find.text('공용'), findsOneWidget);
    expect(find.text('레이저'), findsOneWidget);
    expect(find.text('포스트잇'), findsOneWidget);

    container.read(sessionProvider.notifier).viewAs(MemberRole.participant);
    await tester.pump();
    expect(find.text('레이저'), findsNothing);
    expect(find.text('포스트잇'), findsOneWidget);
    expect(find.text('개인'), findsOneWidget);
  });
}
