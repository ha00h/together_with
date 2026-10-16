import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/archive/lesson_archive.dart';
import 'package:together_with/archive/lesson_renderer.dart';
import 'package:together_with/archive/share_lesson.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/session.dart';
import 'package:together_with/models/stroke.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';

class MemoryLessonArchive implements LessonArchive {
  var failExport = false;
  final sessions = <Session>[];

  @override
  Future<SavedLesson> export(Session session) async {
    if (failExport) {
      throw const LessonExportException('기록을 만들지 못했습니다.');
    }
    sessions.add(session);
    return SavedLesson(
      id: 'saved',
      title: session.title,
      code: session.joinCode,
      fileName: 'saved.pdf',
      savedAt: DateTime.utc(2026, 10, 15),
      path: '/tmp/saved.pdf',
    );
  }

  @override
  Future<List<SavedLesson>> readAll() async => const [];

  @override
  Future<void> remove(String id) async {}
}

void main() {
  test('페이지 기록에는 공용 판서와 개인 노트와 끝나지 않은 획이 들어간다', () {
    final session = Session(
      id: 'room',
      title: '수학',
      joinCode: 'ABCDEF',
      documentPath: '/tmp/lesson.pdf',
      documentKind: DocumentKind.pdf,
      pageCount: 2,
      pageIndex: 0,
      aspectRatio: 1,
      role: MemberRole.participant,
      openedOnThisDevice: false,
      tool: CanvasTool.pen,
      hostColorArgb: 1,
      participantColorArgb: 2,
      strokeWidthPx: 3,
      publicStrokes: const [
        Stroke(
          id: 'public',
          pageIndex: 0,
          tool: InkTool.pen,
          argb: 1,
          widthNorm: 0.01,
          points: [NormPoint(0.1, 0.2)],
          isPublic: true,
        ),
      ],
      privateStrokes: const [
        Stroke(
          id: 'private',
          pageIndex: 0,
          tool: InkTool.pen,
          argb: 2,
          widthNorm: 0.01,
          points: [NormPoint(0.3, 0.4)],
          isPublic: false,
        ),
      ],
      liveStroke: const Stroke(
        id: 'live',
        pageIndex: 1,
        tool: InkTool.highlighter,
        argb: 3,
        widthNorm: 0.02,
        points: [NormPoint(0.5, 0.6)],
        isPublic: false,
      ),
    );

    expect(inkForPage(session, 0).map((stroke) => stroke.id), [
      'public',
      'private',
    ]);
    expect(inkForPage(session, 1).single.id, 'live');
    expect(pdfShareName('수학'), '수학.pdf');
    expect(pdfShareName('a/b'), 'a b.pdf');
  });

  test('발표자가 수업을 끝내면 기록을 남기고 서버 수업을 지운다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final store = MemoryActiveRoomStore();
    final archive = MemoryLessonArchive();
    final box = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(store),
        privateStrokeStoreProvider.overrideWithValue(
          MemoryPrivateStrokeStore(),
        ),
        lessonArchiveProvider.overrideWithValue(archive),
      ],
    );
    addTearDown(box.dispose);
    final host = box.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    const size = Size(200, 280);
    host.pointerDown(const Offset(20, 30), size);
    host.pointerUp();
    final code = box.read(sessionProvider)!.joinCode;

    final result = await host.endClass();

    expect(result.ok, isTrue);
    expect(result.removedServer, isTrue);
    expect(archive.sessions.single.publicStrokes, hasLength(1));
    expect(await gateway.joinRoom(code), isNull);
    expect(box.read(sessionProvider), isNull);
    expect(store.code, isNull);
  });

  test('참여자가 기록을 저장해도 서버 수업은 남는다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final archive = MemoryLessonArchive();
    ProviderContainer container(String userId) {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          lessonArchiveProvider.overrideWithValue(archive),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    final hostBox = container('host-1');
    final host = hostBox.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    final code = hostBox.read(sessionProvider)!.joinCode;
    gateway.userId = 'guest-2';
    final guestBox = container('guest-2');
    expect(
      await guestBox.read(sessionProvider.notifier).joinRoom(code),
      isNull,
    );
    guestBox
        .read(sessionProvider.notifier)
        .pointerDown(const Offset(10, 10), const Size(100, 100));
    guestBox.read(sessionProvider.notifier).pointerUp();

    final result = await guestBox.read(sessionProvider.notifier).endClass();

    expect(result.ok, isTrue);
    expect(result.removedServer, isFalse);
    expect(archive.sessions.single.privateStrokes, hasLength(1));
    expect(
      inkForPage(archive.sessions.single, 0).single.isPublic,
      isFalse,
    );
    expect(guestBox.read(sessionProvider), isNull);
    gateway.userId = 'host-1';
    expect(await gateway.joinRoom(code), isNotNull);
  });

  test('발표자가 끝내면 참여자에게 알리고 공용 판서는 기록에 남는다', () async {
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
    host.pointerUp();
    await pumpEventQueue();
    final code = hostBox.read(sessionProvider)!.joinCode;

    gateway.userId = 'guest-2';
    final guestBox = container();
    expect(
      await guestBox.read(sessionProvider.notifier).joinRoom(code),
      isNull,
    );
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.publicStrokes, hasLength(1));

    final hostResult = await host.endClass();
    await pumpEventQueue();

    final guest = guestBox.read(sessionProvider)!;
    expect(hostResult.removedServer, isTrue);
    expect(guest.classEnded, isTrue);
    expect(guest.publicStrokes, hasLength(1));

    final saved = await guestBox.read(sessionProvider.notifier).endClass();
    expect(saved.ok, isTrue);
    expect(archive.sessions.last.publicStrokes, hasLength(1));
  });

  test('기록을 만들지 못하면 서버 수업은 지우지 않는다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final archive = MemoryLessonArchive()..failExport = true;
    final box = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(
          MemoryPrivateStrokeStore(),
        ),
        lessonArchiveProvider.overrideWithValue(archive),
      ],
    );
    addTearDown(box.dispose);
    await box
        .read(sessionProvider.notifier)
        .startRoom(
          title: '수학',
          documentPath: '/tmp/lesson.pdf',
          fileName: 'lesson.pdf',
          documentKind: DocumentKind.pdf,
        );
    final code = box.read(sessionProvider)!.joinCode;

    final result = await box.read(sessionProvider.notifier).endClass();

    expect(result.ok, isFalse);
    expect(box.read(sessionProvider), isNotNull);
    expect(await gateway.joinRoom(code), isNotNull);
  });
}
