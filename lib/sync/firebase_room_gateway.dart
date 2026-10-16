import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../firebase_options.dart';
import '../models/document_kind.dart';
import '../models/page_insert.dart';
import '../models/stroke.dart';
import 'room_gateway.dart';
import 'stroke_codec.dart';

class FirebaseRoomGateway implements RoomGateway {
  var _persistenceReady = false;

  FirebaseDatabase get _database {
    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: realtimeDatabaseUrl,
    );
    if (!_persistenceReady) {
      database.setPersistenceEnabled(true);
      _persistenceReady = true;
    }
    return database;
  }

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  Future<String> ensureUser() async {
    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null) return current.uid;
    final credential = await auth.signInAnonymously();
    final uid = credential.user?.uid;
    if (uid == null) {
      throw const RoomSyncException('로그인하지 못했습니다. 연결을 확인해 주세요.');
    }
    return uid;
  }

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
    final extension = sourceExtension(fileName, kind);
    final storagePath = 'rooms/$code/source.$extension';
    final doc = _firestore.collection('rooms').doc(code);
    final existing = await doc.get();
    if (existing.exists) throw const RoomCodeTaken();
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(doc);
      if (snap.exists) throw const RoomCodeTaken();
      transaction.set(doc, {
        'title': title,
        'hostUid': hostUid,
        'storagePath': storagePath,
        'fileName': fileName,
        'kind': kind.name,
        'version': 1,
        'pageCount': 1,
        'radio': radioOn,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    try {
      final room = _database.ref('rooms/$code');
      await room.child('hostUid').set(hostUid);
      await room.child('page').set(0);
      await room.child('touchedAt').set(ServerValue.timestamp);
      await FirebaseStorage.instance
          .ref(storagePath)
          .putFile(
            File(localPath),
            SettableMetadata(contentType: contentTypeFor(extension)),
          );
    } catch (_) {
      await doc.delete();
      await _database.ref('rooms/$code').remove();
      rethrow;
    }
  }

  @override
  Future<RoomSnapshot?> joinRoom(String code) async {
    final viewerUid = await ensureUser();
    final snap = await _firestore.collection('rooms').doc(code).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final hostUid = data['hostUid'];
    final storagePath = data['storagePath'];
    final fileName = data['fileName'];
    final kindName = data['kind'];
    if (hostUid is! String || storagePath is! String || fileName is! String) {
      return null;
    }
    final kind = kindName == DocumentKind.image.name
        ? DocumentKind.image
        : DocumentKind.pdf;
    final version = data['version'] is num
        ? (data['version'] as num).toInt()
        : 1;
    final pageCount = data['pageCount'] is num
        ? (data['pageCount'] as num).toInt()
        : 1;
    final localPath = await _download(
      code: code,
      storagePath: storagePath,
      fileName: fileName,
      kind: kind,
    );
    final room = _database.ref('rooms/$code');
    final strokesSnap = await room.child('strokes').get();
    final liveSnap = await room.child('live').get();
    final pageSnap = await room.child('page').get();
    final startedSnap = await room.child('startedAt').get();
    final strokes = _strokesFrom(strokesSnap.value);
    var live = strokeFromRemote(liveSnap.value);
    if (live == null && viewerUid == hostUid) {
      live = await _readDraft(code);
      if (live != null) {
        await publishLive(code: code, writerId: viewerUid, stroke: live);
      }
    }
    final pageIndex = pageSnap.value is num
        ? (pageSnap.value as num).toInt()
        : 0;
    return RoomSnapshot(
      code: code,
      title: data['title'] is String ? data['title'] as String : '수업',
      hostUid: hostUid,
      viewerUid: viewerUid,
      localPath: localPath,
      kind: kind,
      pageCount: pageCount < 1 ? 1 : pageCount,
      pageIndex: pageIndex < 0 ? 0 : pageIndex,
      strokes: strokes,
      live: live,
      radioOn: data['radio'] != false,
      documentVersion: version,
      ops: documentOpsFrom(data['ops']),
      expiresAt: _expiryFrom(startedSnap.value),
    );
  }

  @override
  Future<DateTime?> startClock(String code) async {
    final started = _database.ref('rooms/$code/startedAt');
    try {
      await started.set(ServerValue.timestamp);
    } catch (_) {
      // Already started by someone else; the rules refuse a second write.
    }
    return _expiryFrom((await started.get()).value);
  }

  @override
  Future<void> touchRoom({required String code, required String hostUid}) {
    return _database.ref('rooms/$code/touchedAt').set(ServerValue.timestamp);
  }

  @override
  Future<Duration> clockOffset() async {
    final event = await _database.ref('.info/serverTimeOffset').once();
    final value = event.snapshot.value;
    return Duration(milliseconds: value is num ? value.round() : 0);
  }

  DateTime? _expiryFrom(Object? startedAt) => startedAt is num
      ? DateTime.fromMillisecondsSinceEpoch(
          startedAt.toInt(),
        ).add(roomLifetime)
      : null;

  @override
  Future<RoomDocument?> fetchDocument(String code) async {
    final snap = await _firestore.collection('rooms').doc(code).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    final version = data['version'] is num
        ? (data['version'] as num).toInt()
        : 1;
    final pageCount = data['pageCount'] is num
        ? (data['pageCount'] as num).toInt()
        : 1;
    return RoomDocument(
      version: version,
      pageCount: pageCount < 1 ? 1 : pageCount,
      ops: documentOpsFrom(data['ops']),
    );
  }

  @override
  Future<String> downloadPart(String code, String storagePath) {
    return _download(
      code: code,
      storagePath: storagePath,
      fileName: 'part.pdf',
      kind: DocumentKind.pdf,
    );
  }

  @override
  Future<String> uploadPart({
    required String code,
    required String writerId,
    required String localPath,
    required int version,
  }) async {
    final storagePath = 'rooms/$code/part-$version.pdf';
    await FirebaseStorage.instance
        .ref(storagePath)
        .putFile(
          File(localPath),
          SettableMetadata(contentType: contentTypeFor('pdf')),
        );
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
    final doc = _firestore.collection('rooms').doc(code);
    final snap = await doc.get();
    final data = snap.data();
    if (!snap.exists || data == null || data['hostUid'] != writerId) {
      throw const RoomSyncException('문서를 바꿀 권한이 없습니다.');
    }
    await doc.update({
      'version': op.version,
      'pageCount': pageCount,
      'ops': FieldValue.arrayUnion([op.toMap()]),
    });
    await _database.ref('rooms/$code').update({
      'doc': op.version,
      if (pageIndex != null) 'page': pageIndex,
      for (final stroke in moved) 'strokes/${stroke.id}/page': stroke.pageIndex,
      for (final id in removed) 'strokes/$id': null,
    });
  }

  @override
  Stream<RemoteEvent> watch(String code) {
    final controller = StreamController<RemoteEvent>();
    final room = _database.ref('rooms/$code');
    var knownStrokes = <String, Stroke>{};
    Stroke? knownLive;
    int? page;
    var ended = false;
    Set<String>? knownMembers;
    int? docVersion;
    Object? focus;
    var focusSeen = false;
    Object? startedAt;
    final subscription = room.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        if (raw == null) {
          if (!ended) {
            ended = true;
            controller.add(const RemoteClassEnded());
          }
          return;
        }
        final map = asStringMap(raw);
        if (map == null) return;
        if (map['ended'] == true) {
          if (!ended) {
            ended = true;
            controller.add(const RemoteClassEnded());
          }
          return;
        }
        final nextPage = map['page'];
        if (nextPage is num && nextPage.toInt() != page) {
          page = nextPage.toInt();
          controller.add(RemotePageChanged(page!));
        }
        final nextFocus = map['focus'];
        if (!focusSeen) {
          focusSeen = true;
          focus = nextFocus;
        } else if (nextFocus != null && nextFocus != focus) {
          focus = nextFocus;
          controller.add(const RemoteFocus());
        }
        final nextLive = strokeFromRemote(map['live']);
        if (!sameLivePreview(knownLive, nextLive)) {
          knownLive = nextLive;
          controller.add(RemoteLiveChanged(nextLive));
        }
        final members = asStringMap(map['members']);
        final nextMembers = {...?members?.keys};
        final previous = knownMembers;
        if (previous == null ||
            previous.length != nextMembers.length ||
            !previous.containsAll(nextMembers)) {
          knownMembers = nextMembers;
          controller.add(RemoteMembersChanged(nextMembers));
        }
        final nextStarted = map['startedAt'];
        if (nextStarted != startedAt) {
          startedAt = nextStarted;
          final expiresAt = _expiryFrom(nextStarted);
          if (expiresAt != null) controller.add(RemoteExpiry(expiresAt));
        }
        final nextDoc = map['doc'];
        if (nextDoc is num && nextDoc.toInt() != docVersion) {
          docVersion = nextDoc.toInt();
          controller.add(RemoteDocumentChanged(docVersion!));
        }
        final nextStrokes = {
          for (final stroke in _strokesFrom(map['strokes'])) stroke.id: stroke,
        };
        if (!ended) {
          for (final id in knownStrokes.keys) {
            if (!nextStrokes.containsKey(id)) {
              controller.add(RemoteStrokeRemoved(id));
            }
          }
        }
        for (final stroke in _strokesFrom(map['strokes'])) {
          final known = knownStrokes[stroke.id];
          if (known == null || !sameStoredStroke(known, stroke)) {
            controller.add(RemoteStrokeAdded(stroke));
          }
        }
        knownStrokes = nextStrokes;
      },
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
    return controller.stream;
  }

  @override
  Future<void> updatePageCount({
    required String code,
    required String writerId,
    required int pageCount,
  }) {
    return _firestore.collection('rooms').doc(code).update({
      'pageCount': pageCount,
    });
  }

  @override
  Future<void> publishLive({
    required String code,
    required String writerId,
    required Stroke stroke,
  }) async {
    if (!stroke.isLaser) await _writeDraft(code, stroke);
    await _database.ref('rooms/$code/live').set(strokeToMap(stroke));
  }

  @override
  Future<void> clearLive({
    required String code,
    required String writerId,
  }) async {
    await _database.ref('rooms/$code/live').remove();
    await _deleteDraft(code);
  }

  @override
  Future<void> commitStroke({
    required String code,
    required String writerId,
    required Stroke stroke,
  }) async {
    await _database
        .ref('rooms/$code/strokes/${stroke.id}')
        .set(strokeToMap(stroke));
    await _deleteDraft(code);
  }

  @override
  Future<void> deleteStroke({
    required String code,
    required String writerId,
    required String strokeId,
  }) {
    return _database.ref('rooms/$code/strokes/$strokeId').remove();
  }

  @override
  Future<void> publishPage({
    required String code,
    required String writerId,
    required int pageIndex,
  }) {
    return _database.ref('rooms/$code/page').set(pageIndex);
  }

  @override
  Future<void> publishFocus({
    required String code,
    required String writerId,
    required int pageIndex,
  }) {
    return _database.ref('rooms/$code').update({
      'page': pageIndex,
      'focus': ServerValue.timestamp,
    });
  }

  @override
  Future<void> endRoom({required String code, required String hostUid}) async {
    final doc = _firestore.collection('rooms').doc(code);
    final snap = await doc.get();
    final data = snap.data();
    if (snap.exists) {
      if (data?['hostUid'] != hostUid) {
        throw const RoomSyncException('수업을 끝낼 권한이 없습니다.');
      }
      await _database.ref('rooms/$code/ended').set(true);
      final storagePath = data?['storagePath'];
      final paths = [
        if (storagePath is String && storagePath.isNotEmpty) storagePath,
        for (final op in documentOpsFrom(data?['ops']))
          if (op.path != null) op.path!,
      ];
      for (final path in paths) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') rethrow;
        }
      }
    }
    await _database.ref('rooms/$code').remove();
    if (snap.exists) await doc.delete();
  }

  @override
  Future<void> joinPresence({required String code, required String uid}) async {
    final member = _database.ref('rooms/$code/members/$uid');
    await member.onDisconnect().remove();
    await member.set(true);
  }

  @override
  Future<void> leavePresence({required String code, required String uid}) async {
    final member = _database.ref('rooms/$code/members/$uid');
    try {
      await member.onDisconnect().cancel();
    } catch (_) {}
    await member.remove();
  }

  List<Stroke> _strokesFrom(Object? raw) {
    final map = asStringMap(raw);
    if (map == null) return const [];
    final decoded = <({int at, Stroke stroke})>[];
    for (final entry in map.entries) {
      final stroke = strokeFromRemote(entry.value, fallbackId: entry.key);
      if (stroke == null) continue;
      decoded.add((at: strokeSortKey(entry.value), stroke: stroke));
    }
    decoded.sort((a, b) => a.at.compareTo(b.at));
    return [for (final item in decoded) item.stroke];
  }

  Future<String> _download({
    required String code,
    required String storagePath,
    required String fileName,
    required DocumentKind kind,
  }) async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory('${support.path}/rooms/$code');
    await folder.create(recursive: true);
    final extension = sourceExtension(fileName, kind);
    final stem = storagePath
        .split('/')
        .last
        .replaceAll(RegExp(r'\.[^.]*$'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${folder.path}/$stem.$extension');
    if (await file.exists() && await file.length() > 0) return file.path;
    final partial = File('${file.path}.part');
    await FirebaseStorage.instance.ref(storagePath).writeToFile(partial);
    await partial.rename(file.path);
    return file.path;
  }

  Future<File> _draftFile(String code) async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory('${support.path}/rooms/$code');
    await folder.create(recursive: true);
    return File('${folder.path}/draft.json');
  }

  Future<void> _writeDraft(String code, Stroke stroke) async {
    final file = await _draftFile(code);
    await file.writeAsString(jsonEncode(strokeToMap(stroke)));
  }

  Future<Stroke?> _readDraft(String code) async {
    final file = await _draftFile(code);
    if (!await file.exists()) return null;
    final raw = jsonDecode(await file.readAsString());
    return strokeFromRemote(raw);
  }

  Future<void> _deleteDraft(String code) async {
    final file = await _draftFile(code);
    if (await file.exists()) await file.delete();
  }
}

String sourceExtension(String fileName, DocumentKind kind) {
  if (kind == DocumentKind.pdf) return 'pdf';
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'png';
  final extension = fileName.substring(dot + 1).toLowerCase();
  if (extension == 'jpg' || extension == 'jpeg') return 'jpg';
  if (extension == 'png') return 'png';
  return 'png';
}

String contentTypeFor(String extension) {
  switch (extension) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    default:
      return 'application/octet-stream';
  }
}
