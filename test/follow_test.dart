import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/archive/lesson_archive.dart';
import 'package:together_with/documents/document_assembler.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';

import 'end_class_test.dart';

class _BlankAssembler implements DocumentAssembler {
  var pages = 3;

  @override
  Future<AssembledDocument> assemble(List<String> sources) async =>
      AssembledDocument(path: '/tmp/a.pdf', pageCount: pages);

  @override
  Future<AssembledDocument> blank(double aspectRatio) async =>
      const AssembledDocument(path: '/tmp/b.pdf', pageCount: 1);

  @override
  Future<AssembledDocument> insertBlank(
    String base, {
    required int at,
    required double aspectRatio,
  }) async {
    pages += 1;
    return AssembledDocument(path: '/tmp/i-$pages.pdf', pageCount: pages);
  }

  @override
  Future<AssembledDocument> removePage(String base, {required int at}) async {
    pages -= 1;
    return AssembledDocument(path: '/tmp/d-$pages.pdf', pageCount: pages);
  }
}

void main() {
  late MemoryRoomGateway gateway;
  late _BlankAssembler assembler;

  ProviderContainer container() {
    final box = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(MemoryPrivateStrokeStore()),
        lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
        documentAssemblerProvider.overrideWithValue(assembler),
      ],
    );
    addTearDown(box.dispose);
    return box;
  }

  Future<(ProviderContainer, ProviderContainer)> openRoom() async {
    gateway = MemoryRoomGateway(userId: 'host-1');
    assembler = _BlankAssembler();
    final hostBox = container();
    final host = hostBox.read(sessionProvider.notifier);
    await host.startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    host.attachDocument(pageCount: 3, aspectRatio: 0.7);
    await pumpEventQueue();
    final code = hostBox.read(sessionProvider)!.joinCode;
    gateway.userId = 'guest-2';
    final guestBox = container();
    await guestBox.read(sessionProvider.notifier).joinRoom(code);
    await pumpEventQueue();
    gateway.userId = 'host-1';
    return (hostBox, guestBox);
  }

  test('참여자는 혼자 페이지를 넘기고, 따라가기로 돌아온다', () async {
    final (hostBox, guestBox) = await openRoom();
    final host = hostBox.read(sessionProvider.notifier);
    final guest = guestBox.read(sessionProvider.notifier);

    guest.browsePage(2);
    expect(guestBox.read(sessionProvider)!.pageIndex, 2);
    expect(guestBox.read(sessionProvider)!.following, isFalse);

    host.goToPage(1);
    await pumpEventQueue();
    var session = guestBox.read(sessionProvider)!;
    expect(session.hostPageIndex, 1);
    expect(session.pageIndex, 2);

    guest.pointerDown(const Offset(10, 10), const Size(100, 100));
    guest.pointerMove(const Offset(40, 40), const Size(100, 100));
    guest.pointerUp();
    expect(guestBox.read(sessionProvider)!.privateStrokes.single.pageIndex, 2);

    guest.followPresenter();
    session = guestBox.read(sessionProvider)!;
    expect(session.following, isTrue);
    expect(session.pageIndex, 1);

    host.goToPage(2);
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.pageIndex, 2);
  });

  test('참여자가 스와이프로 넘기면 혼자 보기로 바뀐다', () async {
    final (hostBox, guestBox) = await openRoom();
    final guest = guestBox.read(sessionProvider.notifier);

    expect(guest.turnPage(-1), isFalse);
    expect(guest.turnPage(1), isTrue);
    final session = guestBox.read(sessionProvider)!;
    expect(session.pageIndex, 1);
    expect(session.following, isFalse);
    expect(hostBox.read(sessionProvider)!.pageIndex, 0);
  });

  test('따라가기를 끄면 발표자가 넘겨도 지금 페이지에 남는다', () async {
    final (hostBox, guestBox) = await openRoom();
    final host = hostBox.read(sessionProvider.notifier);
    final guest = guestBox.read(sessionProvider.notifier);

    guest.stopFollowing();
    expect(guestBox.read(sessionProvider)!.following, isFalse);
    expect(guestBox.read(sessionProvider)!.pageIndex, 0);

    host.goToPage(2);
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.pageIndex, 0);
    expect(guestBox.read(sessionProvider)!.hostPageIndex, 2);

    guest.followPresenter();
    expect(guestBox.read(sessionProvider)!.pageIndex, 2);
  });

  test('발표자가 부르면 혼자 보던 참여자도 발표자 페이지로 온다', () async {
    final (hostBox, guestBox) = await openRoom();
    final host = hostBox.read(sessionProvider.notifier);
    final guest = guestBox.read(sessionProvider.notifier);

    host.goToPage(1);
    await pumpEventQueue();
    guest.browsePage(0);
    expect(guestBox.read(sessionProvider)!.pageIndex, 0);

    host.callAttention();
    await pumpEventQueue();
    final session = guestBox.read(sessionProvider)!;
    expect(session.pageIndex, 1);
    expect(session.following, isTrue);
    expect(session.attentionCount, 1);
  });

  test('발표자가 나가면 참여자에게 부재가 보이고, 돌아오면 사라진다', () async {
    final (hostBox, guestBox) = await openRoom();
    expect(guestBox.read(sessionProvider)!.hostPresent, isTrue);
    final code = hostBox.read(sessionProvider)!.joinCode;

    hostBox.read(sessionProvider.notifier).closeSession();
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.hostPresent, isFalse);

    gateway.userId = 'guest-3';
    final lateBox = container();
    await lateBox.read(sessionProvider.notifier).joinRoom(code);
    await pumpEventQueue();
    expect(lateBox.read(sessionProvider)!.hostPresent, isFalse);

    gateway.userId = 'host-1';
    final backBox = container();
    await backBox.read(sessionProvider.notifier).joinRoom(code);
    await pumpEventQueue();
    expect(backBox.read(sessionProvider)!.hostPresent, isTrue);
    expect(guestBox.read(sessionProvider)!.hostPresent, isTrue);
    expect(lateBox.read(sessionProvider)!.hostPresent, isTrue);
  });

  test('발표자가 화면을 나가면(뒤로가기) 부재로 보이고, 다시 들어오면 돌아온다', () async {
    final (hostBox, guestBox) = await openRoom();
    final host = hostBox.read(sessionProvider.notifier);

    host.leaveWorkspace();
    await pumpEventQueue();
    expect(hostBox.read(sessionProvider), isNotNull);
    expect(guestBox.read(sessionProvider)!.hostPresent, isFalse);
    expect(guestBox.read(sessionProvider)!.memberCount, 1);

    host.enterWorkspace();
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.hostPresent, isTrue);
    expect(guestBox.read(sessionProvider)!.memberCount, 2);
  });

  test('혼자 보던 페이지 앞에 흰 페이지가 들어가면 같은 내용을 계속 본다', () async {
    final (hostBox, guestBox) = await openRoom();
    final host = hostBox.read(sessionProvider.notifier);
    final guest = guestBox.read(sessionProvider.notifier);

    guest.browsePage(2);
    expect(await host.insertBlankPage(), isNull);
    await pumpEventQueue();
    final session = guestBox.read(sessionProvider)!;
    expect(session.pageCount, 4);
    expect(session.hostPageIndex, 1);
    expect(session.pageIndex, 3);
    expect(session.following, isFalse);
  });
}
