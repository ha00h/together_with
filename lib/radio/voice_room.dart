import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import 'agora_app.dart';

enum VoiceFailure { certificate, microphone, generic }

class VoiceJoinException implements Exception {
  const VoiceJoinException(this.kind);

  final VoiceFailure kind;
}

class VoiceNotice {
  const VoiceNotice({
    this.certificateRequired = false,
    this.permissionDenied = false,
    this.renew = false,
  });

  final bool certificateRequired;
  final bool permissionDenied;
  final bool renew;
}

/// 수업 코드 채널의 음성. 발표자만 마이크를 내고 참여자는 듣기만 한다.
abstract class VoiceRoom {
  void listen(void Function(VoiceNotice notice) onNotice);

  Future<void> join({
    required String channelId,
    required bool publish,
    String token = '',
    int uid = 0,
  });

  Future<void> renew(String token);

  Future<void> setPublishing(bool publish);

  Future<void> setListening(bool listen);

  Future<void> leave();
}

class AgoraVoiceRoom implements VoiceRoom {
  RtcEngine? _engine;
  bool _inChannel = false;
  String? _channel;
  int _life = 0;
  void Function(VoiceNotice notice)? _onNotice;

  @override
  void listen(void Function(VoiceNotice notice) onNotice) {
    _onNotice = onNotice;
  }

  @override
  Future<void> join({
    required String channelId,
    required bool publish,
    String token = '',
    int uid = 0,
  }) async {
    final engine = await _engineOrCreate();
    if (_inChannel && _channel == channelId) {
      await setPublishing(publish);
      return;
    }
    if (_inChannel) {
      await engine.leaveChannel();
      _inChannel = false;
      _channel = null;
    }
    try {
      await engine.enableLocalAudio(publish);
      await engine.joinChannel(
        token: token,
        channelId: channelId,
        uid: uid,
        options: _options(publish),
      );
      try {
        await engine.setEnableSpeakerphone(true);
      } catch (_) {}
    } catch (error) {
      throw _asJoinException(error);
    }
    _inChannel = true;
    _channel = channelId;
  }

  @override
  Future<void> renew(String token) async {
    final engine = _engine;
    if (engine == null || !_inChannel || token.isEmpty) return;
    await engine.renewToken(token);
  }

  @override
  Future<void> setPublishing(bool publish) async {
    final engine = _engine;
    if (engine == null || !_inChannel) return;
    try {
      await engine.enableLocalAudio(publish);
      await engine.updateChannelMediaOptions(_options(publish));
    } catch (error) {
      throw _asJoinException(error);
    }
  }

  @override
  Future<void> setListening(bool listen) async {
    final engine = _engine;
    if (engine == null || !_inChannel) return;
    await engine.muteAllRemoteAudioStreams(!listen);
  }

  @override
  Future<void> leave() async {
    _life++;
    final engine = _engine;
    _engine = null;
    _inChannel = false;
    _channel = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
  }

  Future<RtcEngine> _engineOrCreate() async {
    final existing = _engine;
    if (existing != null) return existing;
    final life = _life;
    final engine = createAgoraRtcEngine();
    await engine.initialize(
      const RtcEngineContext(
        appId: agoraAppId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );
    if (life != _life) {
      await engine.release();
      throw const VoiceJoinException(VoiceFailure.generic);
    }
    await engine.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioGameStreaming,
    );
    await engine.disableVideo();
    await engine.enableAudio();
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onError: (error, _) {
          if (life != _life) return;
          if (error == ErrorCodeType.errTokenExpired) {
            _onNotice?.call(const VoiceNotice(renew: true));
          } else if (error == ErrorCodeType.errInvalidToken) {
            _onNotice?.call(const VoiceNotice(certificateRequired: true));
          } else if (error == ErrorCodeType.errNoPermission) {
            _onNotice?.call(const VoiceNotice(permissionDenied: true));
          }
        },
        onTokenPrivilegeWillExpire: (_, _) {
          if (life != _life) return;
          _onNotice?.call(const VoiceNotice(renew: true));
        },
        onConnectionStateChanged: (_, _, reason) {
          if (life != _life) return;
          if (reason ==
              ConnectionChangedReasonType.connectionChangedTokenExpired) {
            _onNotice?.call(const VoiceNotice(renew: true));
          } else if (reason ==
              ConnectionChangedReasonType.connectionChangedInvalidToken) {
            _onNotice?.call(const VoiceNotice(certificateRequired: true));
          }
        },
      ),
    );
    _engine = engine;
    return engine;
  }

  ChannelMediaOptions _options(bool publish) {
    return ChannelMediaOptions(
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      clientRoleType: publish
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
      audienceLatencyLevel: publish
          ? null
          : AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
      publishMicrophoneTrack: publish,
      publishCameraTrack: false,
      autoSubscribeAudio: true,
      autoSubscribeVideo: false,
    );
  }

  VoiceJoinException _asJoinException(Object error) {
    if (error is VoiceJoinException) return error;
    if (error is AgoraRtcException) {
      if (error.code == 109 || error.code == 110) {
        return const VoiceJoinException(VoiceFailure.certificate);
      }
      if (error.code == 9) {
        return const VoiceJoinException(VoiceFailure.microphone);
      }
    }
    return const VoiceJoinException(VoiceFailure.generic);
  }
}
