import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';
import '../state/session_controller.dart';
import 'voice_room.dart';
import 'voice_ticket.dart';

const certificateWarning = '음성 입장권이 맞지 않습니다. 수업을 나갔다가 다시 들어와 주세요.';
const voiceTokenWarning = '음성 입장권을 받지 못했습니다.';
const microphoneWarning = '마이크 권한이 없어 목소리를 보낼 수 없습니다.';
const radioWarning = '음성을 연결하지 못했습니다.';

const _micChannel = MethodChannel('together_with/mic');

class RadioLink {
  const RadioLink({
    this.joined = false,
    this.micOn = false,
    this.listening = true,
    this.warning,
  });

  final bool joined;
  final bool micOn;
  final bool listening;
  final String? warning;

  RadioLink copyWith({
    bool? joined,
    bool? micOn,
    bool? listening,
    String? warning,
    bool clearWarning = false,
  }) {
    return RadioLink(
      joined: joined ?? this.joined,
      micOn: micOn ?? this.micOn,
      listening: listening ?? this.listening,
      warning: clearWarning ? null : (warning ?? this.warning),
    );
  }
}

final voiceRoomProvider = Provider<VoiceRoom>((ref) => AgoraVoiceRoom());

final voiceTicketIssuerProvider = Provider<VoiceTicketIssuer>(
  (ref) => FirebaseVoiceTicketIssuer(),
);

final radioProvider = NotifierProvider.autoDispose<RadioController, RadioLink>(
  RadioController.new,
);

class RadioController extends Notifier<RadioLink> {
  String? _applied;
  String? _channel;
  bool _publishing = false;
  Future<void> _queue = Future<void>.value();

  @override
  RadioLink build() {
    final room = ref.read(voiceRoomProvider);
    room.listen(_onNotice);
    ref.listen(sessionProvider, (previous, next) => _onSession(next));
    ref.onDispose(() {
      _applied = null;
      _channel = null;
      unawaited(room.leave());
    });
    Future.microtask(() {
      if (!ref.mounted) return;
      _onSession(ref.read(sessionProvider));
    });
    return const RadioLink();
  }

  Future<void> toggleMic() {
    return _enqueue(() async {
      final session = ref.read(sessionProvider);
      if (session == null ||
          !session.networked ||
          !session.radioEnabled ||
          session.role != MemberRole.host) {
        return;
      }
      final next = !state.micOn;
      if (next && !await _ensureMicrophone()) {
        state = state.copyWith(micOn: false, warning: microphoneWarning);
        if (_channel != null) {
          await ref.read(voiceRoomProvider).setPublishing(false);
          _publishing = false;
        }
        return;
      }
      state = state.copyWith(micOn: next, clearWarning: true);
      if (_channel == null) return;
      try {
        await ref.read(voiceRoomProvider).setPublishing(next);
        _publishing = next;
      } on VoiceJoinException catch (error) {
        _show(error);
      }
    });
  }

  Future<void> toggleListen() {
    return _enqueue(() async {
      final session = ref.read(sessionProvider);
      if (session == null || !session.radioEnabled) return;
      final next = !state.listening;
      state = state.copyWith(listening: next);
      if (_channel == null) return;
      await ref.read(voiceRoomProvider).setListening(next);
    });
  }

  void _onSession(Session? session) {
    final signature = _signature(session);
    if (signature == _applied) return;
    _applied = signature;
    _enqueue(() => _apply(session));
  }

  Future<void> _apply(Session? session) async {
    final room = ref.read(voiceRoomProvider);
    if (session == null || !session.networked || !session.radioEnabled) {
      _channel = null;
      _publishing = false;
      await room.leave();
      if (!ref.mounted) return;
      state = const RadioLink();
      return;
    }
    var publish = session.role == MemberRole.host && state.micOn;
    if (publish && !await _ensureMicrophone()) {
      publish = false;
      state = state.copyWith(micOn: false, warning: microphoneWarning);
    }
    try {
      if (_channel != session.joinCode) {
        final VoiceTicket ticket;
        try {
          ticket = await ref
              .read(voiceTicketIssuerProvider)
              .issue(session.joinCode);
        } on VoiceTicketException {
          _channel = null;
          _publishing = false;
          await room.leave();
          if (!ref.mounted) return;
          state = state.copyWith(joined: false, warning: voiceTokenWarning);
          return;
        }
        publish = await _join(
          room,
          session.joinCode,
          publish,
          ticket.token,
          ticket.uid,
        );
      } else if (_publishing != publish) {
        await room.setPublishing(publish);
        _publishing = publish;
      }
      await room.setListening(state.listening);
      if (!ref.mounted) return;
      final keepMicWarning =
          !publish && state.warning == microphoneWarning;
      state = state.copyWith(joined: true, clearWarning: !keepMicWarning);
    } on VoiceJoinException catch (error) {
      if (!ref.mounted) return;
      _channel = null;
      _show(error);
    }
  }

  Future<bool> _join(
    VoiceRoom room,
    String code,
    bool publish,
    String token,
    int uid,
  ) async {
    try {
      await room.join(channelId: code, publish: publish, token: token, uid: uid);
    } on VoiceJoinException catch (error) {
      if (error.kind != VoiceFailure.microphone || !publish) rethrow;
      state = state.copyWith(micOn: false, warning: microphoneWarning);
      await room.join(
        channelId: code,
        publish: false,
        token: token,
        uid: uid,
      );
      publish = false;
    }
    _channel = code;
    _publishing = publish;
    return publish;
  }

  void _onNotice(VoiceNotice notice) {
    if (!ref.mounted) return;
    _enqueue(() async {
      if (!ref.mounted) return;
      if (notice.renew) {
        final session = ref.read(sessionProvider);
        if (session == null || _channel == null) return;
        try {
          final ticket = await ref
              .read(voiceTicketIssuerProvider)
              .issue(session.joinCode);
          await ref.read(voiceRoomProvider).renew(ticket.token);
        } on VoiceTicketException {
          if (!ref.mounted) return;
          state = state.copyWith(warning: voiceTokenWarning);
        }
        return;
      }
      if (notice.certificateRequired) {
        _channel = null;
        _publishing = false;
        await ref.read(voiceRoomProvider).leave();
        if (!ref.mounted) return;
        state = state.copyWith(joined: false, warning: certificateWarning);
        return;
      }
      if (notice.permissionDenied) {
        _publishing = false;
        state = state.copyWith(micOn: false, warning: microphoneWarning);
        await ref.read(voiceRoomProvider).setPublishing(false);
      }
    });
  }

  void _show(VoiceJoinException error) {
    state = state.copyWith(
      joined: false,
      warning: switch (error.kind) {
        VoiceFailure.certificate => certificateWarning,
        VoiceFailure.microphone => microphoneWarning,
        VoiceFailure.generic => radioWarning,
      },
    );
  }

  Future<bool> _ensureMicrophone() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _micChannel.invokeMethod<bool>('request');
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  String? _signature(Session? session) {
    if (session == null || !session.networked) return null;
    return '${session.joinCode}:${session.role.name}:${session.radioEnabled}';
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.catchError((_) {});
    return run;
  }
}
