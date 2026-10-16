import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_with/models/document_kind.dart';
import 'package:together_with/models/session.dart';
import 'package:together_with/models/stroke.dart';
import 'package:together_with/state/session_controller.dart';

void main() {
  ProviderContainer container() {
    final result = ProviderContainer();
    addTearDown(result.dispose);
    return result;
  }

  void open(ProviderContainer box) {
    box
        .read(sessionProvider.notifier)
        .openAsHost(
          title: '수학',
          documentPath: '/tmp/lesson.pdf',
          documentKind: DocumentKind.pdf,
          pageCount: 3,
        );
  }

  void drawLine(SessionController notifier) {
    const size = Size(200, 280);
    notifier.pointerDown(const Offset(20, 30), size);
    notifier.pointerMove(const Offset(80, 90), size);
    notifier.pointerUp();
  }

  test('발표자 획은 공용이고 참여자 획은 개인이다', () {
    final box = container();
    final notifier = box.read(sessionProvider.notifier);
    open(box);
    drawLine(notifier);

    var session = box.read(sessionProvider)!;
    expect(session.publicStrokes, hasLength(1));
    expect(session.publicStrokes.single.isPublic, isTrue);
    expect(session.privateStrokes, isEmpty);
    expect(session.publicStrokes.single.points.first.x, closeTo(0.1, 0.001));

    notifier.viewAs(MemberRole.participant);
    drawLine(notifier);
    session = box.read(sessionProvider)!;
    expect(session.publicStrokes, hasLength(1));
    expect(session.privateStrokes, hasLength(1));
    expect(session.privateStrokes.single.isPublic, isFalse);
  });

  test('참여자는 페이지를 넘기지 못한다', () {
    final box = container();
    final notifier = box.read(sessionProvider.notifier);
    open(box);
    notifier.viewAs(MemberRole.participant);
    notifier.goToPage(2);
    expect(box.read(sessionProvider)!.pageIndex, 0);

    notifier.viewAs(MemberRole.host);
    notifier.goToPage(2);
    expect(box.read(sessionProvider)!.pageIndex, 2);
  });

  test('지우개는 지금 역할의 레이어만 지운다', () {
    final box = container();
    final notifier = box.read(sessionProvider.notifier);
    open(box);
    drawLine(notifier);
    notifier.viewAs(MemberRole.participant);
    drawLine(notifier);
    notifier.selectTool(CanvasTool.eraser);
    notifier.pointerDown(const Offset(20, 30), const Size(200, 280));

    var session = box.read(sessionProvider)!;
    expect(session.privateStrokes, isEmpty);
    expect(session.publicStrokes, hasLength(1));

    notifier.viewAs(MemberRole.host);
    notifier.selectTool(CanvasTool.eraser);
    notifier.pointerDown(const Offset(20, 30), const Size(200, 280));
    session = box.read(sessionProvider)!;
    expect(session.publicStrokes, isEmpty);
  });

  test('다른 페이지의 획은 지우개에 닿지 않는다', () {
    final box = container();
    final notifier = box.read(sessionProvider.notifier);
    open(box);
    drawLine(notifier);
    notifier.goToPage(1);
    notifier.selectTool(CanvasTool.eraser);
    notifier.pointerDown(const Offset(20, 30), const Size(200, 280));
    expect(box.read(sessionProvider)!.publicStrokes, hasLength(1));
  });
}
