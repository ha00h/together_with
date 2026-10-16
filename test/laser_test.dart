import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/archive/lesson_archive.dart';
import 'package:together_with/archive/lesson_renderer.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/stroke.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';
import 'package:together_with/sync/stroke_codec.dart';

import 'end_class_test.dart';

void main() {
  test('레이저 점은 획으로 저장되지 않고 손을 떼면 사라진다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          livePushIntervalProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    final hostBox = container();
    final host = hostBox.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    final code = hostBox.read(sessionProvider)!.joinCode;
    gateway.userId = 'guest-2';
    final guestBox = container();
    expect(
      await guestBox.read(sessionProvider.notifier).joinRoom(code),
      isNull,
    );

    gateway.userId = 'host-1';
    host.selectTool(CanvasTool.laser);
    const size = Size(200, 280);
    host.pointerDown(const Offset(30, 40), size);
    host.pointerMove(const Offset(120, 160), size);
    await pumpEventQueue();

    final shown = guestBox.read(sessionProvider)!;
    expect(shown.remoteLiveStroke?.isLaser, isTrue);
    expect(shown.publicStrokes, isEmpty);
    expect(gateway.strokeCount(code), 0);
    expect(inkForPage(hostBox.read(sessionProvider)!, 0), isEmpty);

    host.pointerUp();
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.remoteLiveStroke, isNull);
    expect(gateway.strokeCount(code), 0);
    expect(gateway.serverLive(code), isNull);
  });

  test('수업이 끝날 때 레이저는 공용 판서가 되지 않는다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final archive = MemoryLessonArchive();
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          lessonArchiveProvider.overrideWithValue(archive),
          livePushIntervalProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    final hostBox = container();
    final host = hostBox.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    final code = hostBox.read(sessionProvider)!.joinCode;
    gateway.userId = 'guest-2';
    final guestBox = container();
    expect(
      await guestBox.read(sessionProvider.notifier).joinRoom(code),
      isNull,
    );

    gateway.userId = 'host-1';
    host.selectTool(CanvasTool.laser);
    host.pointerDown(const Offset(30, 40), const Size(200, 280));
    await pumpEventQueue();

    await host.endClass();
    await pumpEventQueue();
    final guest = guestBox.read(sessionProvider)!;
    expect(guest.classEnded, isTrue);
    expect(guest.publicStrokes, isEmpty);
    expect(inkForPage(archive.sessions.single, 0), isEmpty);

    final saved = await guestBox.read(sessionProvider.notifier).endClass();
    expect(saved.ok, isTrue);
    expect(archive.sessions.last.publicStrokes, isEmpty);
  });

  test('레이저 표시는 주고받을 수 있다', () {
    const stroke = Stroke(
      id: 'dot',
      pageIndex: 0,
      tool: InkTool.laser,
      argb: laserInk,
      widthNorm: 0.02,
      points: [NormPoint(0.2, 0.3)],
      isPublic: true,
    );
    final decoded = strokeFromRemote(strokeToMap(stroke));
    expect(decoded?.isLaser, isTrue);
    expect(decoded?.points.single.x, closeTo(0.2, 0.0001));
  });

  test('레이저가 움직여도 같은 표시로 본다', () {
    const first = Stroke(
      id: 'dot',
      pageIndex: 0,
      tool: InkTool.laser,
      argb: laserInk,
      widthNorm: 0.02,
      points: [NormPoint(0.2, 0.3)],
      isPublic: true,
    );
    final moved = first.copyWith(points: const [NormPoint(0.8, 0.9)]);
    expect(sameLivePreview(first, first), isTrue);
    expect(sameLivePreview(first, moved), isFalse);
    expect(sameLivePreview(null, null), isTrue);
    expect(sameLivePreview(first, null), isFalse);
  });
}
