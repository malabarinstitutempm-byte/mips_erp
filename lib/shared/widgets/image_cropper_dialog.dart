import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class CroppedImageResult {
  final Uint8List bytes;
  final File? file;

  const CroppedImageResult({
    required this.bytes,
    this.file,
  });
}

class ImageCropperDialog extends StatefulWidget {
  final Uint8List bytes;
  final File? file;
  final String? fileName;

  const ImageCropperDialog({
    super.key,
    required this.bytes,
    this.file,
    this.fileName,
  });

  static Future<CroppedImageResult?> show(
    BuildContext context, {
    required Uint8List bytes,
    File? file,
    String? fileName,
  }) {
    return showDialog<CroppedImageResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImageCropperDialog(
        bytes: bytes,
        file: file,
        fileName: fileName,
      ),
    );
  }

  @override
  State<ImageCropperDialog> createState() => _ImageCropperDialogState();
}

class _ImageCropperDialogState extends State<ImageCropperDialog> {
  img.Image? _decodedImage;
  Uint8List? _bakedBytes;
  bool _isLoading = true;
  String? _error;

  // Zoom & Pan state
  static const double _minZoom = 0.5;
  static const double _maxZoom = 4.0;
  static const double _zoomStep = 0.25;

  double _zoom = 1.0;
  Offset _offset = Offset.zero;
  int _quarterTurns = 0; // 0 = 0 deg, 1 = 90 deg CW, 2 = 180 deg, 3 = 270 deg CW
  double _cropRatio = 7 / 9; // Default ID Card portrait (7:9)

  bool _isDragging = false;
  Offset _startingFocalPoint = Offset.zero;
  Offset _startingOffset = Offset.zero;
  double _startingZoom = 1.0;

  // Layout cache for crop coordinate calculation
  Rect? _currentCropRect;
  double? _currentDispW;
  double? _currentDispH;
  double? _currentScale;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final decoded = img.decodeImage(widget.bytes);

      if (decoded == null) {
        setState(() {
          _error = 'Failed to decode image. Please use a valid JPG or PNG.';
          _isLoading = false;
        });
        return;
      }

      // Auto-rotate based on EXIF metadata so orientations match Flutter
      final baked = img.bakeOrientation(decoded);
      final bakedBytes = Uint8List.fromList(img.encodeJpg(baked, quality: 90));

      if (mounted) {
        setState(() {
          _decodedImage = baked;
          _bakedBytes = bakedBytes;
          _isLoading = false;
          _resetTransforms();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading image: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _resetTransforms() {
    setState(() {
      _zoom = 1.0;
      _offset = Offset.zero;
      _quarterTurns = 0;
    });
  }

  void _zoomIn() {
    setState(() {
      _zoom = (_zoom + _zoomStep).clamp(_minZoom, _maxZoom);
      _offset = _clampOffset(_offset);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = (_zoom - _zoomStep).clamp(_minZoom, _maxZoom);
      _offset = _clampOffset(_offset);
    });
  }

  void _rotateLeft() {
    setState(() {
      _quarterTurns = (_quarterTurns + 3) % 4; // -90 deg
      _offset = Offset.zero;
    });
  }

  void _rotateRight() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4; // +90 deg
      _offset = Offset.zero;
    });
  }

  void _setAspectRatio(double ratio) {
    setState(() {
      _cropRatio = ratio;
      _offset = Offset.zero;
    });
  }

  Offset _clampOffset(Offset offset) {
    if (_currentCropRect == null || _currentDispW == null || _currentDispH == null) {
      return offset;
    }
    // Allow panning so that user has generous freedom to position faces
    final maxDx = (_currentDispW! / 2) + (_currentCropRect!.width * 0.4);
    final maxDy = (_currentDispH! / 2) + (_currentCropRect!.height * 0.4);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx),
      offset.dy.clamp(-maxDy, maxDy),
    );
  }

  Rect _calculateCropRect(Size viewportSize, double cropRatio) {
    final w = viewportSize.width;
    final h = viewportSize.height;
    if (w <= 0 || h <= 0) return Rect.zero;

    // Margin padding inside viewport
    const padding = 20.0;
    final maxW = math.max(60.0, w - padding * 2);
    final maxH = math.max(60.0, h - padding * 2);

    double cw, ch;
    if (maxW / maxH > cropRatio) {
      ch = maxH;
      cw = ch * cropRatio;
    } else {
      cw = maxW;
      ch = cw / cropRatio;
    }

    return Rect.fromCenter(
      center: Offset(w / 2, h / 2),
      width: cw,
      height: ch,
    );
  }

  Future<void> _cropAndSave() async {
    if (_decodedImage == null || _currentCropRect == null || _currentScale == null) return;
    setState(() => _isLoading = true);

    try {
      // 1. Prepare target canvas
      const targetW = 600;
      final targetH = (600 / _cropRatio).round();
      final targetCanvas = img.Image(width: targetW, height: targetH);
      img.fill(targetCanvas, color: img.ColorRgb8(255, 255, 255)); // Crisp white backdrop

      // 2. Rotate image if quarter turns were applied
      img.Image workingImage = _decodedImage!;
      final turns = _quarterTurns % 4;
      if (turns == 1) {
        workingImage = img.copyRotate(_decodedImage!, angle: 90);
      } else if (turns == 2) {
        workingImage = img.copyRotate(_decodedImage!, angle: 180);
      } else if (turns == 3) {
        workingImage = img.copyRotate(_decodedImage!, angle: 270);
      }

      // 3. Compute crop bounds in workingImage pixel coordinates
      final cw = _currentCropRect!.width;
      final ch = _currentCropRect!.height;
      final dispW = _currentDispW!;
      final dispH = _currentDispH!;
      final scale = _currentScale!;

      final dx = (dispW - cw) / 2 - _offset.dx;
      final dy = (dispH - ch) / 2 - _offset.dy;

      final srcX = dx / scale;
      final srcY = dy / scale;
      final srcW = cw / scale;
      final srcH = ch / scale;

      // 4. Find valid intersection with workingImage boundaries
      final x1 = math.max(0.0, srcX);
      final y1 = math.max(0.0, srcY);
      final x2 = math.min(workingImage.width.toDouble(), srcX + srcW);
      final y2 = math.min(workingImage.height.toDouble(), srcY + srcH);

      if (x2 > x1 && y2 > y1) {
        final cropX = x1.floor();
        final cropY = y1.floor();
        final cropW = (x2.ceil() - cropX).clamp(1, workingImage.width - cropX);
        final cropH = (y2.ceil() - cropY).clamp(1, workingImage.height - cropY);

        final subCrop = img.copyCrop(
          workingImage,
          x: cropX,
          y: cropY,
          width: cropW,
          height: cropH,
        );

        // Map subCrop onto target canvas
        final scaleToTarget = targetW / srcW;
        final dstX = ((cropX - srcX) * scaleToTarget).round().clamp(0, targetW - 1);
        final dstY = ((cropY - srcY) * scaleToTarget).round().clamp(0, targetH - 1);
        final dstW = (cropW * scaleToTarget).round().clamp(1, targetW - dstX);
        final dstH = (cropH * scaleToTarget).round().clamp(1, targetH - dstY);

        final resizedSub = img.copyResize(
          subCrop,
          width: dstW,
          height: dstH,
          interpolation: img.Interpolation.linear,
        );

        img.compositeImage(
          targetCanvas,
          resizedSub,
          dstX: dstX,
          dstY: dstY,
        );
      }

      final croppedBytes = Uint8List.fromList(img.encodeJpg(targetCanvas, quality: 92));

      File? newFile;
      if (!kIsWeb && widget.file != null) {
        try {
          final fname = widget.fileName ?? widget.file!.path.split(RegExp(r'[\\/]')).last;
          newFile = File('${widget.file!.parent.path}/cropped_$fname');
          await newFile.writeAsBytes(croppedBytes);
        } catch (_) {}
      }

      if (mounted) {
        Navigator.pop(context, CroppedImageResult(bytes: croppedBytes, file: newFile));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Crop failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radius14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: math.min(720.0, MediaQuery.sizeOf(context).height * 0.92),
          minWidth: 320,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spacing20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.brandTint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(LucideIcons.crop, size: 18, color: AppColors.brand),
                      ),
                      const SizedBox(width: AppTokens.spacing8),
                      const Text(
                        'Crop & Adjust Photo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textStrong,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                    color: AppColors.textMuted,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spacing12),

              // Aspect Ratio Selector Chips
              Row(
                children: [
                  const Text(
                    'Format:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spacing8),
                  ChoiceChip(
                    label: const Text('7:9 ID Portrait', style: TextStyle(fontSize: 11)),
                    selected: (_cropRatio - (7 / 9)).abs() < 0.01,
                    selectedColor: AppColors.brandTint,
                    labelStyle: TextStyle(
                      color: (_cropRatio - (7 / 9)).abs() < 0.01 ? AppColors.brand : AppColors.textBody,
                      fontWeight: (_cropRatio - (7 / 9)).abs() < 0.01 ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      if (selected) _setAspectRatio(7 / 9);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: AppTokens.spacing8),
                  ChoiceChip(
                    label: const Text('1:1 Square', style: TextStyle(fontSize: 11)),
                    selected: (_cropRatio - 1.0).abs() < 0.01,
                    selectedColor: AppColors.brandTint,
                    labelStyle: TextStyle(
                      color: (_cropRatio - 1.0).abs() < 0.01 ? AppColors.brand : AppColors.textBody,
                      fontWeight: (_cropRatio - 1.0).abs() < 0.01 ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      if (selected) _setAspectRatio(1.0);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const Spacer(),
                  const Flexible(
                    child: Text(
                      'Drag · Scroll to zoom',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spacing12),

              // Viewport Area
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radius10),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(AppTokens.spacing16),
                                child: Text(_error!, style: TextStyle(color: AppColors.danger.base)),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
                                final cropRect = _calculateCropRect(viewportSize, _cropRatio);

                                // Compute image geometry
                                final origW = _decodedImage!.width.toDouble();
                                final origH = _decodedImage!.height.toDouble();
                                final isQuarterTurn = (_quarterTurns % 2 == 1);
                                final rotW = isQuarterTurn ? origH : origW;
                                final rotH = isQuarterTurn ? origW : origH;

                                final s0 = math.max(cropRect.width / rotW, cropRect.height / rotH);
                                final scale = s0 * _zoom;
                                final dispW = rotW * scale;
                                final dispH = rotH * scale;

                                // Update state caches for crop computation
                                _currentCropRect = cropRect;
                                _currentDispW = dispW;
                                _currentDispH = dispH;
                                _currentScale = scale;

                                return MouseRegion(
                                  cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                                  child: Listener(
                                    onPointerSignal: (pointerSignal) {
                                      if (pointerSignal is PointerScrollEvent) {
                                        setState(() {
                                          final double delta = -pointerSignal.scrollDelta.dy / 500.0;
                                          _zoom = (_zoom + delta).clamp(_minZoom, _maxZoom);
                                          _offset = _clampOffset(_offset);
                                        });
                                      }
                                    },
                                    child: GestureDetector(
                                      onScaleStart: (details) {
                                        setState(() => _isDragging = true);
                                        _startingFocalPoint = details.focalPoint;
                                        _startingOffset = _offset;
                                        _startingZoom = _zoom;
                                      },
                                      onScaleUpdate: (details) {
                                        setState(() {
                                          if (details.scale != 1.0) {
                                            _zoom = (_startingZoom * details.scale).clamp(_minZoom, _maxZoom);
                                          }
                                          final proposed = _startingOffset + (details.focalPoint - _startingFocalPoint);
                                          _offset = _clampOffset(proposed);
                                        });
                                      },
                                      onScaleEnd: (_) => setState(() => _isDragging = false),
                                      child: Stack(
                                        clipBehavior: Clip.hardEdge,
                                        alignment: Alignment.center,
                                        children: [
                                          // Neutral canvas backdrop
                                          Container(color: const Color(0xFF1E222B)),

                                          // Rotated & Panned Image
                                          Transform.translate(
                                            offset: _offset,
                                            child: SizedBox(
                                              width: dispW,
                                              height: dispH,
                                              child: RotatedBox(
                                                quarterTurns: _quarterTurns,
                                                child: Image.memory(
                                                  _bakedBytes!,
                                                  fit: BoxFit.fill,
                                                  filterQuality: FilterQuality.medium,
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Crop frame with cutout, border & rule-of-thirds grid
                                          CustomPaint(
                                            size: viewportSize,
                                            painter: _CropPainter(
                                              cropRect: cropRect,
                                              borderColor: Colors.white,
                                              overlayColor: Colors.black.withValues(alpha: 0.65),
                                              showGrid: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ),
              const SizedBox(height: AppTokens.spacing12),

              // Zoom & Rotation Toolbar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.spacing12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(AppTokens.radius10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    // Zoom Out
                    Tooltip(
                      message: 'Zoom Out (-25%)',
                      child: IconButton(
                        icon: const Icon(LucideIcons.zoomOut, size: 18),
                        onPressed: _zoom > _minZoom ? _zoomOut : null,
                        color: AppColors.textBody,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                      ),
                    ),

                    // Zoom Slider
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: AppColors.brand,
                          inactiveTrackColor: AppColors.border,
                          thumbColor: AppColors.brand,
                        ),
                        child: Slider(
                          value: _zoom.clamp(_minZoom, _maxZoom),
                          min: _minZoom,
                          max: _maxZoom,
                          onChanged: (val) {
                            setState(() {
                              _zoom = val;
                              _offset = _clampOffset(_offset);
                            });
                          },
                        ),
                      ),
                    ),

                    // Zoom In
                    Tooltip(
                      message: 'Zoom In (+25%)',
                      child: IconButton(
                        icon: const Icon(LucideIcons.zoomIn, size: 18),
                        onPressed: _zoom < _maxZoom ? _zoomIn : null,
                        color: AppColors.textBody,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                      ),
                    ),
                    const SizedBox(width: AppTokens.spacing4),

                    // Zoom Percentage Badge
                    Container(
                      constraints: const BoxConstraints(minWidth: 46),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${(_zoom * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textStrong,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spacing8),

                    Container(width: 1, height: 22, color: AppColors.border),
                    const SizedBox(width: AppTokens.spacing8),

                    // Rotate Left (CCW)
                    Tooltip(
                      message: 'Rotate Left 90°',
                      child: IconButton(
                        icon: const Icon(LucideIcons.rotateCcw, size: 17),
                        onPressed: _rotateLeft,
                        color: AppColors.textBody,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                      ),
                    ),

                    // Rotate Right (CW)
                    Tooltip(
                      message: 'Rotate Right 90°',
                      child: IconButton(
                        icon: const Icon(LucideIcons.rotateCw, size: 17),
                        onPressed: _rotateRight,
                        color: AppColors.textBody,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                      ),
                    ),
                    const SizedBox(width: AppTokens.spacing4),

                    // Reset
                    Tooltip(
                      message: 'Reset Zoom & Position',
                      child: IconButton(
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        onPressed: _resetTransforms,
                        color: AppColors.textMuted,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spacing16),

              // Dialog Footer / Actions
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: AppTokens.spacing8,
                children: [
                  Text(
                    '${_cropRatio == 1.0 ? "Square 1:1" : "ID Portrait 7:9"} · Export 600px',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spacing16, vertical: AppTokens.spacing12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.textBody)),
                      ),
                      const SizedBox(width: AppTokens.spacing12),
                      ElevatedButton.icon(
                        onPressed: _isLoading || _error != null || _decodedImage == null ? null : _cropAndSave,
                        icon: const Icon(LucideIcons.check, size: 16),
                        label: const Text('Use Photo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spacing20, vertical: AppTokens.spacing12),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect cropRect;
  final Color borderColor;
  final Color overlayColor;
  final bool showGrid;

  _CropPainter({
    required this.cropRect,
    required this.borderColor,
    required this.overlayColor,
    this.showGrid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cropRect.isEmpty) return;

    // 1. Dark overlay outside crop box
    final overlayPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // 2. Main border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(cropRect, borderPaint);

    // 3. Rule of Thirds Grid Lines
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final w = cropRect.width;
      final h = cropRect.height;

      final v1 = cropRect.left + w / 3;
      final v2 = cropRect.left + (2 * w) / 3;
      canvas.drawLine(Offset(v1, cropRect.top), Offset(v1, cropRect.bottom), gridPaint);
      canvas.drawLine(Offset(v2, cropRect.top), Offset(v2, cropRect.bottom), gridPaint);

      final h1 = cropRect.top + h / 3;
      final h2 = cropRect.top + (2 * h) / 3;
      canvas.drawLine(Offset(cropRect.left, h1), Offset(cropRect.right, h1), gridPaint);
      canvas.drawLine(Offset(cropRect.left, h2), Offset(cropRect.right, h2), gridPaint);
    }

    // 4. Camera crop reticle corner markers
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;

    const cornerLen = 16.0;
    // Top-left
    canvas.drawLine(Offset(cropRect.left - 1, cropRect.top), Offset(cropRect.left + cornerLen, cropRect.top), cornerPaint);
    canvas.drawLine(Offset(cropRect.left, cropRect.top - 1), Offset(cropRect.left, cropRect.top + cornerLen), cornerPaint);

    // Top-right
    canvas.drawLine(Offset(cropRect.right + 1, cropRect.top), Offset(cropRect.right - cornerLen, cropRect.top), cornerPaint);
    canvas.drawLine(Offset(cropRect.right, cropRect.top - 1), Offset(cropRect.right, cropRect.top + cornerLen), cornerPaint);

    // Bottom-left
    canvas.drawLine(Offset(cropRect.left - 1, cropRect.bottom), Offset(cropRect.left + cornerLen, cropRect.bottom), cornerPaint);
    canvas.drawLine(Offset(cropRect.left, cropRect.bottom + 1), Offset(cropRect.left, cropRect.bottom - cornerLen), cornerPaint);

    // Bottom-right
    canvas.drawLine(Offset(cropRect.right + 1, cropRect.bottom), Offset(cropRect.right - cornerLen, cropRect.bottom), cornerPaint);
    canvas.drawLine(Offset(cropRect.right, cropRect.bottom + 1), Offset(cropRect.right, cropRect.bottom - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.showGrid != showGrid;
  }
}
