import 'package:flutter/material.dart';

/// A color with its three roles:
/// [base] icons, charts, progress fills
/// [tint] soft backgrounds (icon tiles, badges, panels)
/// [dark] text/icons placed on top of [tint] (passes contrast)
@immutable
class ColorSet {
  final Color base;
  final Color tint;
  final Color dark;
  const ColorSet({required this.base, required this.tint, required this.dark});

  static ColorSet lerp(ColorSet a, ColorSet b, double t) => ColorSet(
        base: Color.lerp(a.base, b.base, t)!,
        tint: Color.lerp(a.tint, b.tint, t)!,
        dark: Color.lerp(a.dark, b.dark, t)!,
      );
}

/// Raw palette. Screens should NOT read this directly for module/status
/// colors. Use `context.semantic` (see app_semantic_colors.dart) instead.
class AppColors {
  AppColors._();

  // ---- Neutrals (slate) ----
  static const Color bg = Color(0xFFF4F6FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE3E8F0);
  static const Color textStrong = Color(0xFF0F172A);
  static const Color textBody = Color(0xFF334155);
  static const Color textMuted = Color(0xFF64748B);

  // ---- Brand (replace brand with your exact MIPS blue) ----
  static const Color brand = Color(0xFF1D4ED8);
  static const Color brandDark = Color(0xFF1E3A8A);
  static const Color brandTint = Color(0xFFEAF0FF);

  // ---- Module colors (icon tiles, section accents, charts) ----
  static const ColorSet students = ColorSet(
      base: Color(0xFF0EA5E9), tint: Color(0xFFE0F2FE), dark: Color(0xFF075985));
  static const ColorSet fees = ColorSet(
      base: Color(0xFF10B981), tint: Color(0xFFD1FAE5), dark: Color(0xFF065F46));
  static const ColorSet exams = ColorSet(
      base: Color(0xFF6366F1), tint: Color(0xFFE0E7FF), dark: Color(0xFF3730A3));
  static const ColorSet documents = ColorSet(
      base: Color(0xFF14B8A6), tint: Color(0xFFCCFBF1), dark: Color(0xFF115E59));
  static const ColorSet courses = ColorSet(
      base: Color(0xFF8B5CF6), tint: Color(0xFFEDE9FE), dark: Color(0xFF5B21B6));
  static const ColorSet reports = ColorSet(
      base: Color(0xFFF97316), tint: Color(0xFFFFEDD5), dark: Color(0xFF9A3412));
  static const ColorSet settings = ColorSet(
      base: Color(0xFF64748B), tint: Color(0xFFF1F5F9), dark: Color(0xFF334155));

  // ---- Status colors (badges, progress, validation ONLY) ----
  static const ColorSet success = ColorSet(
      base: Color(0xFF16A34A), tint: Color(0xFFDCFCE7), dark: Color(0xFF166534));
  static const ColorSet warning = ColorSet(
      base: Color(0xFFD97706), tint: Color(0xFFFEF3C7), dark: Color(0xFF92400E));
  static const ColorSet danger = ColorSet(
      base: Color(0xFFDC2626), tint: Color(0xFFFEE2E2), dark: Color(0xFF991B1B));
  static const ColorSet info = ColorSet(
      base: Color(0xFF2563EB), tint: Color(0xFFDBEAFE), dark: Color(0xFF1E40AF));

  // ---- Avatar palette (initials background, picked by name hash) ----
  static const List<ColorSet> avatarPalette = [
    students, fees, exams, documents, courses, reports,
  ];
}
