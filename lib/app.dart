import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'theme/app_theme.dart';
import 'theme/form_factor.dart';

class TogetherApp extends StatelessWidget {
  const TogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '함께 보자',
      theme: buildAppTheme(),
      builder: (context, child) => _OrientationLock(child: child),
      home: const HomeScreen(),
    );
  }
}

class _OrientationLock extends StatefulWidget {
  const _OrientationLock({required this.child});

  final Widget? child;

  @override
  State<_OrientationLock> createState() => _OrientationLockState();
}

class _OrientationLockState extends State<_OrientationLock> {
  double? _appliedShortestSide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = View.of(context);
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    if (shortest == _appliedShortestSide) return;
    _appliedShortestSide = shortest;
    applyOrientationPolicy(shortest);
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
