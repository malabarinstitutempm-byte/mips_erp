import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color baseColor;
  final Color tintColor;
  final double size;

  IconTile({
    super.key,
    required this.icon,
    required this.baseColor,
    required this.tintColor,
    this.size = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tintColor,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.5,
          color: baseColor,
        ),
      ),
    );
  }
}
