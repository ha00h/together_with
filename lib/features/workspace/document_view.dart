import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/document_kind.dart';

class DocumentView extends StatefulWidget {
  const DocumentView({
    super.key,
    required this.path,
    required this.kind,
    required this.pageIndex,
    required this.onReady,
    this.onBusy,
  });

  final String path;
  final DocumentKind kind;
  final int pageIndex;
  final void Function(int pageCount, double aspectRatio) onReady;
  final ValueChanged<bool>? onBusy;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  ui.Image? _image;
  PdfDocument? _document;
  var _loading = true;
  String? _error;
  var _generation = 0;
  var _renderGeneration = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(DocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.kind != widget.kind) {
      _open();
      return;
    }
    if (widget.kind == DocumentKind.pdf &&
        oldWidget.pageIndex != widget.pageIndex) {
      _renderCurrentPage();
    }
  }

  void _busy(bool busy) {
    final onBusy = widget.onBusy;
    if (onBusy == null) return;
    scheduleMicrotask(() => onBusy(busy));
  }

  @override
  void dispose() {
    _generation++;
    _renderGeneration++;
    _image?.dispose();
    final document = _document;
    _document = null;
    if (document != null) unawaited(document.dispose());
    super.dispose();
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _renderGeneration++;
    final previous = _image;
    _image = null;
    previous?.dispose();
    final document = _document;
    _document = null;
    if (document != null) unawaited(document.dispose());
    setState(() {
      _loading = true;
      _error = null;
    });
    _busy(true);
    try {
      if (widget.kind == DocumentKind.image) {
        await _openImage(generation);
      } else {
        await _openPdf(generation);
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '문서를 열지 못했습니다.';
      });
    } finally {
      if (generation == _generation) _busy(false);
    }
  }

  Future<void> _openImage(int generation) async {
    final bytes = await File(widget.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted || generation != _generation) {
      frame.image.dispose();
      return;
    }
    final image = frame.image;
    setState(() {
      _image = image;
      _loading = false;
    });
    widget.onReady(1, image.width / image.height);
  }

  Future<void> _openPdf(int generation) async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(widget.path);
    if (!mounted || generation != _generation) {
      await document.dispose();
      return;
    }
    _document = document;
    await _renderCurrentPage();
  }

  Future<void> _renderCurrentPage() async {
    final document = _document;
    if (document == null) return;
    final generation = ++_renderGeneration;
    _busy(true);
    try {
      var index = widget.pageIndex;
      if (index < 0) index = 0;
      if (index >= document.pages.length) index = document.pages.length - 1;
      final page = document.pages[index];
      final rendered = await page.render(
        fullWidth: page.width * 2,
        fullHeight: page.height * 2,
      );
      if (rendered == null) {
        throw StateError('PDF page render returned null');
      }
      final image = await rendered.createImage();
      rendered.dispose();
      if (!mounted || generation != _renderGeneration) {
        image.dispose();
        return;
      }
      final previous = _image;
      setState(() {
        _image = image;
        _loading = false;
      });
      previous?.dispose();
      widget.onReady(document.pages.length, page.width / page.height);
    } catch (_) {
      if (!mounted || generation != _renderGeneration) return;
      setState(() {
        _loading = false;
        _error = '문서를 열지 못했습니다.';
      });
    } finally {
      if (generation == _renderGeneration) _busy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final image = _image;
    if (_loading || image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RawImage(
      image: image,
      fit: BoxFit.fill,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
