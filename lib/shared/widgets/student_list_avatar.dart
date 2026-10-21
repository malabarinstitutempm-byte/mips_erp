import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/file_storage_service.dart';
import '../../core/utils/image_transform_helper.dart';
import 'app_avatar.dart';

class StudentListAvatar extends StatelessWidget {
  final Student student;
  final double radius;

  const StudentListAvatar({
    super.key,
    required this.student,
    this.radius = 18, // 36px diameter
  });

  @override
  Widget build(BuildContext context) {
    final photo = student.profilePhotoThumbPath ?? student.profilePhotoPath;
    if (photo == null || photo.isEmpty) {
      return AppAvatar(name: student.name, radius: radius);
    }

    if (photo.startsWith('data:image')) {
      try {
        final bytes = base64Decode(photo.split(',').last);
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
          backgroundColor: AppColors.students.tint,
        );
      } catch (_) {
        return AppAvatar(name: student.name, radius: radius);
      }
    }

    if (photo.startsWith('http://') || photo.startsWith('https://')) {
      // O5 Optimization: Transform to width 96, WebP, quality 75
      final transformed = transformImageUrl(photo, width: 96, quality: 75);
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(transformed),
        backgroundColor: AppColors.students.tint,
      );
    }

    if (!kIsWeb) {
      return FutureBuilder<String>(
        future: FileStorageService.getAbsolutePath(photo),
        builder: (context, snapshot) {
          if (snapshot.hasData && File(snapshot.data!).existsSync()) {
            return CircleAvatar(
              radius: radius,
              backgroundImage: FileImage(File(snapshot.data!)),
              backgroundColor: AppColors.students.tint,
            );
          }
          return AppAvatar(name: student.name, radius: radius);
        },
      );
    }

    return AppAvatar(name: student.name, radius: radius);
  }
}
