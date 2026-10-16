import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/archive/lesson_renderer.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/note_metrics.dart';
import 'package:together_with/models/stroke.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';
import 'package:together_with/sync/stroke_codec.dart';

void main() {
  test('발표자 포스트잇은 참여자에게 보이고 기록에 남는다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
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
    host.selectTool(CanvasTool.note);
    host.placeNote(const Offset(40, 50), const Size(200, 280), '  숙제  ');
    await pumpEventQueue();

    final note = guestBox.read(sessionProvider)!.publicStrokes.single;
    expect(note.isNote, isTrue);
    expect(note.text, '숙제');
    expect(inkForPage(hostBox.read(sessionProvider)!, 0).single.text, '숙제');
    expect(strokeHits(note, note.points.first), isTrue);
    expect(strokeHits(note, const NormPoint(0.95, 0.95)), isFalse);

    host.selectTool(CanvasTool.eraser);
    host.pointerDown(const Offset(50, 60), const Size(200, 280));
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.publicStrokes, isEmpty);
  });

  test('참여자 포스트잇은 자기 기기에만 남고 접고 옮길 수 있다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    ProviderContainer container(String userId) {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    final hostBox = container('host-1');
    await hostBox.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    final code = hostBox.read(sessionProvider)!.joinCode;
    gateway.userId = 'guest-2';
    final guestBox = container('guest-2');
    final guest = guestBox.read(sessionProvider.notifier);
    expect(await guest.joinRoom(code), isNull);
    guest.placeNote(const Offset(20, 20), const Size(200, 280), '개인');
    final note = guestBox.read(sessionProvider)!.privateStrokes.single;
    expect(note.text, '개인');
    expect(note.isPublic, isFalse);
    expect(guestBox.read(sessionProvider)!.publicStrokes, isEmpty);
    expect(gateway.strokeCount(code), 0);

    guest.toggleNoteFold(note.id);
    expect(guestBox.read(sessionProvider)!.privateStrokes.single.folded, isTrue);
    guest.moveNote(note.id, const NormPoint(0.5, 0.4));
    guest.syncNote(note.id);
    expect(
      guestBox.read(sessionProvider)!.privateStrokes.single.points.single.x,
      closeTo(0.5, 0.0001),
    );
    expect(gateway.strokeCount(code), 0);
    expect(hostBox.read(sessionProvider)!.publicStrokes, isEmpty);
  });

  test('발표자가 옮기거나 접으면 참여자 화면도 따라간다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
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
    host.placeNote(const Offset(30, 40), const Size(200, 280), '공용');
    await pumpEventQueue();
    final id = hostBox.read(sessionProvider)!.publicStrokes.single.id;

    gateway.userId = 'guest-2';
    final guestBox = container();
    expect(await guestBox.read(sessionProvider.notifier).joinRoom(code), isNull);
    await pumpEventQueue();

    gateway.userId = 'host-1';
    host.moveNote(id, const NormPoint(0.4, 0.2));
    host.syncNote(id);
    host.toggleNoteFold(id);
    await pumpEventQueue();

    final shown = guestBox.read(sessionProvider)!.publicStrokes.single;
    expect(shown.folded, isTrue);
    expect(shown.points.single.x, closeTo(0.4, 0.0001));
    expect(strokeHits(shown, shown.points.first), isTrue);
    expect(
      strokeHits(
        shown,
        NormPoint(shown.points.first.x, shown.points.first.y + 0.2),
      ),
      isFalse,
    );
  });

  test('포스트잇 글은 다시 읽을 수 있다', () {
    final height = noteHeightNorm('복습', 1 / 1.4142);
    const note = Stroke(
      id: 'n1',
      pageIndex: 1,
      tool: InkTool.note,
      argb: notePaper,
      widthNorm: noteWidthNorm,
      heightNorm: 0.2,
      points: [NormPoint(0.1, 0.2)],
      text: '복습',
      isPublic: true,
    );
    final decoded = strokeFromRemote(strokeToMap(note))!;
    expect(decoded.text, '복습');
    expect(decoded.heightNorm, closeTo(0.2, 0.0001));
    expect(decoded.isNote, isTrue);
    expect(decoded.folded, isFalse);
    final folded = strokeFromRemote({
      ...strokeToMap(note),
      'folded': true,
    });
    expect(folded?.folded, isTrue);
    expect(height, inInclusiveRange(0.1, 0.5));
    expect(strokeFromRemote({'tool': 'note', 'text': '  '}), isNull);
  });
}
