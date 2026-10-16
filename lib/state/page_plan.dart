import 'package:flutter_riverpod/flutter_riverpod.dart';

class PagePlan {
  const PagePlan({required this.maxPages});

  static const basic = PagePlan(maxPages: 10);

  final int maxPages;

  String get limitMessage => '한 수업은 최대 $maxPages쪽까지 쓸 수 있습니다.';
}

final pagePlanProvider = Provider<PagePlan>((ref) => PagePlan.basic);
