import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../features/workspace/stroke_painter.dart';
import '../models/document_kind.dart';
import '../models/session.dart';
import '../models/stroke.dart';

class LessonPageImage {
  const LessonPageImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

class LessonExportException implements Exception {
  const LessonExportException(this.message);

  final String message;
}

const _renderWidth = 1240.0;

Future<List<LessonPageImage>> renderLessonPages(Session session) async {
  if (session.documentKind == DocumentKind.pdf) {
    return _renderPdf(session);
  }
  return [await _renderImage(session)];
}

Future<Uint8List> buildLessonPdf(List<LessonPageImage> pages) {
  final document = pw.Document();
  for (final page in pages) {
    final aspect = page.height / page.width;
    final pageWidth = 595.0;
    final pageHeight = pageWidth * aspect;
    final image = pw.MemoryImage(page.bytes);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
  }
  return document.save();
}

List<Stroke> inkForPage(Session session, int pageIndex) {
  final live = session.liveStroke;
  final remote = session.remoteLiveStroke;
  bool saved(Stroke stroke) => stroke.pageIndex == pageIndex && !stroke.isLaser;
  return [
    ...session.publicStrokes.where(saved),
    ...session.privateStrokes.where(saved),
    if (remote != null && saved(remote) && remote.id != live?.id) remote,
    if (live != null && saved(live)) live,
  ];
}

Future<List<LessonPageImage>> _renderPdf(Session session) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openFile(session.documentPath);
  try {
    final pages = <LessonPageImage>[];
    for (var index = 0; index < document.pages.length; index++) {
      final page = document.pages[index];
      final height = _renderWidth * page.height / page.width;
      final rendered = await page.render(
        fullWidth: _renderWidth,
        fullHeight: height,
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) {
        throw const LessonExportException('문서 페이지를 그리지 못했습니다.');
      }
      final image = await rendered.createImage();
      rendered.dispose();
      pages.add(
        await _composite(
          image,
          inkForPage(session, index),
          Size(_renderWidth, height),
        ),
      );
    }
    return pages;
  } finally {
    await document.dispose();
  }
}

Future<LessonPageImage> _renderImage(Session session) async {
  final bytes = await File(session.documentPath).readAsBytes();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: _renderWidth.round(),
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  return _composite(
    image,
    inkForPage(session, 0),
    Size(image.width.toDouble(), image.height.toDouble()),
  );
}

Future<LessonPageImage> _composite(
  ui.Image base,
  List<Stroke> strokes,
  Size size,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(base, Offset.zero, Paint());
  StrokePainter(strokes: strokes, expandNotes: true).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  base.dispose();
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final width = image.width;
  final height = image.height;
  image.dispose();
  if (data == null) {
    throw const LessonExportException('기록 이미지를 만들지 못했습니다.');
  }
  return LessonPageImage(
    bytes: data.buffer.asUint8List(),
    width: width,
    height: height,
  );
}
