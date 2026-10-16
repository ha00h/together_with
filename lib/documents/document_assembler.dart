import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../models/document_kind.dart';

class AssembledDocument {
  const AssembledDocument({
    required this.path,
    required this.pageCount,
    this.droppedPages = 0,
  });

  final String path;
  final int pageCount;
  final int droppedPages;
}

class DocumentAssemblyException implements Exception {
  const DocumentAssemblyException(this.message);

  final String message;
}

abstract class DocumentAssembler {
  Future<AssembledDocument> assemble(List<String> sources, {int? maxPages});

  Future<int> pageCountOf(String source);

  Future<AssembledDocument> blank(double aspectRatio);

  Future<AssembledDocument> insertBlank(
    String base, {
    required int at,
    required double aspectRatio,
  });

  Future<AssembledDocument> removePage(String base, {required int at});
}

final documentAssemblerProvider = Provider<DocumentAssembler>(
  (ref) => PdfDocumentAssembler(),
);

const _pageWidth = 595.0;
const _maxRasterEdge = 2400;

class PdfDocumentAssembler implements DocumentAssembler {
  @override
  Future<AssembledDocument> assemble(
    List<String> sources, {
    int? maxPages,
  }) async {
    if (sources.isEmpty) {
      throw const DocumentAssemblyException('합칠 페이지가 없습니다.');
    }
    var dropped = 0;
    final merged = await _merge((open) async {
      final pages = <PdfPage>[];
      for (final source in sources) {
        pages.addAll((await open(source)).pages);
      }
      if (maxPages == null || pages.length <= maxPages) return pages;
      dropped = pages.length - maxPages;
      return pages.take(maxPages).toList();
    });
    return AssembledDocument(
      path: merged.path,
      pageCount: merged.pageCount,
      droppedPages: dropped,
    );
  }

  @override
  Future<int> pageCountOf(String source) async {
    if (documentKindFromName(source) != DocumentKind.pdf) return 1;
    await pdfrxFlutterInitialize();
    try {
      final document = await PdfDocument.openFile(source);
      try {
        return document.pages.length;
      } finally {
        await document.dispose();
      }
    } catch (_) {
      throw const DocumentAssemblyException('문서를 읽지 못했습니다.');
    }
  }

  @override
  Future<AssembledDocument> blank(double aspectRatio) async {
    try {
      final file = await _newFile();
      await file.writeAsBytes(await _blankPdf(aspectRatio), flush: true);
      return AssembledDocument(path: file.path, pageCount: 1);
    } catch (_) {
      throw const DocumentAssemblyException('흰 페이지를 만들지 못했습니다.');
    }
  }

  @override
  Future<AssembledDocument> insertBlank(
    String base, {
    required int at,
    required double aspectRatio,
  }) {
    return _merge((open) async {
      final existing = (await open(base)).pages;
      final blank = await open.keep(
        await PdfDocument.openData(
          await _blankPdf(aspectRatio),
          sourceName: 'blank.pdf',
        ),
      );
      final index = at.clamp(0, existing.length);
      return [
        ...existing.take(index),
        ...blank.pages,
        ...existing.skip(index),
      ];
    });
  }

  @override
  Future<AssembledDocument> removePage(String base, {required int at}) {
    return _merge((open) async {
      final existing = (await open(base)).pages;
      if (existing.length < 2) {
        throw const DocumentAssemblyException('마지막 한 장은 삭제할 수 없습니다.');
      }
      final index = at.clamp(0, existing.length - 1);
      return [...existing.take(index), ...existing.skip(index + 1)];
    });
  }

  Future<AssembledDocument> _merge(
    Future<List<PdfPage>> Function(_Opener open) collect,
  ) async {
    await pdfrxFlutterInitialize();
    final opener = _Opener();
    try {
      final pages = await collect(opener);
      final merged = await opener.keep(
        await PdfDocument.createNew(sourceName: 'lesson.pdf'),
      );
      merged.pages = pages;
      final bytes = await merged.encodePdf();
      final file = await _newFile();
      await file.writeAsBytes(bytes, flush: true);
      return AssembledDocument(path: file.path, pageCount: pages.length);
    } on DocumentAssemblyException {
      rethrow;
    } catch (_) {
      throw const DocumentAssemblyException('페이지를 합치지 못했습니다.');
    } finally {
      await opener.disposeAll();
    }
  }
}

class _Opener {
  final _opened = <PdfDocument>[];

  Future<PdfDocument> call(String source) async {
    if (documentKindFromName(source) == DocumentKind.pdf) {
      return keep(await PdfDocument.openFile(source));
    }
    return keep(
      await PdfDocument.openData(
        await _imagePagePdf(source),
        sourceName: source,
      ),
    );
  }

  Future<PdfDocument> keep(PdfDocument document) async {
    _opened.add(document);
    return document;
  }

  Future<void> disposeAll() async {
    for (final document in _opened.reversed) {
      await document.dispose();
    }
  }
}

Future<File> _newFile() async {
  final support = await getApplicationSupportDirectory();
  final folder = Directory('${support.path}/session_docs');
  await folder.create(recursive: true);
  return File(
    '${folder.path}/${DateTime.now().microsecondsSinceEpoch}_lesson.pdf',
  );
}

Future<Uint8List> _blankPdf(double aspectRatio) {
  final aspect = aspectRatio > 0 ? aspectRatio : 1 / 1.4142;
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(_pageWidth, _pageWidth / aspect),
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.SizedBox.expand(),
    ),
  );
  return document.save();
}

Future<Uint8List> _imagePagePdf(String path) async {
  final bytes = await File(path).readAsBytes();
  final pw.ImageProvider image = _isJpeg(bytes)
      ? pw.MemoryImage(bytes)
      : await _rasterImage(bytes);
  final width = image.width ?? 1;
  final height = image.height ?? 1;
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(_pageWidth, _pageWidth * height / width),
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Image(image, fit: pw.BoxFit.fill),
    ),
  );
  return document.save();
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;

Future<pw.ImageProvider> _rasterImage(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final longEdge = descriptor.width > descriptor.height
      ? descriptor.width
      : descriptor.height;
  final scale = longEdge > _maxRasterEdge ? _maxRasterEdge / longEdge : 1.0;
  final codec = await descriptor.instantiateCodec(
    targetWidth: (descriptor.width * scale).round(),
    targetHeight: (descriptor.height * scale).round(),
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final width = image.width;
  final height = image.height;
  image.dispose();
  if (data == null) {
    throw const DocumentAssemblyException('이미지를 읽지 못했습니다.');
  }
  return pw.RawImage(
    bytes: data.buffer.asUint8List(),
    width: width,
    height: height,
  );
}
