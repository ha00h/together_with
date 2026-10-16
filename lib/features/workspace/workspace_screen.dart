import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../documents/document_picker.dart';
import '../../models/note_metrics.dart';
import '../../models/room_clock.dart';
import '../../models/session.dart';
import '../../models/stroke.dart';
import '../../radio/radio_controller.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/form_factor.dart';
import '../home/end_class_button.dart';
import 'document_view.dart';
import 'stroke_painter.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  late final SessionController _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(sessionProvider.notifier);
    _notifier.enterWorkspace();
  }

  @override
  void dispose() {
    scheduleMicrotask(_notifier.leaveWorkspace);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const _WorkspaceView();
}

class _WorkspaceView extends ConsumerWidget {
  const _WorkspaceView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) {
      return const Scaffold(body: Center(child: Text('열린 세션이 없습니다.')));
    }
    final notifier = ref.read(sessionProvider.notifier);
    final isHost = session.role == MemberRole.host;
    ref.listen(
      sessionProvider.select((value) => value?.attentionCount ?? 0),
      (previous, next) {
        if (next <= (previous ?? 0)) return;
        final page = (ref.read(sessionProvider)?.hostPageIndex ?? 0) + 1;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('발표자가 모두를 $page쪽으로 불렀습니다.')),
          );
      },
    );
    ref.listen(
      sessionProvider.select((value) => value?.hostPresent ?? true),
      (previous, next) {
        final current = ref.read(sessionProvider);
        if (previous == null ||
            previous == next ||
            current == null ||
            current.role == MemberRole.host ||
            current.classEnded) {
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                next ? '발표자가 돌아왔습니다.' : '발표자가 잠시 나갔습니다. 돌아오면 이어서 진행됩니다.',
              ),
            ),
          );
      },
    );
    final landscape = isLandscape(context);
    final page = _PageStage(session: session);
    final radioWarning = session.networked && session.radioEnabled
        ? ref.watch(radioProvider).warning
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              session.networked
                  ? '코드 ${session.joinCode} · ${isHost ? '발표자' : '참여자'} · ${session.memberCount}명${session.radioEnabled ? '' : ' · 라디오 끔'}'
                  : '코드 ${session.joinCode} · ${isHost ? '발표자' : '참여자'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF57534E)),
            ),
            if (session.networked && isHost) _RoomClock(session: session),
          ],
        ),
        actions: [
          const EndClassButton(popOnSuccess: true),
          if (session.networked && isHost && !session.classEnded)
            IconButton(
              key: const Key('call-attention'),
              tooltip: '모두 내 페이지로',
              onPressed: () {
                notifier.callAttention();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '참여자를 모두 ${session.pageIndex + 1}쪽으로 불렀습니다.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.campaign_outlined),
            ),
          if (session.networked && session.radioEnabled && isHost)
            const _HostMicButton(),
          if (session.networked && session.radioEnabled && !isHost)
            const _ListenButton(),
          if (session.openedOnThisDevice)
            IconButton(
              tooltip: isHost ? '참여자 화면' : '발표자 화면',
              onPressed: () => notifier.viewAs(
                isHost ? MemberRole.participant : MemberRole.host,
              ),
              icon: Icon(
                isHost ? Icons.smartphone_outlined : Icons.tablet_outlined,
              ),
            ),
        ],
      ),
      body: landscape
          ? Row(
              children: [
                Expanded(
                  child: _StageColumn(
                    session: session,
                    page: page,
                    radioWarning: radioWarning,
                  ),
                ),
                _SideRail(key: const Key('landscape-rail'), session: session),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: _StageColumn(
                    session: session,
                    page: page,
                    radioWarning: radioWarning,
                  ),
                ),
                _PortraitDock(
                  key: const Key('portrait-dock'),
                  session: session,
                ),
              ],
            ),
    );
  }
}

class _StageColumn extends StatelessWidget {
  const _StageColumn({
    required this.session,
    required this.page,
    this.radioWarning,
  });

  final Session session;
  final Widget page;
  final String? radioWarning;

  @override
  Widget build(BuildContext context) {
    final isHost = session.role == MemberRole.host;
    final tablet = isTablet(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tablet ? 28 : 20,
            0,
            tablet ? 28 : 20,
            8,
          ),
          child: Row(
            children: [
              Text(
                isHost ? '공용 판서' : '개인 노트',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isHost ? '이 필기는 참여자 화면에 보입니다.' : '내 기기에만 남고, 공용 판서는 따라갑니다.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF57534E),
                  ),
                ),
              ),
              Text('${session.pageIndex + 1} / ${session.pageCount}'),
            ],
          ),
        ),
        if (!isHost && session.networked)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tablet ? 28 : 20,
              0,
              tablet ? 28 : 20,
              8,
            ),
            child: _FollowBar(session: session),
          ),
        if (session.classEnded && !session.openedOnThisDevice)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tablet ? 28 : 20,
              0,
              tablet ? 28 : 20,
              8,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  session.expired
                      ? '수업 시간(24시간)이 끝났습니다. 기록 저장을 눌러 공용 판서와 내 노트를 이 기기에 남기세요.'
                      : '발표자가 수업을 끝냈습니다. 기록 저장을 눌러 공용 판서와 내 노트를 이 기기에 남기세요.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        if (session.syncWarning != null || radioWarning != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tablet ? 28 : 20,
              0,
              tablet ? 28 : 20,
              8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  if (session.syncWarning != null) session.syncWarning!,
                  if (radioWarning != null) radioWarning!,
                ].join('\n'),
                style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              tablet ? 24 : 12,
              0,
              tablet ? 12 : 12,
              tablet ? 16 : 0,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE7E1D8),
                borderRadius: BorderRadius.circular(tablet ? 20 : 16),
              ),
              child: page,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomClock extends ConsumerStatefulWidget {
  const _RoomClock({required this.session});

  final Session session;

  @override
  ConsumerState<_RoomClock> createState() => _RoomClockState();
}

class _RoomClockState extends ConsumerState<_RoomClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = widget.session.expiresAt;
    final now = ref.read(sessionProvider.notifier).serverNow();
    final urgent =
        expiresAt != null &&
        expiresAt.difference(now) < const Duration(hours: 1);
    return Text(
      remainingLabel(expiresAt, now),
      key: const Key('room-clock'),
      style: TextStyle(
        fontSize: 12,
        fontWeight: urgent ? FontWeight.w700 : FontWeight.w400,
        color: urgent ? const Color(0xFFB91C1C) : const Color(0xFF57534E),
      ),
    );
  }
}

class _FollowBar extends ConsumerWidget {
  const _FollowBar({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presenter = session.hostPageIndex + 1;
    final following = session.following;
    final away = !session.hostPresent && !session.classEnded;
    final status = away
        ? '발표자가 잠시 나가 있습니다 · 마지막 위치 $presenter쪽'
        : following
        ? '발표자는 $presenter쪽 · 함께 넘어갑니다'
        : session.pageIndex == session.hostPageIndex
        ? '혼자 보는 중 · 발표자도 이 페이지에 있습니다'
        : '혼자 보는 중 · 발표자는 $presenter쪽';
    return DecoratedBox(
      key: away ? const Key('host-away') : null,
      decoration: BoxDecoration(
        color: away
            ? const Color(0xFFE5E7EB)
            : following
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                status,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Text('발표자 따라가기', style: TextStyle(fontSize: 12)),
            Switch(
              key: const Key('follow-presenter'),
              value: following,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (on) {
                final notifier = ref.read(sessionProvider.notifier);
                on ? notifier.followPresenter() : notifier.stopFollowing();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PageStage extends ConsumerStatefulWidget {
  const _PageStage({required this.session});

  final Session session;

  @override
  ConsumerState<_PageStage> createState() => _PageStageState();
}

enum _NoteTouch { place, drag, fold }

class _PageStageState extends ConsumerState<_PageStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  var _turnDirection = 0;
  var _turnPending = false;
  Timer? _turnFallback;
  _NoteTouch? _touch;
  String? _dragId;
  NormPoint? _dragOrigin;
  Offset? _down;
  var _moved = false;
  var _rendering = false;
  final _touches = <int, Offset>{};
  final _styluses = <int>{};
  var _swiping = false;
  var _swipeDone = false;
  Offset? _swipeStart;
  Offset? _swipeLast;
  var _stageWidth = 0.0;

  @override
  void didUpdateWidget(_PageStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.session.pageIndex;
    final to = widget.session.pageIndex;
    if (from == to || MediaQuery.of(context).disableAnimations) return;
    _turnDirection = to > from ? 1 : -1;
    _turn.value = 0;
    _turnPending = true;
    _turnFallback?.cancel();
    _turnFallback = Timer(const Duration(milliseconds: 800), _playTurn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (mounted && !_rendering) _playTurn();
      });
    });
  }

  void _playTurn() {
    _turnFallback?.cancel();
    _turnFallback = null;
    if (!mounted || !_turnPending) return;
    _turnPending = false;
    _turn.forward(from: 0);
  }

  @override
  void dispose() {
    _turnFallback?.cancel();
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final busy = session.documentLoading || _rendering;
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = constraints.maxWidth;
        var height = width / session.aspectRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * session.aspectRatio;
        }
        final size = Size(width, height);
        _stageWidth = width;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.white),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: AnimatedBuilder(
                      animation: _turn,
                      builder: (context, child) {
                        final t = Curves.easeOutCubic.transform(_turn.value);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(
                              _turnDirection * width * 0.18 * (1 - t),
                              0,
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DocumentView(
                            path: session.documentPath,
                            kind: session.documentKind,
                            pageIndex: session.pageIndex,
                            onBusy: (value) {
                              if (!mounted || _rendering == value) return;
                              setState(() => _rendering = value);
                              if (!value) _playTurn();
                            },
                            onReady: (pageCount, aspectRatio) {
                              ref
                                  .read(sessionProvider.notifier)
                                  .attachDocument(
                                    pageCount: pageCount,
                                    aspectRatio: aspectRatio,
                                  );
                            },
                          ),
                          CustomPaint(
                            painter: StrokePainter(
                              strokes: _visibleStrokes(session),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AbsorbPointer(
                    absorbing: busy,
                    child: Listener(
                      key: const Key('page-stage'),
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerEnd,
                      onPointerCancel: _onPointerEnd,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) => _onStart(details, size),
                        onPanUpdate: (details) => _onMove(details, size),
                        onPanEnd: (_) => _onEnd(size),
                        onPanCancel: _onCancel,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  if (session.documentLoading)
                    const ColoredBox(
                      key: Key('document-loading'),
                      color: Color(0x99FFFFFF),
                      child: Center(
                        child: Text(
                          '페이지를 준비하는 중입니다',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (busy)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_touches.isEmpty && _styluses.isEmpty) {
      _swiping = false;
      _swipeDone = false;
    }
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
    } else {
      _styluses.add(event.pointer);
      return;
    }
    if (_touches.length == 2 && _styluses.isEmpty && !_swiping) {
      _beginSwipe();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.localPosition;
    if (_swiping && !_swipeDone && _touches.length >= 2) {
      _swipeLast = _centroid();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _styluses.remove(event.pointer);
    if (_touches.remove(event.pointer) == null) return;
    if (!_swiping || _swipeDone || _touches.length >= 2) return;
    _swipeDone = true;
    final start = _swipeStart;
    final last = _swipeLast;
    if (start == null || last == null) return;
    final dx = last.dx - start.dx;
    final dy = last.dy - start.dy;
    final threshold = math.max(48.0, _stageWidth * 0.12);
    if (dx.abs() < threshold || dx.abs() < dy.abs() * 1.2) return;
    ref.read(sessionProvider.notifier).turnPage(dx < 0 ? 1 : -1);
  }

  void _beginSwipe() {
    _swiping = true;
    _swipeStart = _centroid();
    _swipeLast = _swipeStart;
    final dragId = _touch == _NoteTouch.drag ? _dragId : null;
    _touch = null;
    _dragId = null;
    _dragOrigin = null;
    _down = null;
    final notifier = ref.read(sessionProvider.notifier);
    if (dragId != null) notifier.syncNote(dragId);
    notifier.cancelStroke();
  }

  Offset _centroid() {
    var sum = Offset.zero;
    for (final point in _touches.values) {
      sum += point;
    }
    return sum / _touches.length.toDouble();
  }

  void _onStart(DragStartDetails details, Size size) {
    if (_swiping) return;
    final session = ref.read(sessionProvider);
    _touch = null;
    _dragId = null;
    _dragOrigin = null;
    _down = details.localPosition;
    _moved = false;
    if (session != null && session.tool == CanvasTool.note) {
      final point = normalizePoint(
        details.localPosition.dx,
        details.localPosition.dy,
        size.width,
        size.height,
      );
      final note = _topNote(session, point);
      if (note != null && _canEdit(session, note) && noteFoldHit(note, point)) {
        ref.read(sessionProvider.notifier).toggleNoteFold(note.id);
        _touch = _NoteTouch.fold;
        return;
      }
      if (note != null && _canEdit(session, note)) {
        _touch = _NoteTouch.drag;
        _dragId = note.id;
        _dragOrigin = note.points.first;
        return;
      }
      if (note != null) {
        _touch = _NoteTouch.fold;
        return;
      }
      _touch = _NoteTouch.place;
      return;
    }
    ref
        .read(sessionProvider.notifier)
        .pointerDown(details.localPosition, size);
  }

  void _onMove(DragUpdateDetails details, Size size) {
    if (_swiping) return;
    if (_touch == _NoteTouch.drag &&
        _dragId != null &&
        _dragOrigin != null &&
        _down != null) {
      final delta = details.localPosition - _down!;
      if (delta.distance > 8) _moved = true;
      ref.read(sessionProvider.notifier).moveNote(
        _dragId!,
        NormPoint(
          _dragOrigin!.x + delta.dx / size.width,
          _dragOrigin!.y + delta.dy / size.height,
        ),
      );
      return;
    }
    if (_touch == _NoteTouch.place && _down != null) {
      if ((details.localPosition - _down!).distance > 8) _moved = true;
      return;
    }
    if (_touch != null) return;
    ref.read(sessionProvider.notifier).pointerMove(details.localPosition, size);
  }

  void _onEnd(Size size) {
    if (_swiping) return;
    final touch = _touch;
    final down = _down;
    final dragId = _dragId;
    _touch = null;
    _dragId = null;
    _dragOrigin = null;
    _down = null;
    if (touch == _NoteTouch.drag && dragId != null) {
      ref.read(sessionProvider.notifier).syncNote(dragId);
      return;
    }
    if (touch == _NoteTouch.place && down != null && !_moved) {
      _askStickyNote(context, ref, down, size);
      return;
    }
    if (touch != null) return;
    ref.read(sessionProvider.notifier).pointerUp();
  }

  void _onCancel() {
    if (_swiping) return;
    final dragId = _touch == _NoteTouch.drag ? _dragId : null;
    _touch = null;
    _dragId = null;
    _dragOrigin = null;
    _down = null;
    if (dragId != null) {
      ref.read(sessionProvider.notifier).syncNote(dragId);
      return;
    }
    ref.read(sessionProvider.notifier).pointerUp();
  }

  bool _canEdit(Session session, Stroke note) =>
      session.drawsPublic == note.isPublic;

  Stroke? _topNote(Session session, NormPoint point) {
    final notes = <Stroke>[
      for (final stroke in session.publicStrokes)
        if (stroke.isNote && stroke.pageIndex == session.pageIndex) stroke,
      if (!session.drawsPublic)
        for (final stroke in session.privateStrokes)
          if (stroke.isNote && stroke.pageIndex == session.pageIndex) stroke,
    ];
    for (final note in notes.reversed) {
      if (noteContains(note, point)) return note;
    }
    return null;
  }

  List<Stroke> _visibleStrokes(Session session) {
    bool onPage(Stroke stroke) => stroke.pageIndex == session.pageIndex;
    final live = session.liveStroke;
    final remote = session.remoteLiveStroke;
    return [
      ...session.publicStrokes.where(onPage),
      if (!session.drawsPublic) ...session.privateStrokes.where(onPage),
      if (remote != null &&
          session.hostPresent &&
          onPage(remote) &&
          remote.id != live?.id &&
          !session.publicStrokes.any((stroke) => stroke.id == remote.id))
        remote,
      if (live != null && onPage(live)) live,
    ];
  }
}

class _PortraitDock extends ConsumerWidget {
  const _PortraitDock({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomy = isTablet(context);
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            roomy ? 28 : 8,
            roomy ? 14 : 6,
            roomy ? 28 : 8,
            roomy ? 12 : 4,
          ),
          child: roomy
              ? Row(
                  children: [
                    _PageButtons(session: session),
                    const Spacer(),
                    _ToolButtons(session: session, showLabels: true),
                    const Spacer(),
                    _ColorDots(session: session),
                    const SizedBox(width: 16),
                    _WidthDots(session: session),
                  ],
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        _PageButtons(session: session),
                        const Spacer(),
                        _ToolButtons(session: session),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _ColorDots(session: session),
                        const Spacer(),
                        _WidthDots(session: session),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SideRail extends ConsumerWidget {
  const _SideRail({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHost = session.role == MemberRole.host;
    return SafeArea(
      left: false,
      child: Container(
        width: isTablet(context) ? 120 : 88,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: Color(0xFFD6D0C8))),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Text(
              isHost ? '공용' : '개인',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _PageButtons(session: session, vertical: true),
            const Divider(height: 24),
            _ToolButtons(session: session, vertical: true),
            const Divider(height: 24),
            _ColorDots(session: session, vertical: true),
            const SizedBox(height: 12),
            _WidthDots(session: session, vertical: true),
          ],
        ),
      ),
    );
  }
}

class _PageButtons extends ConsumerWidget {
  const _PageButtons({required this.session, this.vertical = false});

  final Session session;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sessionProvider.notifier);
    final canTurn = !session.documentLoading;
    void turn(int index) => session.role == MemberRole.host
        ? notifier.goToPage(index)
        : notifier.browsePage(index);
    final previous = IconButton(
      tooltip: '이전 페이지',
      onPressed: canTurn && session.pageIndex > 0
          ? () => turn(session.pageIndex - 1)
          : null,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(vertical ? Icons.expand_less : Icons.chevron_left),
    );
    final next = IconButton(
      tooltip: '다음 페이지',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: canTurn && session.pageIndex < session.pageCount - 1
          ? () => turn(session.pageIndex + 1)
          : null,
      icon: Icon(vertical ? Icons.expand_more : Icons.chevron_right),
    );
    final canAdd =
        session.role == MemberRole.host &&
        session.openedOnThisDevice &&
        !session.classEnded;
    final buttons = [previous, next, if (canAdd) const _AddPagesButton()];
    if (vertical) {
      return Column(children: buttons);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }
}

class _AddPagesButton extends ConsumerStatefulWidget {
  const _AddPagesButton();

  @override
  ConsumerState<_AddPagesButton> createState() => _AddPagesButtonState();
}

class _AddPagesButtonState extends ConsumerState<_AddPagesButton> {
  var _busy = false;

  Future<void> _choose(_AddChoice choice) async {
    switch (choice) {
      case _AddChoice.blank:
        await _addBlank();
      case _AddChoice.photos:
        await _add(PageSource.photos);
      case _AddChoice.files:
        await _add(PageSource.files);
      case _AddChoice.delete:
        await _delete();
    }
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final page = (ref.read(sessionProvider)?.pageIndex ?? 0) + 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$page쪽을 삭제할까요?'),
        content: const Text(
          '이 페이지의 공용 판서도 함께 지워지고, 참여자들의 이 페이지 개인 노트도 사라집니다. 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const Key('confirm-delete-page'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final error = await ref.read(sessionProvider.notifier).deletePage();
      messenger.showSnackBar(
        SnackBar(content: Text(error ?? '$page쪽을 삭제했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBlank() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final error = await ref.read(sessionProvider.notifier).insertBlankPage();
      messenger.showSnackBar(
        SnackBar(content: Text(error ?? '이 페이지 뒤에 흰 페이지를 넣었습니다.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(PageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final picked = await pickPages(source);
      if (picked == null) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('페이지를 맨 뒤에 붙이는 중입니다.')),
      );
      final error = await ref
          .read(sessionProvider.notifier)
          .appendPages(picked.paths);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(error ?? '${picked.paths.length}개를 맨 뒤에 붙였습니다.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('파일을 읽지 못했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(
      sessionProvider.select((session) => session?.documentLoading ?? false),
    );
    final pageCount = ref.watch(
      sessionProvider.select((session) => session?.pageCount ?? 1),
    );
    if (_busy || loading) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopupMenuButton<_AddChoice>(
      key: const Key('add-pages'),
      tooltip: '페이지 관리',
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.auto_stories_outlined),
      onSelected: _choose,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _AddChoice.blank,
          child: Text('이 페이지 뒤에 흰 페이지'),
        ),
        const PopupMenuItem(
          value: _AddChoice.photos,
          child: Text('사진을 맨 뒤에 추가'),
        ),
        const PopupMenuItem(
          value: _AddChoice.files,
          child: Text('파일을 맨 뒤에 추가'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('delete-page'),
          value: _AddChoice.delete,
          enabled: pageCount > 1,
          child: Text(
            pageCount > 1 ? '이 페이지 삭제' : '이 페이지 삭제 (한 장뿐이라 불가)',
            style: TextStyle(
              color: pageCount > 1 ? Colors.red.shade700 : null,
            ),
          ),
        ),
      ],
    );
  }
}

enum _AddChoice { blank, photos, files, delete }

class _ToolButtons extends ConsumerWidget {
  const _ToolButtons({
    required this.session,
    this.vertical = false,
    this.showLabels = false,
  });

  final Session session;
  final bool vertical;
  final bool showLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sessionProvider.notifier);
    final buttons = [
      _ToolButton(
        tooltip: '펜',
        label: vertical || showLabels ? '펜' : null,
        selected: session.tool == CanvasTool.pen,
        icon: Icons.edit_outlined,
        onPressed: () => notifier.selectTool(CanvasTool.pen),
      ),
      _ToolButton(
        tooltip: '형광펜',
        label: vertical || showLabels ? '형광펜' : null,
        selected: session.tool == CanvasTool.highlighter,
        icon: Icons.highlight_outlined,
        onPressed: () => notifier.selectTool(CanvasTool.highlighter),
      ),
      _ToolButton(
        tooltip: '지우개',
        label: vertical || showLabels ? '지우개' : null,
        selected: session.tool == CanvasTool.eraser,
        icon: Icons.auto_fix_off_outlined,
        onPressed: () => notifier.selectTool(CanvasTool.eraser),
      ),
      _ToolButton(
        tooltip: '포스트잇',
        label: vertical || showLabels ? '포스트잇' : null,
        selected: session.tool == CanvasTool.note,
        icon: Icons.sticky_note_2_outlined,
        onPressed: () => notifier.selectTool(CanvasTool.note),
      ),
      if (session.role == MemberRole.host)
        _ToolButton(
          tooltip: '레이저',
          label: vertical || showLabels ? '레이저' : null,
          selected: session.tool == CanvasTool.laser,
          icon: Icons.gps_fixed,
          onPressed: () => notifier.selectTool(CanvasTool.laser),
        ),
      IconButton(
        tooltip: '실행 취소',
        onPressed: notifier.undo,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: const Icon(Icons.undo),
      ),
    ];
    if (vertical) {
      return Column(children: buttons);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }
}

class _ColorDots extends ConsumerWidget {
  const _ColorDots({required this.session, this.vertical = false});

  final Session session;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sessionProvider.notifier);
    final dots = [
      for (final color in inkPalette)
        Padding(
          padding: EdgeInsets.only(
            right: vertical ? 0 : 8,
            bottom: vertical ? 10 : 0,
          ),
          child: _ColorDot(
            color: Color(color),
            selected: session.colorArgb == color,
            onPressed: () => notifier.selectColor(color),
          ),
        ),
    ];
    if (vertical) return Column(children: dots);
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
}

class _WidthDots extends ConsumerWidget {
  const _WidthDots({required this.session, this.vertical = false});

  final Session session;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sessionProvider.notifier);
    final dots = [
      for (final width in const [2.0, 4.0, 8.0])
        Padding(
          padding: EdgeInsets.only(
            left: vertical ? 0 : 8,
            bottom: vertical ? 8 : 0,
          ),
          child: _WidthDot(
            width: width,
            selected: session.strokeWidthPx == width,
            onPressed: () => notifier.selectWidth(width),
          ),
        ),
    ];
    if (vertical) return Column(children: dots);
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
    this.label,
  });

  final String tooltip;
  final String? label;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: selected ? accent : ink);
    if (label == null) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        isSelected: selected,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: iconWidget,
      );
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(height: 2),
              Text(
                label!,
                style: TextStyle(fontSize: 11, color: selected ? accent : ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? accent : const Color(0xFFD6D0C8),
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  const _WidthDot({
    required this.width,
    required this.selected,
    required this.onPressed,
  });

  final double width;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? accent : const Color(0xFFD6D0C8),
          ),
        ),
        child: Container(
          width: width + 2,
          height: width + 2,
          decoration: const BoxDecoration(color: ink, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _HostMicButton extends ConsumerWidget {
  const _HostMicButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(radioProvider);
    final live = radio.micOn && radio.joined;
    return IconButton(
      key: const Key('radio-mic'),
      tooltip: radio.micOn ? '마이크 끄기' : '마이크 켜기',
      onPressed: () => ref.read(radioProvider.notifier).toggleMic(),
      icon: Icon(
        radio.micOn ? Icons.mic : Icons.mic_off,
        color: live ? const Color(0xFF15803D) : const Color(0xFF57534E),
      ),
    );
  }
}

class _ListenButton extends ConsumerWidget {
  const _ListenButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(radioProvider);
    return IconButton(
      key: const Key('radio-listen'),
      tooltip: radio.listening ? '발표자 음성 끄기' : '발표자 음성 켜기',
      onPressed: () => ref.read(radioProvider.notifier).toggleListen(),
      icon: Icon(
        radio.listening ? Icons.volume_up : Icons.volume_off,
        color: radio.joined && radio.listening
            ? const Color(0xFF15803D)
            : const Color(0xFF57534E),
      ),
    );
  }
}

Future<void> _askStickyNote(
  BuildContext context,
  WidgetRef ref,
  Offset local,
  Size size,
) async {
  final controller = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          ref.read(sessionProvider)?.drawsPublic == false ? '내 포스트잇' : '포스트잇',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '메모'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('붙이기'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (text == null) return;
  ref.read(sessionProvider.notifier).placeNote(local, size, text);
}
