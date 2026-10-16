import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/archive/lesson_archive.dart';
import 'package:together_with/documents/document_assembler.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/session.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';

import 'end_class_test.dart';

class _FakeAssembler implements DocumentAssembler {
  _FakeAssembler({this.basePages = 1});

  final int basePages;
  final calls = <List<String>>[];
  final _pages = <String, int>{};

  int pagesOf(String path) =>
      _pages[path] ?? (path == '/tmp/lesson.pdf' ? basePages : 1);

  AssembledDocument _made(int pageCount) {
    final path = '/tmp/merged-${calls.length}.pdf';
    _pages[path] = pageCount;
    return AssembledDocument(path: path, pageCount: pageCount);
  }

  @override
  Future<AssembledDocument> assemble(List<String> sources) async {
    calls.add(sources);
    return _made(sources.fold(0, (sum, path) => sum + pagesOf(path)));
  }

  @override
  Future<AssembledDocument> blank(double aspectRatio) async {
    return const AssembledDocument(path: '/tmp/blank.pdf', pageCount: 1);
  }

  @override
  Future<AssembledDocument> insertBlank(
    String base, {
    required int at,
    required double aspectRatio,
  }) async {
    calls.add([base, 'blank@$at']);
    return _made(pagesOf(base) + 1);
  }

  @override
  Future<AssembledDocument> removePage(String base, {required int at}) async {
    calls.add([base, 'delete@$at']);
    return _made(pagesOf(base) - 1);
  }
}

void main() {
  test('발표자가 맨 뒤에 페이지를 붙이면 참여자도 새 문서로 바뀐다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final assembler = _FakeAssembler();
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
          documentAssemblerProvider.overrideWithValue(assembler),
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
    host.pointerDown(const Offset(10, 10), const Size(100, 100));
    host.pointerMove(const Offset(40, 40), const Size(100, 100));
    host.pointerUp();
    await pumpEventQueue();
    final code = hostBox.read(sessionProvider)!.joinCode;

    gateway.userId = 'guest-2';
    final guestBox = container();
    expect(await guestBox.read(sessionProvider.notifier).joinRoom(code), isNull);
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.documentVersion, 1);

    gateway.userId = 'host-1';
    final error = await host.appendPages(['/tmp/a.jpg', '/tmp/b.jpg']);
    await pumpEventQueue();
    expect(error, isNull);
    expect(assembler.calls.take(2).toList(), [
      ['/tmp/a.jpg', '/tmp/b.jpg'],
      ['/tmp/lesson.pdf', '/tmp/merged-1.pdf'],
    ]);
    expect(gateway.uploads, 1);
    expect(gateway.downloads, 1);
    expect(assembler.calls.last, ['/tmp/lesson.pdf', '/tmp/merged-1.pdf']);

    final hostSession = hostBox.read(sessionProvider)!;
    expect(hostSession.documentPath, '/tmp/merged-2.pdf');
    expect(hostSession.documentVersion, 2);
    expect(hostSession.documentLoading, isFalse);
    expect(hostSession.pageCount, 3);
    expect(hostSession.pageIndex, 1);
    expect(hostSession.publicStrokes, hasLength(1));
    expect(hostSession.publicStrokes.single.pageIndex, 0);

    final guestSession = guestBox.read(sessionProvider)!;
    expect(guestSession.documentPath, '/tmp/merged-3.pdf');
    expect(guestSession.documentLoading, isFalse);
    expect(guestSession.documentKind, DocumentKind.pdf);
    expect(guestSession.documentVersion, 2);
    expect(guestSession.pageCount, 3);
    expect(guestSession.pageIndex, 1);
    expect(guestSession.publicStrokes, hasLength(1));
  });

  test('중간에 흰 페이지를 넣으면 뒤쪽 공용 판서와 개인 노트가 한 칸씩 밀린다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final assembler = _FakeAssembler(basePages: 3);
    final guestNotes = MemoryPrivateStrokeStore();
    ProviderContainer container({MemoryPrivateStrokeStore? notes}) {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            notes ?? MemoryPrivateStrokeStore(),
          ),
          lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
          documentAssemblerProvider.overrideWithValue(assembler),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    const size = Size(100, 100);
    final hostBox = container();
    final host = hostBox.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    host.attachDocument(pageCount: 3, aspectRatio: 0.7);
    void draw(SessionController controller) {
      controller.pointerDown(const Offset(10, 10), size);
      controller.pointerMove(const Offset(40, 40), size);
      controller.pointerUp();
    }

    draw(host);
    host.goToPage(1);
    draw(host);
    await pumpEventQueue();
    final code = hostBox.read(sessionProvider)!.joinCode;

    gateway.userId = 'guest-2';
    final guestBox = container(notes: guestNotes);
    final guest = guestBox.read(sessionProvider.notifier);
    expect(await guest.joinRoom(code), isNull);
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.pageIndex, 1);
    draw(guest);
    await pumpEventQueue();

    gateway.userId = 'host-1';
    host.goToPage(0);
    await pumpEventQueue();
    expect(await host.insertBlankPage(), isNull);
    await pumpEventQueue();

    final hostSession = hostBox.read(sessionProvider)!;
    expect(gateway.uploads, 0);
    expect(gateway.downloads, 0);
    expect(hostSession.pageCount, 4);
    expect(hostSession.pageIndex, 1);
    expect(
      hostSession.publicStrokes.map((stroke) => stroke.pageIndex).toList(),
      [0, 2],
    );

    final guestSession = guestBox.read(sessionProvider)!;
    expect(guestSession.documentVersion, 2);
    expect(guestSession.pageIndex, 1);
    expect(
      guestSession.publicStrokes.map((stroke) => stroke.pageIndex).toList(),
      [0, 2],
    );
    expect(guestSession.privateStrokes.single.pageIndex, 2);
    final saved = await guestNotes.read(code, 'guest-2');
    expect(saved.documentVersion, 2);
    expect(saved.strokes.single.pageIndex, 2);
  });

  test('나가 있던 참여자도 다시 들어오면 개인 노트가 맞는 페이지로 간다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final assembler = _FakeAssembler(basePages: 2);
    final guestNotes = MemoryPrivateStrokeStore();
    ProviderContainer container({MemoryPrivateStrokeStore? notes}) {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            notes ?? MemoryPrivateStrokeStore(),
          ),
          lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
          documentAssemblerProvider.overrideWithValue(assembler),
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
    host.attachDocument(pageCount: 2, aspectRatio: 0.7);
    host.goToPage(1);
    final code = hostBox.read(sessionProvider)!.joinCode;

    gateway.userId = 'guest-2';
    final guestBox = container(notes: guestNotes);
    await guestBox.read(sessionProvider.notifier).joinRoom(code);
    await pumpEventQueue();
    final guest = guestBox.read(sessionProvider.notifier);
    guest.pointerDown(const Offset(10, 10), const Size(100, 100));
    guest.pointerMove(const Offset(40, 40), const Size(100, 100));
    guest.pointerUp();
    await pumpEventQueue();
    guest.closeSession();

    gateway.userId = 'host-1';
    host.goToPage(0);
    expect(await host.insertBlankPage(), isNull);
    await pumpEventQueue();

    gateway.userId = 'guest-2';
    final againBox = container(notes: guestNotes);
    expect(
      await againBox.read(sessionProvider.notifier).joinRoom(code),
      isNull,
    );
    final again = againBox.read(sessionProvider)!;
    expect(again.documentVersion, 2);
    expect(again.privateStrokes.single.pageIndex, 2);
  });

  test('참여자의 옛 문서가 페이지 수를 줄이지 않는다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    final hostBox = container();
    await hostBox.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    hostBox
        .read(sessionProvider.notifier)
        .attachDocument(pageCount: 3, aspectRatio: 0.7);
    hostBox.read(sessionProvider.notifier).goToPage(2);
    final code = hostBox.read(sessionProvider)!.joinCode;

    gateway.userId = 'guest-2';
    final guestBox = container();
    await guestBox.read(sessionProvider.notifier).joinRoom(code);
    await pumpEventQueue();
    guestBox
        .read(sessionProvider.notifier)
        .attachDocument(pageCount: 1, aspectRatio: 0.7);
    final guest = guestBox.read(sessionProvider)!;
    expect(guest.role, MemberRole.participant);
    expect(guest.pageCount, 3);
    expect(guest.pageIndex, 2);
  });

  test('페이지를 삭제하면 그 페이지 판서는 지워지고 뒤쪽은 한 칸씩 당겨진다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final assembler = _FakeAssembler(basePages: 3);
    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
          documentAssemblerProvider.overrideWithValue(assembler),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    const size = Size(100, 100);
    void draw(SessionController controller) {
      controller.pointerDown(const Offset(10, 10), size);
      controller.pointerMove(const Offset(40, 40), size);
      controller.pointerUp();
    }

    final hostBox = container();
    final host = hostBox.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    host.attachDocument(pageCount: 3, aspectRatio: 0.7);
    for (final page in [0, 1, 2]) {
      host.goToPage(page);
      draw(host);
    }
    host.goToPage(1);
    await pumpEventQueue();
    final code = hostBox.read(sessionProvider)!.joinCode;

    gateway.userId = 'guest-2';
    final guestBox = container();
    final guest = guestBox.read(sessionProvider.notifier);
    await guest.joinRoom(code);
    await pumpEventQueue();
    draw(guest);
    guest.browsePage(2);
    draw(guest);
    final loadingSeen = <bool>[];
    guestBox.listen(
      sessionProvider.select((session) => session?.documentLoading ?? false),
      (_, next) => loadingSeen.add(next),
    );

    gateway.userId = 'host-1';
    expect(await host.deletePage(), isNull);
    await pumpEventQueue();

    expect(assembler.calls.first, ['/tmp/lesson.pdf', 'delete@1']);
    final hostSession = hostBox.read(sessionProvider)!;
    expect(hostSession.pageCount, 2);
    expect(hostSession.pageIndex, 1);
    expect(hostSession.documentVersion, 2);
    expect(
      hostSession.publicStrokes.map((stroke) => stroke.pageIndex).toList(),
      [0, 1],
    );

    final guestSession = guestBox.read(sessionProvider)!;
    expect(loadingSeen, [true, false]);
    expect(guestSession.documentLoading, isFalse);
    expect(guestSession.documentVersion, 2);
    expect(guestSession.pageCount, 2);
    expect(guestSession.pageIndex, 1);
    expect(guestSession.following, isFalse);
    expect(
      guestSession.publicStrokes.map((stroke) => stroke.pageIndex).toList(),
      [0, 1],
    );
    expect(guestSession.privateStrokes.single.pageIndex, 1);
  });

  test('마지막 페이지를 지우면 앞 페이지로 가고, 한 장 남으면 지울 수 없다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final assembler = _FakeAssembler(basePages: 2);
    final hostBox = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(MemoryPrivateStrokeStore()),
        lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
        documentAssemblerProvider.overrideWithValue(assembler),
      ],
    );
    addTearDown(hostBox.dispose);
    final host = hostBox.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    host.attachDocument(pageCount: 2, aspectRatio: 0.7);
    host.goToPage(1);

    expect(await host.deletePage(), isNull);
    expect(hostBox.read(sessionProvider)!.pageCount, 1);
    expect(hostBox.read(sessionProvider)!.pageIndex, 0);
    expect(await host.deletePage(), isNotNull);
    expect(assembler.calls, hasLength(1));

    host.viewAs(MemberRole.participant);
    expect(await host.deletePage(), isNotNull);
  });

  test('참여자는 페이지를 추가할 수 없다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final assembler = _FakeAssembler();
    final hostBox = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(MemoryPrivateStrokeStore()),
        lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
        documentAssemblerProvider.overrideWithValue(assembler),
      ],
    );
    addTearDown(hostBox.dispose);
    await hostBox.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    hostBox.read(sessionProvider.notifier).viewAs(MemberRole.participant);
    final error = await hostBox
        .read(sessionProvider.notifier)
        .appendPages(['/tmp/a.jpg']);
    expect(error, isNotNull);
    expect(assembler.calls, isEmpty);
  });
}
