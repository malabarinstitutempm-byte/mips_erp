import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Page content padding and max width
  static const double pagePadding = 24;
  static const double contentMaxWidth = 1440;
}

class AppRadius {
  AppRadius._();
  static const double card = 14;
  static const double control = 10; // inputs, buttons, icon tiles
  static const double pill = 999;

  static final BorderRadius cardBr = BorderRadius.circular(card);
  static final BorderRadius controlBr = BorderRadius.circular(control);
  static final BorderRadius pillBr = BorderRadius.circular(pill);
}

class AppShadows {
  AppShadows._();

  /// Resting card: almost flat
  static const List<BoxShadow> rest = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Hover lift
  static const List<BoxShadow> hover = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Dialogs / slide-overs
  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x290F172A), blurRadius: 40, offset: Offset(0, 16)),
  ];
}

class AppDurations {
  AppDurations._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Curve curve = Curves.easeOut;
}

class AppLayout {
  AppLayout._();
  static const double sidebarWidth = 232;
  static const double sidebarCollapsedWidth = 72;
  static const double collapseBreakpoint = 1280;
  static const double topBarHeight = 60;
  static const double tableRowHeight = 52;
  static const double tableHeaderHeight = 40;
}
class AppTokens {
  static const double spacing4 = AppSpacing.xs;
  static const double spacing8 = AppSpacing.sm;
  static const double spacing12 = AppSpacing.md;
  static const double spacing16 = AppSpacing.lg;
  static const double spacing20 = AppSpacing.xl;
  static const double spacing24 = AppSpacing.xl;
  static const double spacing32 = AppSpacing.xxl;
  static const double spacing48 = 48.0;
  static const double radius10 = AppRadius.control;
  static const double radius14 = AppRadius.card;
  static const double radius999 = AppRadius.pill;
  static const double layoutMaxWidth = AppSpacing.contentMaxWidth;
  static const Duration animFast = AppDurations.fast;
  static const Duration animNormal = AppDurations.normal;
}