import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_semantic_colors.dart';
import 'app_tokens.dart';

/// Extra text styles that don't fit Material's TextTheme slots.
class AppText {
  AppText._();

  /// Big KPI numbers (26/700, tabular so digits align)
  static TextStyle kpiNumber = GoogleFonts.inter(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textStrong,
    height: 1.1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Money, marks, admission numbers in tables
  static TextStyle number = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textBody,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Small uppercase section labels (e.g. "PERSONAL INFORMATION")
  static TextStyle overline = GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: AppColors.textMuted,
  );
}

class AppTheme {
  AppTheme._();

  static const Color surface = AppColors.surface;
  static const Color background = AppColors.bg;
  static const Color primaryColor = AppColors.brand;
  static const Color border = AppColors.border;
  static const Color textPrimary = AppColors.textStrong;
  static const Color textSecondary = AppColors.textBody;
  static const Color textTertiary = AppColors.textMuted;
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF2563EB);
  static const Color warning = Color(0xFFD97706);


  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.brand,
      onPrimary: Colors.white,
      primaryContainer: AppColors.brandTint,
      onPrimaryContainer: AppColors.brandDark,
      surface: AppColors.surface,
      onSurface: AppColors.textStrong,
      onSurfaceVariant: AppColors.textMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: AppColors.danger.base,
      onError: Colors.white,
      errorContainer: AppColors.danger.tint,
      onErrorContainer: AppColors.danger.dark,
      surfaceTint: Colors.transparent,
    );

    final textTheme = _textTheme();

    final inputBorder = OutlineInputBorder(
      borderRadius: AppRadius.controlBr,
      borderSide: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      visualDensity: VisualDensity.compact,
      splashFactory: InkRipple.splashFactory,
      hoverColor: AppColors.brandTint.withValues(alpha: 0.6),
      highlightColor: Colors.transparent,
      dividerColor: AppColors.border,
      extensions: const <ThemeExtension<dynamic>>[
        AppSemanticColors.standard,
      ],

      // ---------- Cards ----------
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBr,
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ---------- Inputs ----------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(
            color: AppColors.brand, fontWeight: FontWeight.w600),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.danger.base),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.danger.base, width: 1.5),
        ),
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.danger.base),
      ),

      // ---------- Buttons ----------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBr),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBr),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textStrong,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBr),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBr),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textBody,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBr),
        ),
      ),

      // ---------- Dialogs, tooltips, snackbars ----------
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBr),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textStrong,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textStrong,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBr),
      ),

      // ---------- Tabs ----------
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.brand,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle:
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        indicatorColor: AppColors.brand,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.border,
        overlayColor:
            WidgetStatePropertyAll(AppColors.brandTint.withValues(alpha: 0.6)),
      ),

      // ---------- Selection controls ----------
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: AppColors.textMuted, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.brand : Colors.transparent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.brand
                : AppColors.border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      // ---------- Misc ----------
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
        linearTrackColor: AppColors.border,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
            AppColors.textMuted.withValues(alpha: 0.35)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlBr,
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: textTheme.bodyMedium,
      ),
    );
  }

  static TextTheme _textTheme() {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    return base.copyWith(
      // Page title
      headlineSmall: base.headlineSmall?.copyWith(
          fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textStrong),
      // Dialog / large section title
      titleLarge: base.titleLarge?.copyWith(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textStrong),
      // Section / card title
      titleMedium: base.titleMedium?.copyWith(
          fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textStrong),
      titleSmall: base.titleSmall?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textStrong),
      // Body
      bodyLarge: base.bodyLarge?.copyWith(
          fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textBody),
      bodyMedium: base.bodyMedium?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textBody),
      // Caption
      bodySmall: base.bodySmall?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted),
      // Buttons, table cells, badges
      labelLarge: base.labelLarge?.copyWith(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textStrong),
      labelMedium: base.labelMedium?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textBody),
      labelSmall: base.labelSmall?.copyWith(
          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
    );
  }
}
