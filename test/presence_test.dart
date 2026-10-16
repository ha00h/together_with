import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/archive/lesson_archive.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/session.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';

import 'end_class_test.dart';

void main() {
  test('들어오고 나가면 접속자 수가 바뀐다', () async {
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
    await pumpEventQueue();
    expect(hostBox.read(sessionProvider)!.memberCount, 1);
    final code = hostBox.read(sessionProvider)!.joinCode;

    gateway.userId = 'guest-2';
    final guestBox = container();
    expect(await guestBox.read(sessionProvider.notifier).joinRoom(code), isNull);
    await pumpEventQueue();
    expect(hostBox.read(sessionProvider)!.memberCount, 2);
    expect(guestBox.read(sessionProvider)!.memberCount, 2);

    guestBox.read(sessionProvider.notifier).closeSession();
    await pumpEventQueue();
    expect(hostBox.read(sessionProvider)!.memberCount, 1);
  });

  test('지난 수업을 닫으면 목록에서 빠진다', () async {
    final archive = _ListArchive();
    final box = ProviderContainer(
      overrides: [lessonArchiveProvider.overrideWithValue(archive)],
    );
    addTearDown(box.dispose);
    box.listen(lessonListProvider, (_, _) {});
    await pumpEventQueue();
    expect(box.read(lessonListProvider), hasLength(1));

    await box.read(lessonListProvider.notifier).dismiss('lesson-1');
    expect(box.read(lessonListProvider), isEmpty);
    expect(archive.removed, ['lesson-1']);
  });
}

class _ListArchive implements LessonArchive {
  final removed = <String>[];
  var lessons = [
    SavedLesson(
      id: 'lesson-1',
      title: '수학',
      code: 'ABCDEF',
      fileName: 'lesson-1.pdf',
      savedAt: DateTime.utc(2026, 10, 16),
      path: '/tmp/lesson-1.pdf',
    ),
  ];

  @override
  Future<SavedLesson> export(Session session) {
    throw UnimplementedError();
  }

  @override
  Future<List<SavedLesson>> readAll() async => lessons;

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    lessons = [for (final lesson in lessons) if (lesson.id != id) lesson];
  }
}
