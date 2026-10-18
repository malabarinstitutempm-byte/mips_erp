import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mips_erp/shared/widgets/image_cropper_dialog.dart';

void main() {
  late Uint8List testImageBytes;

  setUp(() {
    // Generate a valid 200x200 JPEG test image
    final image = img.Image(width: 200, height: 200);
    img.fill(image, color: img.ColorRgb8(50, 120, 220));
    testImageBytes = Uint8List.fromList(img.encodeJpg(image));
  });

  Widget createSubject({required void Function(CroppedImageResult?) onResult}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await ImageCropperDialog.show(
                context,
                bytes: testImageBytes,
                fileName: 'avatar.jpg',
              );
              onResult(result);
            },
            child: const Text('Open Cropper'),
          ),
        ),
      ),
    );
  }

  testWidgets('ImageCropperDialog renders all controls, zoom in/out, and crops successfully', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    CroppedImageResult? croppedResult;

    await tester.pumpWidget(createSubject(onResult: (res) => croppedResult = res));
    await tester.pumpAndSettle();

    // 1. Open cropper
    await tester.tap(find.text('Open Cropper'));
    await tester.pumpAndSettle();

    // Verify dialog header and tools
    expect(find.text('Crop & Adjust Photo'), findsOneWidget);
    expect(find.text('7:9 ID Portrait'), findsOneWidget);
    expect(find.text('1:1 Square'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.byIcon(LucideIcons.zoomIn), findsOneWidget);
    expect(find.byIcon(LucideIcons.zoomOut), findsOneWidget);
    expect(find.byIcon(LucideIcons.rotateCcw), findsOneWidget);
    expect(find.byIcon(LucideIcons.rotateCw), findsOneWidget);
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
    expect(find.text('Use Photo'), findsOneWidget);

    // 2. Test Zoom In (+25%)
    await tester.tap(find.byIcon(LucideIcons.zoomIn));
    await tester.pumpAndSettle();
    expect(find.text('125%'), findsOneWidget);

    // 3. Test Zoom Out (-25%)
    await tester.tap(find.byIcon(LucideIcons.zoomOut));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);

    // 4. Test Aspect Ratio toggle to 1:1
    await tester.tap(find.text('1:1 Square'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Square 1:1'), findsOneWidget);

    // 5. Test Rotate CW
    await tester.tap(find.byIcon(LucideIcons.rotateCw));
    await tester.pumpAndSettle();

    // 6. Test Reset button
    await tester.tap(find.byIcon(LucideIcons.refreshCw));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);

    // 7. Test 'Use Photo' action
    await tester.tap(find.text('Use Photo'));
    await tester.pumpAndSettle();

    // Verify dialog closed and result returned
    expect(find.text('Crop & Adjust Photo'), findsNothing);
    expect(croppedResult, isNotNull);
    expect(croppedResult!.bytes.isNotEmpty, isTrue);

    // Verify cropped bytes decode into a valid image
    final decoded = img.decodeImage(croppedResult!.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, equals(600));
  });
}
