import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/session.dart';
import 'lesson_renderer.dart';

class SavedLesson {
  const SavedLesson({
    required this.id,
    required this.title,
    required this.code,
    required this.fileName,
    required this.savedAt,
    required this.path,
  });

  final String id;
  final String title;
  final String code;
  final String fileName;
  final DateTime savedAt;
  final String path;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'code': code,
    'fileName': fileName,
    'savedAt': savedAt.toIso8601String(),
  };

  static SavedLesson? fromJson(Object? raw, String directoryPath) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final code = raw['code'];
    final fileName = raw['fileName'];
    final savedAt = raw['savedAt'];
    if (id is! String ||
        title is! String ||
        code is! String ||
        fileName is! String ||
        savedAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(savedAt);
    if (parsed == null || fileName.contains('/') || fileName.contains('..')) {
      return null;
    }
    return SavedLesson(
      id: id,
      title: title,
      code: code,
      fileName: fileName,
      savedAt: parsed,
      path: '$directoryPath/$fileName',
    );
  }
}

abstract class LessonArchive {
  Future<SavedLesson> export(Session session);

  Future<List<SavedLesson>> readAll();

  Future<void> remove(String id);
}

final lessonArchiveProvider = Provider<LessonArchive>(
  (ref) => FileLessonArchive(),
);

final lessonListProvider = NotifierProvider<LessonList, List<SavedLesson>>(
  LessonList.new,
);

class LessonList extends Notifier<List<SavedLesson>> {
  @override
  List<SavedLesson> build() {
    Future.microtask(refresh);
    return const [];
  }

  Future<void> refresh() async {
    final lessons = await ref.read(lessonArchiveProvider).readAll();
    if (!ref.mounted) return;
    state = lessons;
  }

  Future<void> dismiss(String id) async {
    await ref.read(lessonArchiveProvider).remove(id);
    await refresh();
  }
}

class FileLessonArchive implements LessonArchive {
  @override
  Future<SavedLesson> export(Session session) async {
    final pages = await renderLessonPages(session);
    if (pages.isEmpty) {
      throw const LessonExportException('기록으로 남길 페이지가 없습니다.');
    }
    final directory = await _directory();
    final savedAt = DateTime.now();
    final id = '${session.joinCode}-${savedAt.millisecondsSinceEpoch}';
    final fileName = '$id.pdf';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(await buildLessonPdf(pages), flush: true);
    final lesson = SavedLesson(
      id: id,
      title: session.title,
      code: session.joinCode,
      fileName: fileName,
      savedAt: savedAt,
      path: file.path,
    );
    try {
      await _writeIndex(directory, lesson);
    } catch (error) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return lesson;
  }

  @override
  Future<List<SavedLesson>> readAll() async {
    try {
      final directory = await _directory();
      final index = File('${directory.path}/index.json');
      if (!await index.exists()) return const [];
      final raw = jsonDecode(await index.readAsString());
      if (raw is! List) return const [];
      final lessons = <SavedLesson>[];
      for (final item in raw) {
        final lesson = SavedLesson.fromJson(item, directory.path);
        if (lesson == null) continue;
        if (!await File(lesson.path).exists()) continue;
        lessons.add(lesson);
      }
      lessons.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return lessons;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> remove(String id) async {
    final directory = await _directory();
    final lessons = await readAll();
    for (final lesson in lessons) {
      if (lesson.id != id) continue;
      final file = File(lesson.path);
      if (await file.exists()) await file.delete();
    }
    final remaining = [
      for (final lesson in lessons)
        if (lesson.id != id) lesson.toJson(),
    ];
    final index = File('${directory.path}/index.json');
    await index.writeAsString(jsonEncode(remaining), flush: true);
  }

  Future<void> _writeIndex(Directory directory, SavedLesson lesson) async {
    final existing = await readAll();
    final encoded = [lesson, ...existing].map((item) => item.toJson()).toList();
    final index = File('${directory.path}/index.json');
    await index.writeAsString(jsonEncode(encoded), flush: true);
  }

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/archives');
    await directory.create(recursive: true);
    return directory;
  }
}
