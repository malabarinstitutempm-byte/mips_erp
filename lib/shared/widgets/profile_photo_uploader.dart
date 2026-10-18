import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image/image.dart' as img;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'image_cropper_dialog.dart';

class ProfilePhotoUploader extends StatefulWidget {
  final File? initialFile;
  final Uint8List? initialBytes;
  final String? initialPhotoPath;
  final ValueChanged<File?>? onPhotoChanged;
  final ValueChanged<Uint8List?>? onBytesChanged;

  const ProfilePhotoUploader({
    super.key,
    this.initialFile,
    this.initialBytes,
    this.initialPhotoPath,
    this.onPhotoChanged,
    this.onBytesChanged,
  });

  @override
  State<ProfilePhotoUploader> createState() => _ProfilePhotoUploaderState();
}

class _ProfilePhotoUploaderState extends State<ProfilePhotoUploader> {
  bool _isDragging = false;
  File? _currentFile;
  Uint8List? _currentBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.initialFile;
    _currentBytes = widget.initialBytes;
    if (_currentBytes == null && widget.initialPhotoPath != null) {
      if (widget.initialPhotoPath!.startsWith('data:image')) {
        try {
          _currentBytes = base64Decode(widget.initialPhotoPath!.split(',').last);
        } catch (_) {}
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pf = result.files.single;
        Uint8List? bytes = pf.bytes;
        File? file;
        if (!kIsWeb && pf.path != null) {
          try {
            file = File(pf.path!);
            if (bytes == null) {
              bytes = await file.readAsBytes();
            }
          } catch (_) {}
        }
        
        if (bytes != null) {
          await _processBytes(bytes, pf.name, file);
        } else {
          setState(() => _error = 'Could not read file data.');
        }
      }
    } catch (e) {
      setState(() => _error = 'Failed to pick file: $e');
    }
  }

  Future<void> _processBytes(Uint8List bytes, String fileName, File? file) async {
    setState(() => _error = null);
    
    // Check size limit (10MB)
    if (bytes.length > 10 * 1024 * 1024) {
      setState(() => _error = 'File too large (Max 10MB).');
      return;
    }

    // Check decode
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      setState(() => _error = 'Invalid image. Only JPG and PNG allowed.');
      return;
    }

    // Open cropper dialog
    if (mounted) {
      final cropped = await ImageCropperDialog.show(
        context,
        bytes: bytes,
        file: file,
        fileName: fileName,
      );
      if (cropped != null) {
        setState(() {
          _currentBytes = cropped.bytes;
          _currentFile = cropped.file;
          _error = null;
        });
        widget.onBytesChanged?.call(cropped.bytes);
        widget.onPhotoChanged?.call(cropped.file);
      }
    }
  }

  ImageProvider? _resolveImageProvider() {
    if (_currentBytes != null) {
      return MemoryImage(_currentBytes!);
    }
    if (!kIsWeb && _currentFile != null) {
      return FileImage(_currentFile!);
    }
    if (widget.initialPhotoPath != null) {
      if (widget.initialPhotoPath!.startsWith('data:image')) {
        try {
          return MemoryImage(base64Decode(widget.initialPhotoPath!.split(',').last));
        } catch (_) {}
      } else if (widget.initialPhotoPath!.startsWith('http://') || widget.initialPhotoPath!.startsWith('https://')) {
        return NetworkImage(widget.initialPhotoPath!);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = _resolveImageProvider();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (details) async {
            setState(() => _isDragging = false);
            if (details.files.isNotEmpty) {
              final xfile = details.files.first;
              final bytes = await xfile.readAsBytes();
              File? f;
              if (!kIsWeb) {
                f = File(xfile.path);
              }
              _processBytes(bytes, xfile.name, f);
            }
          },
          child: InkWell(
            onTap: _pickFile,
            borderRadius: BorderRadius.circular(AppTokens.radius10),
            child: Container(
              width: 132,
              height: 170,
              decoration: BoxDecoration(
                color: _isDragging ? AppColors.students.tint.withValues(alpha: 0.8) : AppColors.students.tint,
                borderRadius: BorderRadius.circular(AppTokens.radius10),
                border: Border.all(
                  color: _error != null 
                      ? AppColors.danger.base 
                      : _isDragging ? AppColors.students.base : AppColors.students.base.withValues(alpha: 0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
                image: imageProvider != null
                    ? DecorationImage(
                        image: imageProvider,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageProvider == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.camera, size: 28, color: AppColors.students.base),
                        const SizedBox(height: AppTokens.spacing8),
                        Text('Upload Photo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.students.dark)),
                        const SizedBox(height: 4),
                        Text('JPG / PNG', style: TextStyle(fontSize: 11, color: AppColors.students.base)),
                      ],
                    )
                  : null,
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: TextStyle(fontSize: 11, color: AppColors.danger.base), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if (imageProvider != null) ...[
          const SizedBox(height: AppTokens.spacing8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _pickFile,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Replace', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentFile = null;
                    _currentBytes = null;
                  });
                  widget.onBytesChanged?.call(null);
                  widget.onPhotoChanged?.call(null);
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger.base,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Remove', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
