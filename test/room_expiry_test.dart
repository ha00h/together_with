import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/archive/lesson_archive.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/room_clock.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_gateway.dart';
import 'package:together_with/sync/room_providers.dart';

import 'end_class_test.dart';

class _RefusingGateway extends MemoryRoomGateway {
  _RefusingGateway({super.userId, super.clock});

  @override
  Future<RoomSnapshot?> joinRoom(String code) async =>
      throw const RoomSyncException(roomExpiredMessage);
}

void main() {
  final start = DateTime(2026, 10, 17, 9);
  late DateTime now;
  late MemoryRoomGateway gateway;

  ProviderContainer container() {
    final box = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(MemoryPrivateStrokeStore()),
        lessonArchiveProvider.overrideWithValue(MemoryLessonArchive()),
      ],
    );
    addTearDown(box.dispose);
    return box;
  }

  Future<(ProviderContainer, String)> openRoom() async {
    now = start;
    gateway = MemoryRoomGateway(userId: 'host-1', clock: () => now);
    final hostBox = container();
    await hostBox.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    return (hostBox, hostBox.read(sessionProvider)!.joinCode);
  }

  Future<ProviderContainer> join(String uid, String code) async {
    gateway.userId = uid;
    final box = container();
    expect(await box.read(sessionProvider.notifier).joinRoom(code), isNull);
    await pumpEventQueue();
    return box;
  }

  test('첫 참여자가 들어온 시점부터 24시간이 시작된다', () async {
    final (hostBox, code) = await openRoom();
    expect(hostBox.read(sessionProvider)!.expiresAt, isNull);

    now = start.add(const Duration(hours: 2));
    await join('guest-2', code);
    final expiresAt = start.add(const Duration(hours: 2)).add(roomLifetime);
    expect(hostBox.read(sessionProvider)!.expiresAt, expiresAt);

    now = start.add(const Duration(hours: 5));
    final late = await join('guest-3', code);
    expect(late.read(sessionProvider)!.expiresAt, expiresAt);
  });

  test('만료되면 참여자는 못 들어오고 발표자는 들어온다', () async {
    final (_, code) = await openRoom();
    await join('guest-2', code);

    now = start.add(roomLifetime).add(const Duration(minutes: 1));
    gateway.userId = 'guest-3';
    final blocked = container();
    expect(
      await blocked.read(sessionProvider.notifier).joinRoom(code),
      contains('발표자만'),
    );
    expect(blocked.read(sessionProvider), isNull);

    final host = await join('host-1', code);
    final session = host.read(sessionProvider)!;
    expect(session.expired, isTrue);
    expect(session.classEnded, isFalse);
  });

  test('서버가 만료로 막으면 같은 안내를 보여준다', () async {
    final (_, code) = await openRoom();
    gateway = _RefusingGateway(userId: 'guest-2', clock: () => now);
    final blocked = container();
    expect(
      await blocked.read(sessionProvider.notifier).joinRoom(code),
      roomExpiredMessage,
    );
    expect(blocked.read(sessionProvider), isNull);
  });

  test('수업 중 만료되면 참여자는 끝난 수업 상태가 된다', () async {
    final (hostBox, code) = await openRoom();
    await join('guest-2', code);

    now = start.add(roomLifetime).subtract(const Duration(milliseconds: 80));
    final guest = await join('guest-3', code);
    expect(guest.read(sessionProvider)!.expired, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    final session = guest.read(sessionProvider)!;
    expect(session.expired, isTrue);
    expect(session.classEnded, isTrue);
    expect(hostBox.read(sessionProvider)!.classEnded, isFalse);
  });

  test('발표자가 수업 화면에 들어올 때마다 방 보관 기간이 갱신된다', () async {
    final (hostBox, code) = await openRoom();
    final host = hostBox.read(sessionProvider.notifier);

    host.enterWorkspace();
    await pumpEventQueue();
    expect(gateway.touchedAt(code), start);

    now = start.add(const Duration(days: 5));
    host.enterWorkspace();
    await pumpEventQueue();
    expect(gateway.touchedAt(code), start.add(const Duration(days: 5)));

    final guest = await join('guest-2', code);
    guest.read(sessionProvider.notifier).enterWorkspace();
    await pumpEventQueue();
    expect(gateway.touchedAt(code), start.add(const Duration(days: 5)));
  });

  test('남은 시간은 시간 단위, 1시간 미만은 분까지 보여준다', () {
    final at = DateTime(2026, 10, 17, 12);
    expect(remainingLabel(null, at), '참여자 입장 후 24시간');
    expect(
      remainingLabel(at.add(const Duration(hours: 5, minutes: 40)), at),
      '남은 시간 5시간',
    );
    expect(
      remainingLabel(at.add(const Duration(minutes: 59, seconds: 30)), at),
      '남은 시간 59분',
    );
    expect(remainingLabel(at.add(const Duration(seconds: 20)), at), '남은 시간 1분');
    expect(remainingLabel(at, at), '만료됨 · 발표자만 입장');
  });
}
