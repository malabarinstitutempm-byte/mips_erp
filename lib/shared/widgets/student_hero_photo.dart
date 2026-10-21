import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/services/file_storage_service.dart';
import '../../core/utils/image_transform_helper.dart';

class StudentHeroPhoto extends StatelessWidget {
  final Student student;
  final VoidCallback? onChangePhoto;

  const StudentHeroPhoto({
    super.key,
    required this.student,
    this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 88,
          height: 112,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            color: AppColors.students.tint,
            border: Border.all(color: AppColors.border),
          ),
          child: _buildPhotoWidget(),
        ),
        if (onChangePhoto != null)
          Positioned(
            right: -6,
            bottom: -6,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                onTap: onChangePhoto,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    LucideIcons.camera,
                    size: 14,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPhotoWidget() {
    final photo = student.profilePhotoPath;
    if (photo == null || photo.isEmpty) {
      return _buildFallback();
    }

    if (photo.startsWith('data:image')) {
      try {
        final bytes = base64Decode(photo.split(',').last);
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Image.memory(
            bytes,
            key: ValueKey(student.profilePhotoUpdatedAt),
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        return _buildFallback();
      }
    }

    if (photo.startsWith('http://') || photo.startsWith('https://')) {
      // O5 Optimization: Transform to width 384, WebP, quality 75
      final transformed = transformImageUrl(photo, width: 384, quality: 75);
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Image.network(
          transformed,
          key: ValueKey(student.profilePhotoUpdatedAt),
          fit: BoxFit.cover,
        ),
      );
    }

    if (!kIsWeb) {
      return FutureBuilder<String>(
        future: FileStorageService.getAbsolutePath(photo),
        builder: (context, snapshot) {
          if (snapshot.hasData && File(snapshot.data!).existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Image.file(
                File(snapshot.data!),
                key: ValueKey(student.profilePhotoUpdatedAt),
                fit: BoxFit.cover,
              ),
            );
          }
          return _buildFallback();
        },
      );
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.user,
            size: 32,
            color: AppColors.students.base.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'NO PHOTO',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: AppColors.students.base.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
