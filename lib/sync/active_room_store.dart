import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

abstract class ActiveRoomStore {
  Future<void> save(String code);

  Future<String?> read();

  Future<void> clear();
}

class MemoryActiveRoomStore implements ActiveRoomStore {
  String? code;

  @override
  Future<void> save(String code) async {
    this.code = code;
  }

  @override
  Future<String?> read() async => code;

  @override
  Future<void> clear() async {
    code = null;
  }
}

class FileActiveRoomStore implements ActiveRoomStore {
  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/active_room_code.txt');
  }

  @override
  Future<void> save(String code) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(code);
    } catch (error) {
      debugPrint('active room save failed: $error');
    }
  }

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final code = (await file.readAsString()).trim();
      if (code.isEmpty) return null;
      return code;
    } catch (error) {
      debugPrint('active room read failed: $error');
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('active room clear failed: $error');
    }
  }
}
