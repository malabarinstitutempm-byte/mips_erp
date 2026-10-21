import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String>? onChanged;
  final int debounceMs;
  final int minChars;

  const SearchField({
    super.key,
    this.hint = 'Search...',
    this.onChanged,
    this.debounceMs = 400,
    this.minChars = 2,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _handleChanged(String value) {
    _debounceTimer?.cancel();

    // If query is cleared, fire immediately without delay
    if (value.trim().isEmpty) {
      widget.onChanged?.call('');
      return;
    }

    // Require minChars characters before querying
    if (value.trim().length < widget.minChars) {
      return;
    }

    // Debounce subsequent typing
    _debounceTimer = Timer(Duration(milliseconds: widget.debounceMs), () {
      widget.onChanged?.call(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              onChanged: _handleChanged,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                fillColor: Colors.transparent,
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
