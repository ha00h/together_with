import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../archive/archive_screen.dart';
import '../../archive/lesson_archive.dart';
import '../../archive/share_lesson.dart';
import '../../models/session.dart';
import '../../state/session_controller.dart';
import '../../sync/room_providers.dart';
import '../../theme/form_factor.dart';
import '../workspace/workspace_screen.dart';
import 'create_room_screen.dart';
import 'end_class_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _code = TextEditingController();
  String? _savedCode;
  var _joining = false;

  @override
  void initState() {
    super.initState();
    _loadSavedRoom();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadSavedRoom() async {
    final code = await ref.read(activeRoomStoreProvider).read();
    if (!mounted) return;
    setState(() {
      _savedCode = code == null || code.isEmpty ? null : code;
    });
  }

  void _openWorkspace() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WorkspaceScreen()));
  }

  Future<void> _join([String? code]) async {
    if (_joining) return;
    setState(() => _joining = true);
    final message = await ref
        .read(sessionProvider.notifier)
        .joinRoom(code ?? _code.text);
    if (!mounted) return;
    setState(() => _joining = false);
    if (message != null) {
      if (message == '없는 입장 코드입니다.') setState(() => _savedCode = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() => _savedCode = ref.read(sessionProvider)?.joinCode);
    _openWorkspace();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final lessons = ref.watch(lessonListProvider);
    ref.listen<Session?>(sessionProvider, (previous, next) {
      if (previous != null && next == null) _loadSavedRoom();
    });
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '함께 보자',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('발표자는 문서 위에 공용 판서를 하고, 참여자는 자기 노트만 적습니다.'),
      ],
    );
    final actions = <Widget>[
      if (session != null) ...[
        _OpenSessionCard(
          session: session,
          onHost: () {
            ref.read(sessionProvider.notifier).viewAs(MemberRole.host);
            _openWorkspace();
          },
          onParticipant: () {
            ref.read(sessionProvider.notifier).viewAs(MemberRole.participant);
            _openWorkspace();
          },
          onClose: () {
            final code = session.joinCode;
            final networked = session.networked;
            ref.read(sessionProvider.notifier).closeSession();
            if (!networked) return;
            setState(() => _savedCode = code);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('입장 코드 $code 로 다시 들어올 수 있습니다.')),
            );
          },
        ),
        const SizedBox(height: 28),
      ],
      if (_joining) const LinearProgressIndicator(),
      if (_joining) const SizedBox(height: 16),
      if (session == null && _savedCode != null) ...[
        OutlinedButton(
          onPressed: _joining ? null : () => _join(_savedCode),
          child: Text('코드 $_savedCode 이어하기'),
        ),
        const SizedBox(height: 12),
      ],
      FilledButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CreateRoomScreen()),
          );
        },
        child: const Text('발표자로 수업 열기'),
      ),
      const SizedBox(height: 28),
      Text('입장 코드', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: '6자리 코드'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: _joining ? null : () => _join(),
        child: Text(_joining ? '받는 중' : '입장하기'),
      ),
      if (lessons.isNotEmpty) ...[
        const SizedBox(height: 28),
        Text('지난 수업', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final lesson in lessons)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(lesson.title),
            subtitle: Text(
              '${lesson.code} · ${lesson.savedAt.toLocal().month}/${lesson.savedAt.toLocal().day}',
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ArchiveScreen(title: lesson.title, path: lesson.path),
                ),
              );
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (context) => IconButton(
                    tooltip: '공유',
                    onPressed: () => shareSavedLesson(
                      context,
                      path: lesson.path,
                      title: lesson.title,
                    ),
                    icon: const Icon(Icons.ios_share),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () =>
                      ref.read(lessonListProvider.notifier).dismiss(lesson.id),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
      ],
    ];

    if (isLandscape(context)) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Align(alignment: Alignment.centerLeft, child: intro),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(32),
                      children: actions,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final tablet = isTablet(context);
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tablet ? 560 : double.infinity,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                tablet ? 40 : 24,
                tablet ? 48 : 32,
                tablet ? 40 : 24,
                24,
              ),
              children: [intro, const SizedBox(height: 28), ...actions],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenSessionCard extends StatelessWidget {
  const _OpenSessionCard({
    required this.session,
    required this.onHost,
    required this.onParticipant,
    required this.onClose,
  });

  final Session session;
  final VoidCallback onHost;
  final VoidCallback onParticipant;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFD6D0C8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text('입장 코드 ${session.joinCode}'),
            if (session.classEnded && !session.openedOnThisDevice) ...[
              const SizedBox(height: 8),
              const Text(
                '발표자가 수업을 끝냈습니다. 기록 저장을 눌러 공용 판서와 내 노트를 남기세요.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 12),
            if (session.openedOnThisDevice)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onHost,
                      child: const Text('발표자'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onParticipant,
                      child: const Text('참여자'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onParticipant,
                  child: const Text('수업 이어보기'),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const EndClassButton(),
                  TextButton(onPressed: onClose, child: const Text('세션 닫기')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
