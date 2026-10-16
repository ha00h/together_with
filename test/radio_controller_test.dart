import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/features/workspace/workspace_screen.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/session.dart';
import 'package:together_with/radio/radio_controller.dart';
import 'package:together_with/radio/voice_room.dart';
import 'package:together_with/radio/voice_ticket.dart';
import 'package:together_with/state/session_controller.dart';
import 'package:together_with/sync/active_room_store.dart';
import 'package:together_with/sync/memory_room_gateway.dart';
import 'package:together_with/sync/private_stroke_store.dart';
import 'package:together_with/sync/room_providers.dart';

class FakeVoiceRoom implements VoiceRoom {
  String? channel;
  bool publish = false;
  bool listening = true;
  int joins = 0;
  int leaves = 0;
  VoiceFailure? failJoinWith;

  @override
  void listen(void Function(VoiceNotice notice) onNotice) {}

  @override
  Future<void> join({
    required String channelId,
    required bool publish,
    String token = '',
    int uid = 0,
  }) async {
    final failure = failJoinWith;
    if (failure != null) {
      failJoinWith = null;
      throw VoiceJoinException(failure);
    }
    joins += 1;
    channel = channelId;
    this.publish = publish;
  }

  @override
  Future<void> renew(String token) async {}

  @override
  Future<void> setPublishing(bool publish) async {
    this.publish = publish;
  }

  @override
  Future<void> setListening(bool listen) async {
    listening = listen;
  }

  @override
  Future<void> leave() async {
    leaves += 1;
    channel = null;
    publish = false;
  }
}

class _FixedTicketIssuer implements VoiceTicketIssuer {
  @override
  Future<VoiceTicket> issue(String code) async {
    return const VoiceTicket(token: 'test-token', uid: 7);
  }
}

void main() {
  test('발표자만 마이크를 내고 참여자는 같은 코드로 듣기만 한다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final voice = FakeVoiceRoom();

    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          voiceRoomProvider.overrideWithValue(voice),
          voiceTicketIssuerProvider.overrideWithValue(_FixedTicketIssuer()),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    final hostBox = container();
    hostBox.listen(radioProvider, (_, _) {});
    await hostBox.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    await pumpEventQueue();
    final code = hostBox.read(sessionProvider)!.joinCode;
    expect(voice.channel, code);
    expect(voice.publish, isFalse);
    expect(hostBox.read(radioProvider).micOn, isFalse);
    expect(hostBox.read(radioProvider).joined, isTrue);

    await hostBox.read(radioProvider.notifier).toggleMic();
    expect(voice.publish, isTrue);
    expect(hostBox.read(radioProvider).micOn, isTrue);

    await hostBox.read(radioProvider.notifier).toggleMic();
    expect(voice.publish, isFalse);
    expect(hostBox.read(radioProvider).micOn, isFalse);

    hostBox.read(sessionProvider.notifier).viewAs(MemberRole.participant);
    await pumpEventQueue();
    expect(voice.publish, isFalse);

    hostBox.read(sessionProvider.notifier).closeSession();
    await pumpEventQueue();
    expect(voice.leaves, greaterThan(0));
    expect(hostBox.read(radioProvider).joined, isFalse);

    gateway.userId = 'guest-2';
    final guestBox = container();
    guestBox.listen(radioProvider, (_, _) {});
    expect(await guestBox.read(sessionProvider.notifier).joinRoom(code), isNull);
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.role, MemberRole.participant);
    expect(voice.channel, code);
    expect(voice.publish, isFalse);

    await guestBox.read(radioProvider.notifier).toggleMic();
    expect(voice.publish, isFalse);
    await guestBox.read(radioProvider.notifier).toggleListen();
    expect(voice.listening, isFalse);
  });

  test('기본 인증서가 켜져 있으면 연결 실패를 알린다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final voice = FakeVoiceRoom()..failJoinWith = VoiceFailure.certificate;
    final box = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(MemoryPrivateStrokeStore()),
        voiceRoomProvider.overrideWithValue(voice),
        voiceTicketIssuerProvider.overrideWithValue(_FixedTicketIssuer()),
      ],
    );
    addTearDown(box.dispose);
    box.listen(radioProvider, (_, _) {});
    await box.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    await pumpEventQueue();
    expect(box.read(radioProvider).joined, isFalse);
    expect(box.read(radioProvider).warning, certificateWarning);
  });

  testWidgets('네트워크 수업의 발표자에게만 마이크 버튼이 있다', (tester) async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final box = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(MemoryPrivateStrokeStore()),
        voiceRoomProvider.overrideWithValue(FakeVoiceRoom()),
        voiceTicketIssuerProvider.overrideWithValue(_FixedTicketIssuer()),
      ],
    );
    addTearDown(box.dispose);
    await box.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: box,
        child: const MaterialApp(home: WorkspaceScreen()),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('radio-mic')), findsOneWidget);
    expect(find.byKey(const Key('radio-listen')), findsNothing);

    box.read(sessionProvider.notifier).viewAs(MemberRole.participant);
    await tester.pump();
    expect(find.byKey(const Key('radio-mic')), findsNothing);
    expect(find.byKey(const Key('radio-listen')), findsOneWidget);
  });

  test('라디오를 끄고 연 수업은 발표자와 참여자 모두 음성을 연결하지 않는다', () async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final voice = FakeVoiceRoom();

    ProviderContainer container() {
      final box = ProviderContainer(
        overrides: [
          roomGatewayProvider.overrideWithValue(gateway),
          activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
          privateStrokeStoreProvider.overrideWithValue(
            MemoryPrivateStrokeStore(),
          ),
          voiceRoomProvider.overrideWithValue(voice),
          voiceTicketIssuerProvider.overrideWithValue(_FixedTicketIssuer()),
        ],
      );
      addTearDown(box.dispose);
      return box;
    }

    final hostBox = container();
    hostBox.listen(radioProvider, (_, _) {});
    await hostBox.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
      radioOn: false,
    );
    await pumpEventQueue();
    expect(hostBox.read(sessionProvider)!.radioEnabled, isFalse);
    expect(voice.joins, 0);
    expect(hostBox.read(radioProvider).joined, isFalse);

    final code = hostBox.read(sessionProvider)!.joinCode;
    gateway.userId = 'guest-2';
    final guestBox = container();
    guestBox.listen(radioProvider, (_, _) {});
    expect(await guestBox.read(sessionProvider.notifier).joinRoom(code), isNull);
    await pumpEventQueue();
    expect(guestBox.read(sessionProvider)!.radioEnabled, isFalse);
    expect(voice.joins, 0);
  });

  testWidgets('라디오를 끈 수업에는 마이크와 듣기 버튼이 없다', (tester) async {
    final gateway = MemoryRoomGateway(userId: 'host-1');
    final box = ProviderContainer(
      overrides: [
        roomGatewayProvider.overrideWithValue(gateway),
        activeRoomStoreProvider.overrideWithValue(MemoryActiveRoomStore()),
        privateStrokeStoreProvider.overrideWithValue(MemoryPrivateStrokeStore()),
        voiceRoomProvider.overrideWithValue(FakeVoiceRoom()),
        voiceTicketIssuerProvider.overrideWithValue(_FixedTicketIssuer()),
      ],
    );
    addTearDown(box.dispose);
    await box.read(sessionProvider.notifier).startRoom(
      title: '수학',
      documentPath: '/tmp/lesson.pdf',
      fileName: 'lesson.pdf',
      documentKind: DocumentKind.pdf,
      radioOn: false,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: box,
        child: const MaterialApp(home: WorkspaceScreen()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('라디오 끔'), findsOneWidget);
    expect(find.byKey(const Key('radio-mic')), findsNothing);
    expect(find.byKey(const Key('radio-listen')), findsNothing);
  });
}
