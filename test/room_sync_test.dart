import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/session.dart';
import 'package:together_with/models/stroke.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';
import 'package:together_with/sync/stroke_codec.dart';

void main() {
  test('획 JSON은 배열이든 맵이든 같은 점으로 돌아온다', () {
    const stroke = Stroke(
      id: 's1',
      pageIndex: 2,
      tool: InkTool.highlighter,
      argb: 0xFFB91C1C,
      widthNorm: 0.02,
      points: [NormPoint(0.1, 0.2), NormPoint(0.4, 0.8)],
      isPublic: true,
    );
    final decoded = strokeFromRemote(strokeToMap(stroke));
    expect(decoded, isNotNull);
    expect(decoded!.id, 's1');
    expect(decoded.pageIndex, 2);
    expect(decoded.tool, InkTool.highlighter);
    expect(decoded.points.last.y, closeTo(0.8, 0.0001));
    expect(decoded.isPublic, isTrue);

    final fromMap = strokeFromRemote({
      'id': 's2',
      'page': 0,
      'tool': 'pen',
      'argb': 1,
      'width': 0.01,
      'points': {
        '1': {'x': 0.6, 'y': 0.7},
        '0': {'x': 0.2, 'y': 0.3},
      },
    });
    expect(fromMap!.points.map((point) => point.x), [0.2, 0.6]);
    expect(strokeFromRemote({'tool': 'nope'}), isNull);
  });

  test('발표자 판서와 페이지가 다른 입장자에게 전달된다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final store = MemoryActiveRoomStore();
    final privateNotes = MemoryPrivateStrokeStore();

    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(store),
          privateStrokeStoreProvider.overrideWithValue(privateNotes),
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
    const size = Size(200, 280);
    host.pointerDown(const Offset(20, 30), size);
    host.pointerMove(const Offset(80, 90), size);
    final code = hostBox.read(sessionProvider)!.joinCode;
    expect(gateway.serverLive(code), isNotNull);

    host.pointerUp();
    await pumpEventQueue();
    expect(gateway.strokeCount(code), 1);

    gateway.userId = 'guest-2';
    final guestBox = container();
    final guest = guestBox.read(sessionProvider.notifier);
    expect(await guest.joinRoom(code.toLowerCase()), isNull);
    final joined = guestBox.read(sessionProvider)!;
    expect(joined.role, MemberRole.participant);
    expect(joined.openedOnThisDevice, isFalse);
    expect(joined.publicStrokes, hasLength(1));
    expect(joined.pageIndex, 0);
    expect(joined.networked, isTrue);

    guest.pointerDown(const Offset(40, 40), size);
    guest.pointerUp();
    await pumpEventQueue();
    expect(gateway.strokeCount(code), 1);
    expect(guestBox.read(sessionProvider)!.privateStrokes, hasLength(1));

    host.selectTool(CanvasTool.eraser);
    host.pointerDown(const Offset(20, 30), size);
    host.pointerUp();
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.publicStrokes, isEmpty);

    host.selectTool(CanvasTool.pen);
    host.attachDocument(pageCount: 3, aspectRatio: 1.2);
    expect(hostBox.read(sessionProvider)!.pageCount, 3);
    host.goToPage(2);
    await pumpEventQueue();
    expect(hostBox.read(sessionProvider)!.pageIndex, 2);
    expect(gateway.serverPage(code), 2);
    expect(guestBox.read(sessionProvider)!.pageIndex, 2);
    guest.goToPage(0);
    expect(guestBox.read(sessionProvider)!.pageIndex, 2);
    expect(store.code, code);

    guest.closeSession();
    final returned = container();
    expect(
      await returned.read(sessionProvider.notifier).joinRoom(code),
      isNull,
    );
    final restored = returned.read(sessionProvider)!;
    expect(restored.role, MemberRole.participant);
    expect(restored.privateStrokes, hasLength(1));
    expect(restored.privateStrokes.single.isPublic, isFalse);
    expect(restored.pageIndex, 2);
    expect(gateway.strokeCount(code), 0);
  });

  test('서버에 없는 미완료 획은 발표자가 다시 들어오면 복구된다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
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
    host.pointerDown(const Offset(20, 30), const Size(200, 280));
    final code = hostBox.read(sessionProvider)!.joinCode;
    gateway.dropServerLive(code);

    final rejoined = container();
    expect(
      await rejoined.read(sessionProvider.notifier).joinRoom(code),
      isNull,
    );
    expect(rejoined.read(sessionProvider)!.role, MemberRole.host);
    expect(rejoined.read(sessionProvider)!.remoteLiveStroke, isNotNull);
    expect(
      await rejoined.read(sessionProvider.notifier).joinRoom('없는코드'),
      '없는 입장 코드입니다.',
    );
  });
}
