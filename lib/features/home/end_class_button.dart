import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/session_controller.dart';

class EndClassButton extends ConsumerStatefulWidget {
  const EndClassButton({super.key, this.popOnSuccess = false});

  final bool popOnSuccess;

  @override
  ConsumerState<EndClassButton> createState() => _EndClassButtonState();
}

class _EndClassButtonState extends ConsumerState<EndClassButton> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final host = session.openedOnThisDevice;
    final label = host ? '수업 끝내기' : '기록 저장';
    return TextButton(
      key: const Key('end-class'),
      onPressed: _busy ? null : () => _end(host),
      child: Text(_busy ? '저장 중' : label),
    );
  }

  Future<void> _end(bool host) async {
    setState(() => _busy = true);
    final result = await ref.read(sessionProvider.notifier).endClass();
    if (!mounted) return;
    setState(() => _busy = false);
    final message =
        result.message ??
        (result.removedServer
            ? '수업 기록을 저장하고 서버에서 지웠습니다.'
            : host
            ? '수업 기록을 이 기기에 저장했습니다.'
            : '공용 판서와 내 노트를 이 기기에 저장했습니다.');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (result.ok && widget.popOnSuccess && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
