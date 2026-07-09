import 'package:flutter/material.dart';

/// Breakpoints tuned for Gather's content-heavy, feed-style screens.
/// Values follow common Material/Web conventions rather than exact device
/// widths, since Flutter Web runs in a resizable browser window.
class Breakpoints {
  Breakpoints._();

  /// Below this: phone layout (bottom nav, full-width content).
  static const double tablet = 700;

  /// Below this: tablet layout (bottom nav kept, but content is capped
  /// and centered). At/above this: desktop layout (side nav rail).
  static const double desktop = 1000;

  static bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < tablet;
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= tablet && w < desktop;
  }
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktop;
}

/// Wraps feed/form content so it never stretches edge-to-edge on wide
/// screens. Centers a column capped at [maxWidth], with responsive
/// horizontal padding on narrower widths so content still breathes on
/// phones without an artificial cap kicking in too early.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 640,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < Breakpoints.tablet ? 0.0 : 16.0;

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: child,
      ),
    );
  }
}
