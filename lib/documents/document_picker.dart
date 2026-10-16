import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

enum PageSource { files, photos }

class PickedPages {
  const PickedPages({required this.paths, required this.names});

  final List<String> paths;
  final List<String> names;
}

Future<PickedPages?> pickPages(PageSource source) async {
  final files = source == PageSource.photos
      ? await FilePicker.pickFiles(
          type: FileType.image,
          darwinOptions: const DarwinOptions(
            assetRepresentationMode: DarwinAssetRepresentationMode.compatible,
          ),
        )
      : await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
        );
  if (files.isEmpty) return null;
  final paths = <String>[];
  final names = <String>[];
  for (final file in files) {
    final saved = await _copyIntoAppDir(file);
    if (saved == null) continue;
    paths.add(saved);
    names.add(file.name);
  }
  if (paths.isEmpty) return null;
  return PickedPages(paths: paths, names: names);
}

Future<String?> _copyIntoAppDir(PlatformFile file) async {
  final dir = await getApplicationSupportDirectory();
  final folder = Directory('${dir.path}/session_docs');
  await folder.create(recursive: true);
  final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final dest = File(
    '${folder.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName',
  );
  final sourcePath = file.path;
  if (sourcePath != null) {
    return (await File(sourcePath).copy(dest.path)).path;
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return null;
  await dest.writeAsBytes(bytes, flush: true);
  return dest.path;
}
