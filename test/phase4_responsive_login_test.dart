import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mips_erp/features/auth/login_screen.dart';

void main() {
  group('LoginScreen Mobile Web Responsiveness Tests', () {
    testWidgets('1. Mobile viewport (360x780) renders compact single-column layout without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify mobile branding header and form elements
      expect(find.text('MIPS ERP'), findsOneWidget);
      expect(find.text('Malabar Institute of Paramedical Science'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);

      // Verify desktop-only slogan is NOT rendered in mobile view
      expect(find.text('Empowering\nHealthcare Education'), findsNothing);
    });

    testWidgets('2. Desktop viewport (1200x800) renders two-column institutional layout', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify desktop two-column branding and form
      expect(find.text('Empowering\nHealthcare Education'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });
  });
}
