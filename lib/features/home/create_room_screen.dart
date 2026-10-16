import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../documents/document_assembler.dart';
import '../../documents/document_picker.dart';
import '../../models/document_kind.dart';
import '../../state/page_plan.dart';
import '../../state/session_controller.dart';
import '../../sync/room_gateway.dart';
import '../../theme/form_factor.dart';
import '../workspace/workspace_screen.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _title = TextEditingController(text: '수업');
  PickedPages? _picked;
  var _blank = false;
  var _picking = false;
  var _uploading = false;
  var _radioOn = true;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDocument(PageSource source) async {
    setState(() => _picking = true);
    try {
      final picked = await pickPages(source);
      if (!mounted || picked == null) return;
      setState(() {
        _picked = picked;
        _blank = false;
      });
    } catch (_) {
      if (mounted) _show('파일을 저장하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _start() async {
    final picked = _picked;
    if ((picked == null && !_blank) || _uploading) return;
    final landscape = isLandscape(context);
    setState(() => _uploading = true);
    try {
      final assembler = ref.read(documentAssemblerProvider);
      final maxPages = ref.read(pagePlanProvider).maxPages;
      var path = picked?.paths.first ?? '';
      var name = picked?.names.first ?? 'lesson.pdf';
      var kind = documentKindFromName(name) ?? DocumentKind.image;
      var dropped = 0;
      if (picked == null) {
        path = (await assembler.blank(landscape ? 1.4142 : 1 / 1.4142)).path;
        kind = DocumentKind.pdf;
      } else if (picked.paths.length > 1 ||
          documentKindFromName(picked.names.first) == null ||
          await assembler.pageCountOf(path) > maxPages) {
        final merged = await assembler.assemble(
          picked.paths,
          maxPages: maxPages,
        );
        path = merged.path;
        name = 'lesson.pdf';
        kind = DocumentKind.pdf;
        dropped = merged.droppedPages;
      }
      if (dropped > 0 && !await _confirmTrim(maxPages, dropped)) return;
      if (!mounted) return;
      await ref
          .read(sessionProvider.notifier)
          .startRoom(
            title: _title.text,
            documentPath: path,
            fileName: name,
            documentKind: kind,
            radioOn: _radioOn,
          );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const WorkspaceScreen()),
      );
    } on DocumentAssemblyException catch (error) {
      if (mounted) _show(error.message);
    } on RoomSyncException catch (error) {
      if (mounted) _show(error.message);
    } catch (_) {
      if (mounted) _show('수업을 열지 못했습니다. 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool> _confirmTrim(int maxPages, int dropped) async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('앞 $maxPages쪽만 사용합니다'),
        content: Text(
          '고른 문서는 모두 ${maxPages + dropped}쪽입니다. '
          '한 수업은 최대 $maxPages쪽까지 쓸 수 있어 뒤쪽 $dropped쪽은 빠집니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('다시 고르기'),
          ),
          FilledButton(
            key: const Key('confirm-trim'),
            onPressed: () => Navigator.pop(context, true),
            child: Text('앞 $maxPages쪽으로 시작'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _pickedLabel {
    final picked = _picked;
    if (_blank) return '흰 화이트보드 한 장으로 시작합니다.';
    if (picked == null) return '아직 고른 문서가 없습니다.';
    if (picked.names.length == 1) return picked.names.first;
    return '${picked.names.length}개를 고른 순서대로 한 문서로 묶습니다.';
  }

  @override
  Widget build(BuildContext context) {
    final busy = _picking || _uploading;
    final ready = (_picked != null || _blank) && !busy;
    return Scaffold(
      appBar: AppBar(title: const Text('수업 열기')),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isTablet(context) || isLandscape(context)
                      ? 560
                      : double.infinity,
                ),
                child: ListView(
                  padding: EdgeInsets.all(
                    isTablet(context) || isLandscape(context) ? 40 : 24,
                  ),
                  children: [
                    const Text('발표자 화면에서 문서를 열고 공용 판서를 시작합니다.'),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: '방 제목'),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('라디오'),
                      subtitle: Text(
                        _radioOn
                            ? '참여자가 발표자 목소리를 듣습니다. 마이크는 꺼진 채로 시작합니다.'
                            : '이 수업에는 음성을 연결하지 않습니다.',
                      ),
                      value: _radioOn,
                      onChanged: busy
                          ? null
                          : (value) => setState(() => _radioOn = value),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _pickDocument(PageSource.files),
                            icon: const Icon(Icons.upload_file),
                            label: const Text('파일'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _pickDocument(PageSource.photos),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('사진'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('start-blank'),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              _blank = true;
                              _picked = null;
                            }),
                      icon: const Icon(Icons.crop_portrait),
                      label: const Text('문서 없이 흰 페이지로 시작'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _pickedLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF57534E),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: ready ? _start : null,
                      child: Text(_uploading ? '올리는 중' : '세션 시작'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
