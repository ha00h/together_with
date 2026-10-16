import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../archive/lesson_archive.dart';
import '../archive/lesson_renderer.dart';
import '../documents/document_assembler.dart';
import '../models/document_kind.dart';
import '../models/note_metrics.dart';
import '../models/page_insert.dart';
import '../models/session.dart';
import '../models/stroke.dart';
import '../sync/room_gateway.dart';
import '../sync/room_providers.dart';
import '../sync/stroke_codec.dart';
import 'page_plan.dart';

const hostInk = 0xFF1C1917;
const participantInk = 0xFF1D4ED8;
const inkPalette = <int>[hostInk, 0xFFB91C1C, participantInk, 0xFF15803D];

class EndClassResult {
  const EndClassResult.saved({required this.removedServer}) : message = null;

  const EndClassResult.failed(this.message) : removedServer = false;

  final String? message;
  final bool removedServer;

  bool get ok => message == null;
}

typedef _DocumentBuild = ({
  AssembledDocument document,
  String? partPath,
  int? insertAt,
  int? removeAt,
});

final sessionProvider = NotifierProvider<SessionController, Session?>(
  SessionController.new,
);

class SessionController extends Notifier<Session?> {
  static const _uuid = Uuid();
  static final _random = Random();
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  StreamSubscription<RemoteEvent>? _remoteSub;
  Timer? _liveTimer;
  Stroke? _pendingLive;
  ({bool public, List<Stroke> base, Map<String, Stroke> removed})? _erase;
  var _fetchingVersion = 0;
  Future<void> _documentQueue = Future<void>.value();
  var _clockOffset = Duration.zero;
  Timer? _expiryTimer;

  DateTime serverNow() => DateTime.now().add(_clockOffset);

  @override
  Session? build() {
    ref.onDispose(_stopSync);
    return null;
  }

  Future<void> startRoom({
    required String title,
    required String documentPath,
    required String fileName,
    required DocumentKind documentKind,
    bool radioOn = true,
  }) async {
    final gateway = ref.read(roomGatewayProvider);
    final uid = await gateway.ensureUser();
    await _syncClock(gateway);
    final trimmed = title.trim();
    final roomTitle = trimmed.isEmpty ? '수업' : trimmed;
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _joinCode();
      try {
        await gateway.createRoom(
          code: code,
          hostUid: uid,
          title: roomTitle,
          localPath: documentPath,
          fileName: fileName,
          kind: documentKind,
          radioOn: radioOn,
        );
        _useRoom(
          RoomSnapshot(
            code: code,
            title: roomTitle,
            hostUid: uid,
            viewerUid: uid,
            localPath: documentPath,
            kind: documentKind,
            pageCount: 1,
            pageIndex: 0,
            strokes: const [],
            radioOn: radioOn,
          ),
        );
        await _announce(code, uid);
        await ref.read(activeRoomStoreProvider).save(code);
        return;
      } on RoomCodeTaken catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
        break;
      }
    }
    debugPrint('startRoom failed: $lastError');
    throw const RoomSyncException('수업을 열지 못했습니다. 연결을 확인해 주세요.');
  }

  Future<String?> joinRoom(String raw) async {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return '입장 코드를 입력해 주세요.';
    try {
      final gateway = ref.read(roomGatewayProvider);
      await gateway.ensureUser();
      await _syncClock(gateway);
      final snapshot = await gateway.joinRoom(code);
      if (snapshot == null) {
        final store = ref.read(activeRoomStoreProvider);
        if (await store.read() == code) await store.clear();
        return '없는 입장 코드입니다.';
      }
      final expiresAt = snapshot.expiresAt;
      if (!snapshot.asHost &&
          expiresAt != null &&
          !serverNow().isBefore(expiresAt)) {
        return roomExpiredMessage;
      }
      var privateStrokes = const <Stroke>[];
      if (!snapshot.asHost) {
        final saved = await ref
            .read(privateStrokeStoreProvider)
            .read(snapshot.code, snapshot.viewerUid);
        privateStrokes = shiftForPageChanges(
          saved.strokes,
          pageShiftsOf(snapshot.ops),
          fromVersion: saved.documentVersion,
        );
      }
      final documentPath = await _replay(
        code: snapshot.code,
        start: snapshot.localPath,
        ops: snapshot.ops,
        fromVersion: 1,
      );
      _useRoom(
        snapshot,
        privateStrokes: privateStrokes,
        documentPath: documentPath,
      );
      if (privateStrokes.isNotEmpty) _persistPrivate();
      await _announce(snapshot.code, snapshot.viewerUid);
      await ref.read(activeRoomStoreProvider).save(snapshot.code);
      if (!snapshot.asHost && expiresAt == null) {
        try {
          final started = await gateway.startClock(snapshot.code);
          if (started != null) _applyExpiry(started);
        } catch (error) {
          debugPrint('start clock failed: $error');
        }
      }
      return null;
    } on RoomSyncException catch (error) {
      return error.message;
    } catch (error) {
      debugPrint('joinRoom failed: $error');
      return '입장하지 못했습니다. 연결을 확인해 주세요.';
    }
  }

  void openAsHost({
    required String title,
    required String documentPath,
    required DocumentKind documentKind,
    int pageCount = 1,
  }) {
    final trimmed = title.trim();
    state = Session(
      id: _uuid.v4(),
      title: trimmed.isEmpty ? '수업' : trimmed,
      joinCode: _joinCode(),
      documentPath: documentPath,
      documentKind: documentKind,
      pageCount: pageCount < 1 ? 1 : pageCount,
      pageIndex: 0,
      aspectRatio: 1 / 1.4142,
      role: MemberRole.host,
      openedOnThisDevice: true,
      tool: CanvasTool.pen,
      hostColorArgb: hostInk,
      participantColorArgb: participantInk,
      strokeWidthPx: 3,
      publicStrokes: const [],
      privateStrokes: const [],
    );
  }

  void viewAs(MemberRole role) {
    final current = state;
    if (current == null || !current.openedOnThisDevice) return;
    final live = current.liveStroke;
    final presenter = current.presenterPage;
    state = current.copyWith(
      role: role,
      tool: role == MemberRole.participant && current.tool == CanvasTool.laser
          ? CanvasTool.pen
          : current.tool,
      pageIndex: presenter,
      hostPageIndex: presenter,
      following: true,
      clearLiveStroke: true,
    );
    if (live != null && live.isPublic) _clearRemoteLive(current);
  }

  void enterWorkspace() {
    final current = state;
    final uid = current?.localUid;
    if (current == null || !current.networked || uid == null) return;
    unawaited(_announce(current.joinCode, uid));
    if (current.role == MemberRole.host) {
      _run(
        ref
            .read(roomGatewayProvider)
            .touchRoom(code: current.joinCode, hostUid: uid),
      );
    }
  }

  void leaveWorkspace() {
    if (!ref.mounted) return;
    _commitErase();
    final current = state;
    final uid = current?.localUid;
    if (current == null || !current.networked || uid == null) return;
    final live = current.liveStroke;
    if (live != null) {
      state = current.copyWith(clearLiveStroke: true);
      if (live.isPublic) _clearRemoteLive(current);
    }
    unawaited(() async {
      try {
        await ref
            .read(roomGatewayProvider)
            .leavePresence(code: current.joinCode, uid: uid);
      } catch (error) {
        debugPrint('presence leave failed: $error');
      }
    }());
  }

  void closeSession() {
    final current = state;
    final uid = current?.localUid;
    final code = current?.joinCode;
    final networked = current?.networked ?? false;
    _stopSync();
    state = null;
    if (!networked || uid == null || code == null) return;
    unawaited(() async {
      try {
        await ref.read(roomGatewayProvider).leavePresence(code: code, uid: uid);
      } catch (error) {
        debugPrint('presence leave failed: $error');
      }
    }());
  }

  Future<EndClassResult> endClass() async {
    final current = state;
    if (current == null) {
      return const EndClassResult.failed('열린 수업이 없습니다.');
    }
    try {
      await ref.read(lessonArchiveProvider).export(current);
      await ref.read(lessonListProvider.notifier).refresh();
    } on LessonExportException catch (error) {
      return EndClassResult.failed(error.message);
    } catch (error) {
      debugPrint('endClass export failed: $error');
      return const EndClassResult.failed('기록을 저장하지 못했습니다. 수업은 서버에 그대로 있습니다.');
    }
    var removedServer = false;
    if (current.networked && current.openedOnThisDevice) {
      final uid = current.localUid;
      if (uid == null) {
        return const EndClassResult.failed('기록은 이 기기에 저장했지만 서버 파일을 지우지 못했습니다.');
      }
      try {
        await ref
            .read(roomGatewayProvider)
            .endRoom(code: current.joinCode, hostUid: uid);
        removedServer = true;
      } catch (error) {
        debugPrint('endClass delete failed: $error');
        return const EndClassResult.failed('기록은 이 기기에 저장했지만 서버 파일을 지우지 못했습니다.');
      }
    }
    await ref.read(activeRoomStoreProvider).clear();
    closeSession();
    return EndClassResult.saved(removedServer: removedServer);
  }

  void attachDocument({required int pageCount, required double aspectRatio}) {
    final current = state;
    if (current == null) return;
    var pages = pageCount < 1 ? 1 : pageCount;
    if (current.networked &&
        current.role == MemberRole.participant &&
        pages < current.pageCount) {
      pages = current.pageCount;
    }
    final aspect = aspectRatio <= 0 ? current.aspectRatio : aspectRatio;
    final pageIndex = current.pageIndex >= pages
        ? pages - 1
        : current.pageIndex;
    if (pages == current.pageCount &&
        pageIndex == current.pageIndex &&
        (aspect - current.aspectRatio).abs() < 0.0001) {
      return;
    }
    final hadPublicLive =
        current.networked && current.liveStroke?.isPublic == true;
    state = current.copyWith(
      pageCount: pages,
      pageIndex: pageIndex,
      aspectRatio: aspect,
      clearLiveStroke: true,
    );
    final uid = current.localUid;
    if (uid == null || !current.networked) return;
    if (pages != current.pageCount && current.role == MemberRole.host) {
      _run(
        ref
            .read(roomGatewayProvider)
            .updatePageCount(
              code: current.joinCode,
              writerId: uid,
              pageCount: pages,
            ),
      );
    }
    if (hadPublicLive) {
      _run(
        ref
            .read(roomGatewayProvider)
            .clearLive(code: current.joinCode, writerId: uid),
      );
    }
  }

  Future<({String? error, int dropped})> appendPages(
    List<String> sources,
  ) async {
    if (sources.isEmpty) return (error: null, dropped: 0);
    final firstNew = state?.pageCount ?? 0;
    final plan = ref.read(pagePlanProvider);
    var dropped = 0;
    final error = await _changeDocument((current) async {
      final room = plan.maxPages - current.pageCount;
      if (room <= 0) throw DocumentAssemblyException(plan.limitMessage);
      final assembler = ref.read(documentAssemblerProvider);
      final part = await assembler.assemble(sources, maxPages: room);
      dropped = part.droppedPages;
      final merged = await assembler.assemble([
        current.documentPath,
        part.path,
      ]);
      return (
        document: merged,
        partPath: part.path,
        insertAt: null,
        removeAt: null,
      );
    });
    if (error == null) goToPage(firstNew);
    return (error: error, dropped: error == null ? dropped : 0);
  }

  Future<String?> insertBlankPage() {
    final at = (state?.pageIndex ?? 0) + 1;
    final plan = ref.read(pagePlanProvider);
    return _changeDocument((current) async {
      if (current.pageCount >= plan.maxPages) {
        throw DocumentAssemblyException(plan.limitMessage);
      }
      final merged = await ref
          .read(documentAssemblerProvider)
          .insertBlank(
            current.documentPath,
            at: at,
            aspectRatio: current.aspectRatio,
          );
      return (document: merged, partPath: null, insertAt: at, removeAt: null);
    });
  }

  Future<String?> deletePage() {
    final current = state;
    if (current != null && current.pageCount < 2) {
      return Future.value('마지막 한 장은 삭제할 수 없습니다.');
    }
    final at = current?.pageIndex ?? 0;
    return _changeDocument((current) async {
      final merged = await ref
          .read(documentAssemblerProvider)
          .removePage(current.documentPath, at: at);
      return (document: merged, partPath: null, insertAt: null, removeAt: at);
    });
  }

  Future<String?> _changeDocument(
    Future<_DocumentBuild> Function(Session current) build,
  ) async {
    final current = state;
    if (current == null) return null;
    if (current.role != MemberRole.host || !current.openedOnThisDevice) {
      return '발표자만 페이지를 바꿀 수 있습니다.';
    }
    if (current.classEnded) return '끝난 수업의 페이지는 바꿀 수 없습니다.';
    if (current.documentLoading) return '페이지를 준비하는 중입니다.';
    state = current.copyWith(documentLoading: true, clearLiveStroke: true);
    if (current.liveStroke?.isPublic == true) _clearRemoteLive(current);
    try {
      return await _applyDocumentChange(current, build);
    } finally {
      final latest = state;
      if (latest != null && latest.id == current.id) {
        state = latest.copyWith(documentLoading: false);
      }
    }
  }

  Future<String?> _applyDocumentChange(
    Session current,
    Future<_DocumentBuild> Function(Session current) build,
  ) async {
    final _DocumentBuild built;
    try {
      built = await build(current);
    } on DocumentAssemblyException catch (error) {
      return error.message;
    }
    final document = built.document;
    final partPath = built.partPath;
    final version = current.documentVersion + 1;
    final insertAt = built.insertAt;
    final removeAt = built.removeAt;
    final DocumentOp? localOp = insertAt != null
        ? DocumentOp.blank(
            version: version,
            at: insertAt,
            aspectRatio: current.aspectRatio,
          )
        : removeAt != null
        ? DocumentOp.delete(version: version, at: removeAt)
        : null;
    final pageShift = localOp?.shift;
    List<Stroke> shift(List<Stroke> strokes) => pageShift == null
        ? strokes
        : shiftForPageChanges(strokes, [pageShift], fromVersion: version - 1);
    final landing = pageShift == null
        ? null
        : pageShift.removes
        ? (pageShift.at < document.pageCount
              ? pageShift.at
              : document.pageCount - 1)
        : pageShift.at;
    final uid = current.localUid;
    var moved = <Stroke>[];
    var removed = <String>[];
    if (current.networked) {
      if (uid == null) return '페이지를 올리지 못했습니다.';
      final gateway = ref.read(roomGatewayProvider);
      try {
        final DocumentOp op;
        if (partPath != null) {
          final storagePath = await gateway.uploadPart(
            code: current.joinCode,
            writerId: uid,
            localPath: partPath,
            version: version,
          );
          op = DocumentOp.append(version: version, path: storagePath);
        } else {
          op = localOp!;
        }
        final before = state ?? current;
        if (pageShift != null) {
          for (final stroke in before.publicStrokes) {
            if (pageShift.dropsPage(stroke.pageIndex)) {
              removed.add(stroke.id);
              continue;
            }
            final page = pageShift.mapPage(stroke.pageIndex);
            if (page != stroke.pageIndex) {
              moved.add(stroke.copyWith(pageIndex: page));
            }
          }
        }
        await gateway.publishDocument(
          code: current.joinCode,
          writerId: uid,
          op: op,
          pageCount: document.pageCount,
          moved: moved,
          removed: removed,
          pageIndex: landing,
        );
      } catch (error) {
        debugPrint('change document failed: $error');
        return '페이지를 올리지 못했습니다. 연결을 확인해 주세요.';
      }
    }
    final latest = state;
    if (latest == null || latest.id != current.id) return null;
    final hadPublicLive = latest.liveStroke?.isPublic == true;
    final targetPage = {for (final stroke in moved) stroke.id: stroke.pageIndex};
    final gone = removed.toSet();
    final publicStrokes = current.networked
        ? [
            for (final stroke in latest.publicStrokes)
              if (!gone.contains(stroke.id))
                targetPage.containsKey(stroke.id)
                    ? stroke.copyWith(pageIndex: targetPage[stroke.id])
                    : stroke,
          ]
        : shift(latest.publicStrokes);
    state = latest.copyWith(
      documentPath: document.path,
      documentKind: DocumentKind.pdf,
      documentVersion: version,
      pageCount: document.pageCount,
      pageIndex: landing,
      publicStrokes: publicStrokes,
      privateStrokes: shift(latest.privateStrokes),
      clearLiveStroke: pageShift != null,
    );
    if (pageShift != null && hadPublicLive) _clearRemoteLive(latest);
    return null;
  }

  void goToPage(int index) {
    final current = state;
    if (current == null ||
        current.role != MemberRole.host ||
        current.documentLoading) {
      return;
    }
    if (index < 0 || index >= current.pageCount || index == current.pageIndex) {
      return;
    }
    final hadPublicLive =
        current.networked && current.liveStroke?.isPublic == true;
    state = current.copyWith(pageIndex: index, clearLiveStroke: true);
    final uid = current.localUid;
    if (uid == null || !current.networked) return;
    _run(
      ref
          .read(roomGatewayProvider)
          .publishPage(code: current.joinCode, writerId: uid, pageIndex: index),
      report: true,
    );
    if (hadPublicLive) {
      _run(
        ref
            .read(roomGatewayProvider)
            .clearLive(code: current.joinCode, writerId: uid),
      );
    }
  }

  void selectTool(CanvasTool tool) {
    final current = state;
    if (current == null || current.tool == tool) return;
    if (tool == CanvasTool.laser && !current.drawsPublic) return;
    final live = current.liveStroke;
    state = current.copyWith(tool: tool, clearLiveStroke: true);
    if (live != null && live.isPublic) _clearRemoteLive(current);
  }

  void selectColor(int argb) {
    final current = state;
    if (current == null) return;
    if (current.role == MemberRole.host) {
      state = current.copyWith(hostColorArgb: argb);
    } else {
      state = current.copyWith(participantColorArgb: argb);
    }
  }

  void selectWidth(double logicalPx) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(strokeWidthPx: logicalPx);
  }

  void undo() {
    final current = state;
    if (current == null) return;
    if (current.liveStroke != null) {
      final live = current.liveStroke!;
      state = current.copyWith(clearLiveStroke: true);
      if (live.isPublic) _clearRemoteLive(current);
      return;
    }
    if (current.role == MemberRole.host) {
      if (current.publicStrokes.isEmpty) return;
      final removed = current.publicStrokes.last;
      state = current.copyWith(
        publicStrokes: current.publicStrokes.sublist(
          0,
          current.publicStrokes.length - 1,
        ),
      );
      final uid = current.localUid;
      if (current.networked && uid != null) {
        _run(
          ref
              .read(roomGatewayProvider)
              .deleteStroke(
                code: current.joinCode,
                writerId: uid,
                strokeId: removed.id,
              ),
          report: true,
        );
      }
      return;
    }
    if (current.privateStrokes.isEmpty) return;
    state = current.copyWith(
      privateStrokes: current.privateStrokes.sublist(
        0,
        current.privateStrokes.length - 1,
      ),
    );
    _persistPrivate();
  }

  void placeNote(Offset local, Size size, String text) {
    final current = state;
    final trimmed = text.trim();
    if (current == null ||
        trimmed.isEmpty ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    if (current.drawsPublic && current.classEnded) return;
    final heightNorm = noteHeightNorm(trimmed, current.aspectRatio);
    final anchor = normalizePoint(local.dx, local.dy, size.width, size.height);
    final x = anchor.x.clamp(0.0, 1 - noteWidthNorm);
    final y = anchor.y.clamp(0.0, 1 - heightNorm);
    final shared = current.drawsPublic;
    final note = Stroke(
      id: _uuid.v4(),
      pageIndex: current.pageIndex,
      tool: InkTool.note,
      argb: shared ? notePaper : notePrivatePaper,
      widthNorm: noteWidthNorm,
      heightNorm: heightNorm,
      points: [NormPoint(x.toDouble(), y.toDouble())],
      text: trimmed,
      isPublic: shared,
    );
    state = current.copyWith(
      publicStrokes: shared
          ? [...current.publicStrokes, note]
          : current.publicStrokes,
      privateStrokes: shared
          ? current.privateStrokes
          : [...current.privateStrokes, note],
    );
    if (shared) {
      _syncPublicNote(note);
    } else {
      _persistPrivate();
    }
  }

  void moveNote(String id, NormPoint origin) {
    _changeNote(id, (note) {
      final height = note.heightNorm <= 0 ? 0.1 : note.heightNorm;
      return note.copyWith(
        points: [
          NormPoint(
            origin.x.clamp(0.0, 1 - note.widthNorm).toDouble(),
            origin.y.clamp(0.0, 1 - height).toDouble(),
          ),
        ],
      );
    });
  }

  void toggleNoteFold(String id) {
    _changeNote(id, (note) => note.copyWith(folded: !note.folded));
    syncNote(id);
  }

  void syncNote(String id) {
    final current = state;
    if (current == null) return;
    final note = _ownedNote(current, id);
    if (note == null) return;
    if (note.isPublic) {
      _syncPublicNote(note);
      return;
    }
    _persistPrivate();
  }

  void _changeNote(String id, Stroke Function(Stroke note) change) {
    final current = state;
    if (current == null) return;
    final owned = _ownedNote(current, id);
    if (owned == null || (owned.isPublic && current.classEnded)) return;
    final next = change(owned);
    List<Stroke> replace(List<Stroke> list) => [
      for (final stroke in list) if (stroke.id == id) next else stroke,
    ];
    state = current.copyWith(
      publicStrokes: owned.isPublic
          ? replace(current.publicStrokes)
          : current.publicStrokes,
      privateStrokes: owned.isPublic
          ? current.privateStrokes
          : replace(current.privateStrokes),
    );
  }

  Stroke? _ownedNote(Session session, String id) {
    final source = session.drawsPublic
        ? session.publicStrokes
        : session.privateStrokes;
    for (final stroke in source) {
      if (stroke.id == id && stroke.isNote) return stroke;
    }
    return null;
  }

  void _syncPublicNote(Stroke note) {
    final current = state;
    final uid = current?.localUid;
    if (current == null ||
        !current.drawsPublic ||
        !current.networked ||
        uid == null ||
        current.classEnded) {
      return;
    }
    _run(
      ref
          .read(roomGatewayProvider)
          .commitStroke(code: current.joinCode, writerId: uid, stroke: note),
      report: true,
    );
  }

  void pointerDown(Offset local, Size size) {
    if (state?.documentLoading == true) return;
    _commitErase();
    _commitLeftoverLive();
    final current = state;
    if (current == null || size.width <= 0 || size.height <= 0) return;
    final point = normalizePoint(local.dx, local.dy, size.width, size.height);
    if (current.tool == CanvasTool.eraser) {
      _eraseAt(point);
      return;
    }
    if (current.tool == CanvasTool.note) return;
    if (current.tool == CanvasTool.laser) {
      if (!current.drawsPublic) return;
      final live = _laserStroke(current, [point]);
      state = current.copyWith(liveStroke: live);
      _scheduleLive(live);
      return;
    }
    final live = Stroke(
      id: _uuid.v4(),
      pageIndex: current.pageIndex,
      tool: current.tool == CanvasTool.highlighter
          ? InkTool.highlighter
          : InkTool.pen,
      argb: _inkArgb(current),
      widthNorm: _widthNorm(current, size.width),
      points: [point],
      isPublic: current.drawsPublic,
    );
    state = current.copyWith(liveStroke: live);
    _scheduleLive(live);
  }

  void pointerMove(Offset local, Size size) {
    final current = state;
    if (current == null || size.width <= 0 || size.height <= 0) return;
    final point = normalizePoint(local.dx, local.dy, size.width, size.height);
    if (current.tool == CanvasTool.eraser) {
      _eraseAt(point);
      return;
    }
    final live = current.liveStroke;
    if (live == null) return;
    final last = live.points.last;
    final dx = point.x - last.x;
    final dy = point.y - last.y;
    if ((dx * dx) + (dy * dy) < 0.000004) return;
    if (live.isLaser) {
      final kept = [...live.points, point];
      final tail = kept.length > 8 ? kept.sublist(kept.length - 8) : kept;
      final next = live.copyWith(points: tail);
      state = current.copyWith(liveStroke: next);
      _scheduleLive(next);
      return;
    }
    final next = live.copyWith(points: [...live.points, point]);
    state = current.copyWith(liveStroke: next);
    _scheduleLive(next);
  }

  void cancelStroke() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _pendingLive = null;
    _undoErase();
    final current = state;
    final live = current?.liveStroke;
    if (current == null || live == null) return;
    state = current.copyWith(clearLiveStroke: true);
    if (live.isPublic) _clearRemoteLive(current);
  }

  void pointerUp() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _pendingLive = null;
    _commitErase();
    final current = state;
    final live = current?.liveStroke;
    if (current == null || live == null) return;
    if (live.isLaser) {
      state = current.copyWith(clearLiveStroke: true);
      _clearRemoteLive(current);
      return;
    }
    if (live.isPublic) {
      state = current.copyWith(
        publicStrokes: [...current.publicStrokes, live],
        clearLiveStroke: true,
      );
      final uid = current.localUid;
      if (current.networked && uid != null) {
        final gateway = ref.read(roomGatewayProvider);
        _run(() async {
          await gateway.commitStroke(
            code: current.joinCode,
            writerId: uid,
            stroke: live,
          );
          await gateway.clearLive(code: current.joinCode, writerId: uid);
        }(), report: true);
      }
      return;
    }
    state = current.copyWith(
      privateStrokes: [...current.privateStrokes, live],
      clearLiveStroke: true,
    );
    _persistPrivate();
  }

  void _persistPrivate() {
    final current = state;
    final uid = current?.localUid;
    if (current == null || !current.networked || current.drawsPublic) return;
    if (uid == null) return;
    ref
        .read(privateStrokeStoreProvider)
        .save(
          current.joinCode,
          uid,
          current.privateStrokes,
          documentVersion: current.documentVersion,
        );
  }

  Future<String> _replay({
    required String code,
    required String start,
    required List<DocumentOp> ops,
    required int fromVersion,
  }) async {
    final assembler = ref.read(documentAssemblerProvider);
    final gateway = ref.read(roomGatewayProvider);
    var path = start;
    for (final op in ops) {
      if (op.version <= fromVersion) continue;
      switch (op.type) {
        case DocumentOpType.blank:
          path = (await assembler.insertBlank(
            path,
            at: op.at!,
            aspectRatio: op.aspectRatio!,
          )).path;
        case DocumentOpType.delete:
          path = (await assembler.removePage(path, at: op.at!)).path;
        case DocumentOpType.append:
          final part = await gateway.downloadPart(code, op.path!);
          path = (await assembler.assemble([path, part])).path;
      }
    }
    return path;
  }

  void _useRoom(
    RoomSnapshot snapshot, {
    List<Stroke> privateStrokes = const [],
    String? documentPath,
  }) {
    var pages = snapshot.pageCount < 1 ? 1 : snapshot.pageCount;
    var index = snapshot.pageIndex < 0 ? 0 : snapshot.pageIndex;
    if (index >= pages) pages = index + 1;
    _stopSync();
    state = Session(
      id: snapshot.code,
      title: snapshot.title,
      joinCode: snapshot.code,
      documentPath: documentPath ?? snapshot.localPath,
      documentKind: snapshot.ops.isEmpty ? snapshot.kind : DocumentKind.pdf,
      pageCount: pages,
      pageIndex: index,
      aspectRatio: 1 / 1.4142,
      role: snapshot.asHost ? MemberRole.host : MemberRole.participant,
      openedOnThisDevice: snapshot.asHost,
      tool: CanvasTool.pen,
      hostColorArgb: hostInk,
      participantColorArgb: participantInk,
      strokeWidthPx: 3,
      publicStrokes: snapshot.strokes,
      privateStrokes: privateStrokes,
      remoteLiveStroke: snapshot.live,
      networked: true,
      localUid: snapshot.viewerUid,
      radioEnabled: snapshot.radioOn,
      documentVersion: snapshot.documentVersion,
      hostUid: snapshot.hostUid,
      expiresAt: snapshot.expiresAt,
    );
    _listen(snapshot.code);
    _scheduleExpiry();
  }

  Future<void> _announce(String code, String uid) async {
    try {
      await ref.read(roomGatewayProvider).joinPresence(code: code, uid: uid);
    } catch (error) {
      debugPrint('presence join failed: $error');
    }
  }

  void _listen(String code) {
    _remoteSub?.cancel();
    _remoteSub = ref
        .read(roomGatewayProvider)
        .watch(code)
        .listen(
          _applyRemote,
          onError: (Object error) {
            debugPrint('room watch failed: $error');
            _setWarning('연결이 끊겼습니다. 판서가 늦을 수 있습니다.');
          },
        );
  }

  void _applyRemote(RemoteEvent event) {
    switch (event) {
      case RemoteStrokeAdded(:final stroke):
        _applyStroke(stroke);
      case RemoteStrokeRemoved(:final id):
        _applyRemove(id);
      case RemoteLiveChanged(:final stroke):
        _applyLive(stroke);
      case RemotePageChanged(:final index):
        _applyPage(index);
      case RemoteClassEnded():
        _applyClassEnded();
      case RemoteMembersChanged(:final uids):
        _applyMembers(uids);
      case RemoteDocumentChanged(:final version):
        _applyDocument(version);
      case RemoteFocus():
        _applyFocus();
      case RemoteExpiry(:final expiresAt):
        _applyExpiry(expiresAt);
    }
  }

  void _applyDocument(int version) {
    final current = state;
    if (current == null ||
        current.openedOnThisDevice ||
        current.classEnded ||
        version <= current.documentVersion ||
        version <= _fetchingVersion) {
      return;
    }
    _fetchingVersion = version;
    final code = current.joinCode;
    _documentQueue = _documentQueue.then((_) => _refreshDocument(code));
  }

  Future<void> _refreshDocument(String code) async {
    final start = state;
    if (start == null || start.joinCode != code) return;
    _setDocumentLoading(code, true);
    try {
      final document = await ref
          .read(roomGatewayProvider)
          .fetchDocument(code);
      final base = state;
      if (document == null ||
          base == null ||
          base.joinCode != code ||
          document.version <= base.documentVersion) {
        return;
      }
      final path = await _replay(
        code: code,
        start: base.documentPath,
        ops: document.ops,
        fromVersion: base.documentVersion,
      );
      final latest = state;
      if (latest == null ||
          latest.joinCode != code ||
          latest.documentVersion != base.documentVersion) {
        return;
      }
      final shifts = pageShiftsOf(document.ops);
      final shifted = shiftForPageChanges(
        latest.privateStrokes,
        shifts,
        fromVersion: latest.documentVersion,
      );
      final removedPages = shifts.any(
        (shift) => shift.removes && shift.version > latest.documentVersion,
      );
      final pages = removedPages || document.pageCount > latest.pageCount
          ? document.pageCount
          : latest.pageCount;
      var browsing = latest.following
          ? latest.pageIndex
          : shiftPage(
              latest.pageIndex,
              shifts,
              fromVersion: latest.documentVersion,
            );
      if (browsing >= pages) browsing = pages - 1;
      final hostPage = latest.hostPageIndex >= pages
          ? pages - 1
          : latest.hostPageIndex;
      state = latest.copyWith(
        documentPath: path,
        documentKind: DocumentKind.pdf,
        documentVersion: document.version,
        pageCount: pages,
        pageIndex: browsing,
        hostPageIndex: hostPage,
        privateStrokes: shifted,
        clearLiveStroke: true,
      );
      _persistPrivate();
    } catch (error) {
      debugPrint('document refresh failed: $error');
      _setWarning('새 페이지를 받지 못했습니다. 다시 들어와 주세요.');
    } finally {
      _setDocumentLoading(code, false);
      if (_fetchingVersion <= (state?.documentVersion ?? 0)) {
        _fetchingVersion = 0;
      }
    }
  }

  void _setDocumentLoading(String code, bool loading) {
    final current = state;
    if (current == null ||
        current.joinCode != code ||
        current.documentLoading == loading) {
      return;
    }
    state = current.copyWith(documentLoading: loading, clearLiveStroke: true);
  }

  void _applyStroke(Stroke stroke) {
    final current = state;
    if (current == null || stroke.isLaser) return;
    final index = current.publicStrokes.indexWhere(
      (item) => item.id == stroke.id,
    );
    if (index >= 0) {
      if (sameStoredStroke(current.publicStrokes[index], stroke)) {
        if (current.remoteLiveStroke?.id == stroke.id) {
          state = current.copyWith(clearRemoteLive: true);
        }
        return;
      }
      final next = [...current.publicStrokes];
      next[index] = stroke;
      state = current.copyWith(
        publicStrokes: next,
        clearRemoteLive: current.remoteLiveStroke?.id == stroke.id,
      );
      return;
    }
    state = current.copyWith(
      publicStrokes: [...current.publicStrokes, stroke],
      clearRemoteLive: current.remoteLiveStroke?.id == stroke.id,
    );
  }

  void _applyRemove(String id) {
    final current = state;
    if (current == null || current.classEnded) return;
    if (!current.publicStrokes.any((stroke) => stroke.id == id)) return;
    state = current.copyWith(
      publicStrokes: [
        for (final stroke in current.publicStrokes)
          if (stroke.id != id) stroke,
      ],
    );
  }

  void _applyLive(Stroke? stroke) {
    final current = state;
    if (current == null || current.classEnded) return;
    if (stroke == null) {
      if (current.remoteLiveStroke == null) return;
      state = current.copyWith(clearRemoteLive: true);
      return;
    }
    if (current.liveStroke?.id == stroke.id) return;
    if (current.publicStrokes.any((item) => item.id == stroke.id)) return;
    state = current.copyWith(remoteLiveStroke: stroke);
  }

  void _applyMembers(Set<String> uids) {
    final current = state;
    if (current == null) return;
    final count = uids.isEmpty ? current.memberCount : uids.length;
    final hostUid = current.hostUid;
    final hostPresent = current.role == MemberRole.host ||
        hostUid == null ||
        uids.contains(hostUid);
    if (current.memberCount == count && current.hostPresent == hostPresent) {
      return;
    }
    state = current.copyWith(memberCount: count, hostPresent: hostPresent);
  }

  Future<void> _syncClock(RoomGateway gateway) async {
    try {
      _clockOffset = await gateway.clockOffset();
    } catch (error) {
      debugPrint('clock offset failed: $error');
    }
  }

  void _applyExpiry(DateTime expiresAt) {
    final current = state;
    if (current == null || current.expiresAt == expiresAt) return;
    state = current.copyWith(expiresAt: expiresAt);
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final expiresAt = state?.expiresAt;
    if (expiresAt == null) return;
    final left = expiresAt.difference(serverNow());
    if (left <= Duration.zero) {
      _expire();
      return;
    }
    _expiryTimer = Timer(left, _expire);
  }

  void _expire() {
    _expiryTimer = null;
    final current = state;
    if (current == null || current.expired) return;
    if (current.role == MemberRole.participant) _applyClassEnded();
    final latest = state;
    if (latest == null) return;
    state = latest.copyWith(expired: true, clearLiveStroke: true);
  }

  void _applyClassEnded() {
    final current = state;
    if (current == null || current.classEnded) return;
    final remote = current.remoteLiveStroke;
    final alreadySaved =
        remote != null &&
        current.publicStrokes.any((stroke) => stroke.id == remote.id);
    final strokes = remote == null || remote.isLaser || alreadySaved
        ? current.publicStrokes
        : [...current.publicStrokes, remote];
    state = current.copyWith(
      classEnded: true,
      publicStrokes: strokes,
      clearRemoteLive: true,
    );
  }

  void _applyPage(int index) {
    final current = state;
    if (current == null || index < 0) return;
    final pages = index >= current.pageCount ? index + 1 : current.pageCount;
    if (current.role == MemberRole.host) {
      if (index == current.pageIndex) return;
      state = current.copyWith(
        pageCount: pages,
        pageIndex: index,
        hostPageIndex: index,
        clearLiveStroke: true,
      );
      return;
    }
    final follow = current.following && index != current.pageIndex;
    if (index == current.hostPageIndex && !follow) return;
    state = current.copyWith(
      pageCount: pages,
      hostPageIndex: index,
      pageIndex: follow ? index : null,
      clearLiveStroke: follow,
    );
  }

  void browsePage(int index) {
    final current = state;
    if (current == null ||
        current.role != MemberRole.participant ||
        current.documentLoading ||
        index < 0 ||
        index >= current.pageCount ||
        index == current.pageIndex) {
      return;
    }
    state = current.copyWith(
      pageIndex: index,
      following: false,
      clearLiveStroke: true,
    );
  }

  bool turnPage(int delta) {
    final current = state;
    if (current == null || current.documentLoading) return false;
    final target = current.pageIndex + delta;
    if (target < 0 || target >= current.pageCount) return false;
    if (current.role == MemberRole.host) {
      goToPage(target);
    } else {
      browsePage(target);
    }
    return state?.pageIndex == target;
  }

  void followPresenter() {
    final current = state;
    if (current == null || current.role != MemberRole.participant) return;
    if (current.following && current.pageIndex == current.hostPageIndex) {
      return;
    }
    state = current.copyWith(
      following: true,
      pageIndex: current.hostPageIndex,
      clearLiveStroke: current.pageIndex != current.hostPageIndex,
    );
  }

  void stopFollowing() {
    final current = state;
    if (current == null ||
        current.role != MemberRole.participant ||
        !current.following) {
      return;
    }
    state = current.copyWith(following: false);
  }

  void callAttention() {
    final current = state;
    final uid = current?.localUid;
    if (current == null ||
        current.role != MemberRole.host ||
        !current.networked ||
        uid == null) {
      return;
    }
    _run(
      ref
          .read(roomGatewayProvider)
          .publishFocus(
            code: current.joinCode,
            writerId: uid,
            pageIndex: current.pageIndex,
          ),
      report: true,
    );
  }

  void _applyFocus() {
    final current = state;
    if (current == null || current.role != MemberRole.participant) return;
    state = current.copyWith(
      following: true,
      pageIndex: current.hostPageIndex,
      attentionCount: current.attentionCount + 1,
      clearLiveStroke: current.pageIndex != current.hostPageIndex,
    );
  }

  void _commitLeftoverLive() {
    final current = state;
    final leftover = current?.remoteLiveStroke;
    final uid = current?.localUid;
    if (current == null ||
        leftover == null ||
        uid == null ||
        !current.drawsPublic) {
      return;
    }
    if (!current.networked) return;
    if (leftover.isLaser) {
      state = current.copyWith(clearRemoteLive: true);
      _run(
        ref
            .read(roomGatewayProvider)
            .clearLive(code: current.joinCode, writerId: uid),
      );
      return;
    }
    if (current.publicStrokes.any((stroke) => stroke.id == leftover.id)) {
      state = current.copyWith(clearRemoteLive: true);
      return;
    }
    state = current.copyWith(
      publicStrokes: [...current.publicStrokes, leftover],
      clearRemoteLive: true,
    );
    final gateway = ref.read(roomGatewayProvider);
    _run(() async {
      await gateway.commitStroke(
        code: current.joinCode,
        writerId: uid,
        stroke: leftover,
      );
      await gateway.clearLive(code: current.joinCode, writerId: uid);
    }(), report: true);
  }

  void _eraseAt(NormPoint point) {
    final current = state;
    if (current == null) return;
    final source = current.drawsPublic
        ? current.publicStrokes
        : current.privateStrokes;
    final removeIds = <String>{
      for (final stroke in source)
        if (stroke.pageIndex == current.pageIndex && strokeHits(stroke, point))
          stroke.id,
    };
    if (removeIds.isEmpty) return;
    final erase = _erase ??= (
      public: current.drawsPublic,
      base: source,
      removed: <String, Stroke>{},
    );
    for (final stroke in source) {
      if (removeIds.contains(stroke.id)) erase.removed[stroke.id] = stroke;
    }
    bool keep(Stroke stroke) => !removeIds.contains(stroke.id);
    state = current.copyWith(
      publicStrokes: current.drawsPublic
          ? current.publicStrokes.where(keep).toList()
          : current.publicStrokes,
      privateStrokes: current.drawsPublic
          ? current.privateStrokes
          : current.privateStrokes.where(keep).toList(),
    );
  }

  void _commitErase() {
    final erase = _erase;
    _erase = null;
    final current = state;
    if (erase == null || erase.removed.isEmpty || current == null) return;
    if (!erase.public) {
      _persistPrivate();
      return;
    }
    final uid = current.localUid;
    if (!current.networked || uid == null) return;
    final gateway = ref.read(roomGatewayProvider);
    for (final id in erase.removed.keys) {
      _run(
        gateway.deleteStroke(
          code: current.joinCode,
          writerId: uid,
          strokeId: id,
        ),
        report: true,
      );
    }
  }

  void _undoErase() {
    final erase = _erase;
    _erase = null;
    final current = state;
    if (erase == null || erase.removed.isEmpty || current == null) return;
    List<Stroke> restore(List<Stroke> now) {
      final present = {for (final stroke in now) stroke.id};
      final result = [...now];
      for (var i = 0; i < erase.base.length; i++) {
        final stroke = erase.base[i];
        if (!erase.removed.containsKey(stroke.id) ||
            present.contains(stroke.id)) {
          continue;
        }
        result.insert(min(i, result.length), stroke);
      }
      return result;
    }

    state = erase.public
        ? current.copyWith(publicStrokes: restore(current.publicStrokes))
        : current.copyWith(privateStrokes: restore(current.privateStrokes));
  }

  void _scheduleLive(Stroke stroke) {
    final current = state;
    if (current == null || !current.networked || !stroke.isPublic) return;
    _pendingLive = stroke;
    if (_liveTimer != null) return;
    final interval = ref.read(livePushIntervalProvider);
    if (interval <= Duration.zero) {
      _flushLive();
      return;
    }
    _liveTimer = Timer(interval, _flushLive);
  }

  void _flushLive() {
    _liveTimer = null;
    final stroke = _pendingLive;
    _pendingLive = null;
    final current = state;
    final uid = current?.localUid;
    if (stroke == null || current == null || uid == null || !stroke.isPublic) {
      return;
    }
    _run(
      ref
          .read(roomGatewayProvider)
          .publishLive(code: current.joinCode, writerId: uid, stroke: stroke),
    );
  }

  void _clearRemoteLive(Session current) {
    final uid = current.localUid;
    if (!current.networked || uid == null) return;
    _run(
      ref
          .read(roomGatewayProvider)
          .clearLive(code: current.joinCode, writerId: uid),
    );
  }

  void _run(Future<void> action, {bool report = false}) {
    unawaited(() async {
      try {
        await action;
        if (report) _clearWarning();
      } catch (error) {
        debugPrint('room write failed: $error');
        if (report) _setWarning('판서를 올리지 못했습니다.');
      }
    }());
  }

  void _setWarning(String message) {
    final current = state;
    if (current == null || current.syncWarning == message) return;
    state = current.copyWith(syncWarning: message);
  }

  void _clearWarning() {
    final current = state;
    if (current == null || current.syncWarning == null) return;
    state = current.copyWith(clearSyncWarning: true);
  }

  void _stopSync() {
    _erase = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _liveTimer?.cancel();
    _liveTimer = null;
    _pendingLive = null;
  }

  Stroke _laserStroke(Session session, List<NormPoint> points) {
    return Stroke(
      id: _uuid.v4(),
      pageIndex: session.pageIndex,
      tool: InkTool.laser,
      argb: laserInk,
      widthNorm: 0.02,
      points: points,
      isPublic: true,
    );
  }

  int _inkArgb(Session session) {
    if (session.tool != CanvasTool.highlighter) return session.colorArgb;
    return Color(session.colorArgb).withValues(alpha: 0.45).toARGB32();
  }

  double _widthNorm(Session session, double canvasWidth) {
    final scale = session.tool == CanvasTool.highlighter ? 2.8 : 1.0;
    return (session.strokeWidthPx * scale) / canvasWidth;
  }

  String _joinCode() {
    return List.generate(
      6,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
  }
}
