import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/stroke.dart';
import 'stroke_codec.dart';

class PrivateNotes {
  const PrivateNotes({required this.strokes, required this.documentVersion});

  final List<Stroke> strokes;
  final int documentVersion;
}

abstract class PrivateStrokeStore {
  Future<void> save(
    String code,
    String uid,
    List<Stroke> strokes, {
    int documentVersion = 1,
  });

  Future<PrivateNotes> read(String code, String uid);
}

class MemoryPrivateStrokeStore implements PrivateStrokeStore {
  final _notes = <String, PrivateNotes>{};

  @override
  Future<void> save(
    String code,
    String uid,
    List<Stroke> strokes, {
    int documentVersion = 1,
  }) async {
    _notes['$code/$uid'] = PrivateNotes(
      strokes: List<Stroke>.of(strokes),
      documentVersion: documentVersion,
    );
  }

  @override
  Future<PrivateNotes> read(String code, String uid) async {
    return _notes['$code/$uid'] ??
        const PrivateNotes(strokes: [], documentVersion: 1);
  }
}

class FilePrivateStrokeStore implements PrivateStrokeStore {
  Future<File> _file(String code, String uid) async {
    final support = await getApplicationSupportDirectory();
    return File(
      '${support.path}/rooms/${_safe(code)}/private/${_safe(uid)}.json',
    );
  }

  @override
  Future<void> save(
    String code,
    String uid,
    List<Stroke> strokes, {
    int documentVersion = 1,
  }) async {
    try {
      final file = await _file(code, uid);
      await file.parent.create(recursive: true);
      final payload = {
        'version': documentVersion,
        'strokes': [for (final stroke in strokes) strokeToMap(stroke)],
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (error) {
      debugPrint('private stroke save failed: $error');
    }
  }

  @override
  Future<PrivateNotes> read(String code, String uid) async {
    const empty = PrivateNotes(strokes: [], documentVersion: 1);
    try {
      final file = await _file(code, uid);
      if (!await file.exists()) return empty;
      final raw = jsonDecode(await file.readAsString());
      var version = 1;
      Object? items = raw;
      if (raw is Map) {
        final saved = raw['version'];
        if (saved is num) version = saved.toInt();
        items = raw['strokes'];
      }
      if (items is! List) return empty;
      final strokes = <Stroke>[];
      for (final item in items) {
        final stroke = strokeFromRemote(item, isPublic: false);
        if (stroke != null) strokes.add(stroke);
      }
      return PrivateNotes(strokes: strokes, documentVersion: version);
    } catch (error) {
      debugPrint('private stroke read failed: $error');
      return empty;
    }
  }
}

String _safe(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return cleaned.isEmpty ? 'note' : cleaned;
}
