import 'dart:async';

import '../models/document_kind.dart';
import '../models/page_insert.dart';
import '../models/stroke.dart';

const roomLifetime = Duration(days: 1);

class RoomCodeTaken implements Exception {
  const RoomCodeTaken();
}

class RoomSyncException implements Exception {
  const RoomSyncException(this.message);

  final String message;
}

class RoomSnapshot {
  const RoomSnapshot({
    required this.code,
    required this.title,
    required this.hostUid,
    required this.viewerUid,
    required this.localPath,
    required this.kind,
    required this.pageCount,
    required this.pageIndex,
    required this.strokes,
    this.live,
    this.radioOn = true,
    this.documentVersion = 1,
    this.ops = const [],
    this.expiresAt,
  });

  final String code;
  final String title;
  final String hostUid;
  final DateTime? expiresAt;
  final String viewerUid;
  final String localPath;
  final DocumentKind kind;
  final int pageCount;
  final int pageIndex;
  final List<Stroke> strokes;
  final Stroke? live;
  final bool radioOn;
  final int documentVersion;
  final List<DocumentOp> ops;

  bool get asHost => viewerUid == hostUid;
}

class RoomDocument {
  const RoomDocument({
    required this.version,
    required this.pageCount,
    this.ops = const [],
  });

  final int version;
  final int pageCount;
  final List<DocumentOp> ops;
}

sealed class RemoteEvent {
  const RemoteEvent();
}

class RemoteStrokeAdded extends RemoteEvent {
  const RemoteStrokeAdded(this.stroke);

  final Stroke stroke;
}

class RemoteStrokeRemoved extends RemoteEvent {
  const RemoteStrokeRemoved(this.id);

  final String id;
}

class RemoteLiveChanged extends RemoteEvent {
  const RemoteLiveChanged(this.stroke);

  final Stroke? stroke;
}

class RemotePageChanged extends RemoteEvent {
  const RemotePageChanged(this.index);

  final int index;
}

class RemoteClassEnded extends RemoteEvent {
  const RemoteClassEnded();
}

class RemoteMembersChanged extends RemoteEvent {
  const RemoteMembersChanged(this.uids);

  final Set<String> uids;

  int get count => uids.length;
}

class RemoteFocus extends RemoteEvent {
  const RemoteFocus();
}

class RemoteExpiry extends RemoteEvent {
  const RemoteExpiry(this.expiresAt);

  final DateTime expiresAt;
}

class RemoteDocumentChanged extends RemoteEvent {
  const RemoteDocumentChanged(this.version);

  final int version;
}

abstract class RoomGateway {
  Future<String> ensureUser();

  Future<void> createRoom({
    required String code,
    required String hostUid,
    required String title,
    required String localPath,
    required String fileName,
    required DocumentKind kind,
    bool radioOn = true,
  });

  Future<RoomSnapshot?> joinRoom(String code);

  Stream<RemoteEvent> watch(String code);

  Future<void> updatePageCount({
    required String code,
    required String writerId,
    required int pageCount,
  });

  Future<void> publishLive({
    required String code,
    required String writerId,
    required Stroke stroke,
  });

  Future<void> clearLive({required String code, required String writerId});

  Future<void> commitStroke({
    required String code,
    required String writerId,
    required Stroke stroke,
  });

  Future<void> deleteStroke({
    required String code,
    required String writerId,
    required String strokeId,
  });

  Future<void> publishPage({
    required String code,
    required String writerId,
    required int pageIndex,
  });

  Future<void> publishFocus({
    required String code,
    required String writerId,
    required int pageIndex,
  });

  Future<void> endRoom({required String code, required String hostUid});

  Future<void> joinPresence({required String code, required String uid});

  Future<void> leavePresence({required String code, required String uid});

  Future<String> uploadPart({
    required String code,
    required String writerId,
    required String localPath,
    required int version,
  });

  Future<void> publishDocument({
    required String code,
    required String writerId,
    required DocumentOp op,
    required int pageCount,
    List<Stroke> moved = const [],
    List<String> removed = const [],
    int? pageIndex,
  });

  Future<RoomDocument?> fetchDocument(String code);

  Future<String> downloadPart(String code, String storagePath);

  /// Starts the room's lifetime once, on the first participant's arrival.
  Future<DateTime?> startClock(String code);

  /// Marks the host's visit; unjoined rooms are purged 7 days after it.
  Future<void> touchRoom({required String code, required String hostUid});

  /// Server time minus this device's time.
  Future<Duration> clockOffset();
}
