import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

class FileStorageService {
  static const int maxPhotoSizeBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxRecordSizeBytes = 25 * 1024 * 1024; // 25 MB

  static Future<String> get appDataRoot async {
    if (kIsWeb) return '';
    try {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'MIPS_ERP_Database');
    } catch (_) {
      return '';
    }
  }

  static Future<Directory> get tempDir async {
    final root = await appDataRoot;
    final dir = Directory(p.join(root, 'temp'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> cleanTemp() async {
    try {
      final dir = await tempDir;
      if (await dir.exists()) {
        final items = dir.listSync();
        for (final item in items) {
          if (item is File) {
            await item.delete();
          } else if (item is Directory) {
            await item.delete(recursive: true);
          }
        }
      }
    } catch (e) {
      print('Failed to clean temp directory: $e');
    }
  }

  static Future<File> moveToTemp(File sourceFile, String newFilename) async {
    final dir = await tempDir;
    final tempFile = File(p.join(dir.path, newFilename));
    return await sourceFile.copy(tempFile.path);
  }

  static Future<String> getFileHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static Future<Directory> getStudentDir(int studentId) async {
    final root = await appDataRoot;
    final dir = Directory(p.join(root, 'student_files', 'student_$studentId'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves a profile photo file (original, display, or thumb) and returns its RELATIVE path
  static Future<String> saveProfilePhoto(int studentId, File tempFile, String name) async {
    final studentDir = await getStudentDir(studentId);
    final photoDir = Directory(p.join(studentDir.path, 'photo'));
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    
    final destination = File(p.join(photoDir.path, name));
    await tempFile.copy(destination.path);
    
    return p.join('student_files', 'student_$studentId', 'photo', name).replaceAll('\\', '/');
  }
  
  /// Saves a student record and returns its RELATIVE path
  static Future<String> saveStudentRecord(int studentId, File tempFile, String recordUuid, String extension) async {
    final studentDir = await getStudentDir(studentId);
    final recordsDir = Directory(p.join(studentDir.path, 'records'));
    if (!await recordsDir.exists()) {
      await recordsDir.create(recursive: true);
    }
    
    final filename = '$recordUuid.$extension';
    final destination = File(p.join(recordsDir.path, filename));
    await tempFile.copy(destination.path);
    
    return p.join('student_files', 'student_$studentId', 'records', filename).replaceAll('\\', '/');
  }

  /// Get the absolute path from a relative path
  static Future<String> getAbsolutePath(String relativePath) async {
    if (kIsWeb) return relativePath;
    try {
      final root = await appDataRoot;
      // Normalize path separators for the current OS
      final normalizedRelative = relativePath.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator);
      return p.join(root, normalizedRelative);
    } catch (_) {
      return relativePath;
    }
  }

  /// Delete a file using its relative path
  static Future<bool> deleteFile(String relativePath) async {
    try {
      final absPath = await getAbsolutePath(relativePath);
      final file = File(absPath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      print('Failed to delete file: $e');
    }
    return false;
  }
}
