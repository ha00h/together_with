import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'share_lesson.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key, required this.title, required this.path});

  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: '공유',
              onPressed: () =>
                  shareSavedLesson(context, path: path, title: title),
              icon: const Icon(Icons.ios_share),
            ),
          ),
        ],
      ),
      body: PdfViewer.file(path),
    );
  }
}
