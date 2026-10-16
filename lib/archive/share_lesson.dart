import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

String pdfShareName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
  final base = cleaned.isEmpty ? '수업 기록' : cleaned;
  return base.toLowerCase().endsWith('.pdf') ? base : '$base.pdf';
}

Future<void> shareSavedLesson(
  BuildContext context, {
  required String path,
  required String title,
}) async {
  if (!await File(path).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장된 기록을 찾지 못했습니다.')),
      );
    }
    return;
  }
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(path, mimeType: 'application/pdf', name: pdfShareName(title)),
        ],
        subject: title,
        sharePositionOrigin: origin,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기록을 보내지 못했습니다.')),
      );
    }
  }
}
