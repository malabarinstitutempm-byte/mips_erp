import 'package:flutter/material.dart';

/// Central responsive helper for MIPS ERP Admin application.
/// 
/// Breakpoints:
/// - Phone: width < 600
/// - Tablet: 600 <= width <= 1024
/// - Desktop: width > 1024
class Responsive {
  static const double phoneBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;

  static bool isPhone(BuildContext context) =>
      MediaQuery.of(context).size.width < phoneBreakpoint;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= phoneBreakpoint && width <= tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width > tabletBreakpoint;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < phoneBreakpoint;

  static bool isMobileOrTablet(BuildContext context) =>
      MediaQuery.of(context).size.width <= tabletBreakpoint;

  /// Returns value based on current device form factor.
  static T value<T>(
    BuildContext context, {
    required T phone,
    T? tablet,
    required T desktop,
  }) {
    if (isPhone(context)) return phone;
    if (isTablet(context)) return tablet ?? desktop;
    return desktop;
  }
}

/// Adaptive layout builder widget.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, BoxConstraints constraints) phone;
  final Widget Function(BuildContext context, BoxConstraints constraints)? tablet;
  final Widget Function(BuildContext context, BoxConstraints constraints) desktop;

  const ResponsiveBuilder({
    super.key,
    required this.phone,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Responsive.phoneBreakpoint) {
          return phone(context, constraints);
        } else if (constraints.maxWidth <= Responsive.tabletBreakpoint) {
          return (tablet ?? desktop)(context, constraints);
        } else {
          return desktop(context, constraints);
        }
      },
    );
  }
}
