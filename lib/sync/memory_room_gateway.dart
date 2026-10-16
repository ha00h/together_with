import 'dart:async';

import '../models/document_kind.dart';
import '../models/page_insert.dart';
import '../models/stroke.dart';
import 'room_gateway.dart';

class MemoryRoomGateway implements RoomGateway {
  MemoryRoomGateway({this.userId = 'user', DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  String userId;
  DateTime Function() clock;
  var uploads = 0;
  var downloads = 0;
  final _rooms = <String, _MemoryRoom>{};
  final _events = <String, StreamController<RemoteEvent>>{};

  int strokeCount(String code) => _rooms[code]?.strokes.length ?? 0;

  Stroke? serverLive(String code) => _rooms[code]?.live;

  int? serverPage(String code) => _rooms[code]?.pageIndex;

  void dropServerLive(String code) {
    _rooms[code]?.live = null;
  }

  @override
  Future<String> ensureUser() async => userId;

  @override
  Future<void> createRoom({
    required String code,
    required String hostUid,
    required String title,
    required String localPath,
    required String fileName,
    required DocumentKind kind,
    bool radioOn = true,
  }) async {
    if (_rooms.containsKey(code)) throw const RoomCodeTaken();
    _rooms[code] = _MemoryRoom(
      title: title,
      hostUid: hostUid,
      localPath: localPath,
      fileName: fileName,
      kind: kind,
      radioOn: radioOn,
    );
    _emit(code, const RemotePageChanged(0));
  }

  @override
  Future<RoomSnapshot?> joinRoom(String code) async {
    final room = _rooms[code];
    if (room == null) return null;
    var live = room.live;
    if (live == null && room.hostUid == userId && room.draft != null) {
      live = room.draft;
      room.live = live;
      _emit(code, RemoteLiveChanged(live));
    }
    return RoomSnapshot(
      code: code,
      title: room.title,
      hostUid: room.hostUid,
      viewerUid: userId,
      localPath: room.localPath,
      kind: room.kind,
      pageCount: room.pageCount,
      pageIndex: room.pageIndex,
      strokes: room.strokes.values.toList(),
      live: live,
      radioOn: room.radioOn,
      documentVersion: room.version,
      ops: List.of(room.ops),
      expiresAt: room.startedAt?.add(roomLifetime),
    );
  }

  @override
  Future<DateTime?> startClock(String code) async {
    final room = _rooms[code];
    if (room == null) return null;
    if (room.startedAt == null) {
      room.startedAt = clock();
      _emit(code, RemoteExpiry(room.startedAt!.add(roomLifetime)));
    }
    return room.startedAt!.add(roomLifetime);
  }

  @override
  Future<void> touchRoom({required String code, required String hostUid}) async {
    final room = _roomForWrite(code, hostUid);
    if (room != null) room.touchedAt = clock();
  }

  DateTime? touchedAt(String code) => _rooms[code]?.touchedAt;

  @override
  Future<Duration> clockOffset() async =>
      clock().difference(DateTime.now());

  @override
  Stream<RemoteEvent> watch(String code) {
    final room = _rooms[code];
    final controller = _events.putIfAbsent(
      code,
      () => StreamController<RemoteEvent>.broadcast(),
    );
    if (room != null) {
      scheduleMicrotask(() {
        if (controller.isClosed) return;
        for (final stroke in room.strokes.values) {
          controller.add(RemoteStrokeAdded(stroke));
        }
        controller.add(RemoteLiveChanged(room.live));
        controller.add(RemotePageChanged(room.pageIndex));
        controller.add(RemoteMembersChanged({...room.members}));
        controller.add(RemoteDocumentChanged(room.version));
        final started = room.startedAt;
        if (started != null) {
          controller.add(RemoteExpiry(started.add(roomLifetime)));
        }
      });
    }
    return controller.stream;
  }

  @override
  Future<void> updatePageCount({
    required String code,
    required String writerId,
    required int pageCount,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) return;
    room.pageCount = pageCount;
  }

  @override
  Future<void> publishLive({
    required String code,
    required String writerId,
    required Stroke stroke,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) return;
    room.live = stroke;
    if (!stroke.isLaser) room.draft = stroke;
    _emit(code, RemoteLiveChanged(stroke));
  }

  @override
  Future<void> clearLive({
    required String code,
    required String writerId,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) return;
    room.live = null;
    room.draft = null;
    _emit(code, const RemoteLiveChanged(null));
  }

  @override
  Future<void> commitStroke({
    required String code,
    required String writerId,
    required Stroke stroke,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) return;
    room.strokes[stroke.id] = stroke;
    room.draft = null;
    _emit(code, RemoteStrokeAdded(stroke));
  }

  @override
  Future<void> deleteStroke({
    required String code,
    required String writerId,
    required String strokeId,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) return;
    room.strokes.remove(strokeId);
    _emit(code, RemoteStrokeRemoved(strokeId));
  }

  @override
  Future<void> publishPage({
    required String code,
    required String writerId,
    required int pageIndex,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) return;
    room.pageIndex = pageIndex;
    _emit(code, RemotePageChanged(pageIndex));
  }

  @override
  Future<void> publishFocus({
    required String code,
    required String writerId,
    required int pageIndex,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) return;
    room.pageIndex = pageIndex;
    _emit(code, RemotePageChanged(pageIndex));
    _emit(code, const RemoteFocus());
  }

  @override
  Future<void> endRoom({required String code, required String hostUid}) async {
    final room = _rooms[code];
    if (room == null) return;
    if (room.hostUid != hostUid) {
      throw const RoomSyncException('수업을 끝낼 권한이 없습니다.');
    }
    _emit(code, const RemoteClassEnded());
    _rooms.remove(code);
  }

  @override
  Future<void> joinPresence({required String code, required String uid}) async {
    final room = _rooms[code];
    if (room == null || uid.isEmpty) return;
    room.members.add(uid);
    _emit(code, RemoteMembersChanged({...room.members}));
  }

  @override
  Future<void> leavePresence({
    required String code,
    required String uid,
  }) async {
    final room = _rooms[code];
    if (room == null) return;
    room.members.remove(uid);
    _emit(code, RemoteMembersChanged({...room.members}));
  }

  @override
  Future<String> uploadPart({
    required String code,
    required String writerId,
    required String localPath,
    required int version,
  }) async {
    if (_roomForWrite(code, writerId) == null) {
      throw const RoomSyncException('문서를 바꿀 권한이 없습니다.');
    }
    uploads += 1;
    return localPath;
  }

  @override
  Future<String> downloadPart(String code, String storagePath) async {
    downloads += 1;
    return storagePath;
  }

  @override
  Future<void> publishDocument({
    required String code,
    required String writerId,
    required DocumentOp op,
    required int pageCount,
    List<Stroke> moved = const [],
    List<String> removed = const [],
    int? pageIndex,
  }) async {
    final room = _roomForWrite(code, writerId);
    if (room == null) {
      throw const RoomSyncException('문서를 바꿀 권한이 없습니다.');
    }
    final version = op.version;
    room.version = version;
    room.pageCount = pageCount;
    room.ops.add(op);
    for (final stroke in moved) {
      final stored = room.strokes[stroke.id];
      if (stored == null) continue;
      final shifted = stored.copyWith(pageIndex: stroke.pageIndex);
      room.strokes[stroke.id] = shifted;
      _emit(code, RemoteStrokeAdded(shifted));
    }
    for (final id in removed) {
      if (room.strokes.remove(id) != null) {
        _emit(code, RemoteStrokeRemoved(id));
      }
    }
    if (pageIndex != null) {
      room.pageIndex = pageIndex;
      _emit(code, RemotePageChanged(pageIndex));
    }
    _emit(code, RemoteDocumentChanged(version));
  }

  @override
  Future<RoomDocument?> fetchDocument(String code) async {
    final room = _rooms[code];
    if (room == null) return null;
    return RoomDocument(
      version: room.version,
      pageCount: room.pageCount,
      ops: List.of(room.ops),
    );
  }

  _MemoryRoom? _roomForWrite(String code, String writerId) {
    final room = _rooms[code];
    if (room == null || room.hostUid != writerId) return null;
    return room;
  }

  void _emit(String code, RemoteEvent event) {
    final controller = _events[code];
    if (controller == null || controller.isClosed) return;
    controller.add(event);
  }
}

class _MemoryRoom {
  _MemoryRoom({
    required this.title,
    required this.hostUid,
    required this.localPath,
    required this.fileName,
    required this.kind,
    required this.radioOn,
  });

  final String title;
  final String hostUid;
  String localPath;
  final String fileName;
  DocumentKind kind;
  final bool radioOn;
  var version = 1;
  var pageCount = 1;
  final ops = <DocumentOp>[];
  var pageIndex = 0;
  Stroke? live;
  Stroke? draft;
  final strokes = <String, Stroke>{};
  final members = <String>{};
  DateTime? startedAt;
  DateTime? touchedAt;
}
