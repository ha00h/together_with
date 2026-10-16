import 'document_kind.dart';
import 'stroke.dart';

enum MemberRole { host, participant }

class Session {
  const Session({
    required this.id,
    required this.title,
    required this.joinCode,
    required this.documentPath,
    required this.documentKind,
    required this.pageCount,
    required this.pageIndex,
    required this.aspectRatio,
    required this.role,
    required this.openedOnThisDevice,
    required this.tool,
    required this.hostColorArgb,
    required this.participantColorArgb,
    required this.strokeWidthPx,
    required this.publicStrokes,
    required this.privateStrokes,
    this.liveStroke,
    this.remoteLiveStroke,
    this.networked = false,
    this.localUid,
    this.syncWarning,
    this.classEnded = false,
    this.memberCount = 1,
    this.radioEnabled = true,
    this.documentVersion = 1,
    this.documentLoading = false,
    int? hostPageIndex,
    this.following = true,
    this.attentionCount = 0,
    this.hostUid,
    this.hostPresent = true,
    this.expiresAt,
    this.expired = false,
  }) : hostPageIndex = hostPageIndex ?? pageIndex;

  final String id;
  final String title;
  final String joinCode;
  final String documentPath;
  final DocumentKind documentKind;
  final int pageCount;
  final int pageIndex;
  final double aspectRatio;
  final MemberRole role;
  final bool openedOnThisDevice;
  final CanvasTool tool;
  final int hostColorArgb;
  final int participantColorArgb;
  final double strokeWidthPx;
  final List<Stroke> publicStrokes;
  final List<Stroke> privateStrokes;
  final Stroke? liveStroke;
  final Stroke? remoteLiveStroke;
  final bool networked;
  final String? localUid;
  final String? syncWarning;
  final bool classEnded;
  final int memberCount;
  final bool radioEnabled;
  final int documentVersion;
  final bool documentLoading;
  final int hostPageIndex;
  final bool following;
  final int attentionCount;
  final String? hostUid;
  final bool hostPresent;
  final DateTime? expiresAt;
  final bool expired;

  int get colorArgb =>
      role == MemberRole.host ? hostColorArgb : participantColorArgb;

  bool get drawsPublic => role == MemberRole.host;

  int get presenterPage => role == MemberRole.host ? pageIndex : hostPageIndex;

  Session copyWith({
    String? documentPath,
    DocumentKind? documentKind,
    int? documentVersion,
    bool? documentLoading,
    int? hostPageIndex,
    bool? following,
    int? attentionCount,
    bool? hostPresent,
    DateTime? expiresAt,
    bool? expired,
    int? pageCount,
    int? pageIndex,
    double? aspectRatio,
    MemberRole? role,
    CanvasTool? tool,
    int? hostColorArgb,
    int? participantColorArgb,
    double? strokeWidthPx,
    List<Stroke>? publicStrokes,
    List<Stroke>? privateStrokes,
    Stroke? liveStroke,
    bool clearLiveStroke = false,
    Stroke? remoteLiveStroke,
    bool clearRemoteLive = false,
    String? syncWarning,
    bool clearSyncWarning = false,
    bool? classEnded,
    int? memberCount,
    bool? radioEnabled,
  }) {
    return Session(
      id: id,
      title: title,
      joinCode: joinCode,
      documentPath: documentPath ?? this.documentPath,
      documentKind: documentKind ?? this.documentKind,
      pageCount: pageCount ?? this.pageCount,
      pageIndex: pageIndex ?? this.pageIndex,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      role: role ?? this.role,
      openedOnThisDevice: openedOnThisDevice,
      tool: tool ?? this.tool,
      hostColorArgb: hostColorArgb ?? this.hostColorArgb,
      participantColorArgb: participantColorArgb ?? this.participantColorArgb,
      strokeWidthPx: strokeWidthPx ?? this.strokeWidthPx,
      publicStrokes: publicStrokes ?? this.publicStrokes,
      privateStrokes: privateStrokes ?? this.privateStrokes,
      liveStroke: clearLiveStroke ? null : (liveStroke ?? this.liveStroke),
      remoteLiveStroke: clearRemoteLive
          ? null
          : (remoteLiveStroke ?? this.remoteLiveStroke),
      networked: networked,
      localUid: localUid,
      syncWarning: clearSyncWarning ? null : (syncWarning ?? this.syncWarning),
      classEnded: classEnded ?? this.classEnded,
      memberCount: memberCount ?? this.memberCount,
      radioEnabled: radioEnabled ?? this.radioEnabled,
      documentVersion: documentVersion ?? this.documentVersion,
      documentLoading: documentLoading ?? this.documentLoading,
      hostPageIndex: hostPageIndex ?? this.hostPageIndex,
      following: following ?? this.following,
      attentionCount: attentionCount ?? this.attentionCount,
      hostUid: hostUid,
      hostPresent: hostPresent ?? this.hostPresent,
      expiresAt: expiresAt ?? this.expiresAt,
      expired: expired ?? this.expired,
    );
  }
}
