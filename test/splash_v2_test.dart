import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/screens/auth/auth_brand.dart';
import 'package:jobtrail/screens/auth/auth_screen.dart';
import 'package:jobtrail/screens/auth/cinematic_splash.dart';

import 'auth_audit_test.dart' show AuditProvider;

void main() {
  for (final size in [
    const Size(393, 852),
    const Size(320, 640),
    const Size(1280, 1000),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'V2 preserves portrait framing at $size, ${textScale}x text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          for (final seconds in [0.0, .5, 1.3, 2.2]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(body: SplashV2Scene(seconds: seconds)),
              ),
            );
            await tester.pump();
            final canvas = tester.getRect(
              find.byKey(const ValueKey('splash-v2-canvas')),
            );
            expect(canvas.width / canvas.height, closeTo(393 / 852, .001));
            expect(canvas.width, lessThanOrEqualTo(393));
            expect(canvas.left, greaterThanOrEqualTo(0));
            expect(canvas.right, lessThanOrEqualTo(size.width));
            expect(canvas.bottom, lessThanOrEqualTo(size.height));
            if (seconds == 2.2) {
              expect(
                tester.widget<AuthBrand>(find.byType(AuthBrand)).size,
                148,
              );
              final mark = tester.getRect(find.byType(AuthBrand));
              expect(mark.width / canvas.width, closeTo(148 / 393, .001));
              expect(find.text('DISCOVER'), findsOneWidget);
              expect(find.text('APPLY'), findsOneWidget);
              expect(find.text('GROW'), findsOneWidget);
              expect(find.byType(LinearProgressIndicator), findsNothing);
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('tracking dot follows the V2 curve through Trail Reveal Ready', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final positions = <Offset>[];
    for (final seconds in [.5, .9, 1.3, 2.2]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SplashV2Scene(seconds: seconds)),
        ),
      );
      positions.add(
        tester.getCenter(find.byKey(const ValueKey('splash-v2-tracking-dot'))),
      );
    }
    expect((positions.first - const Offset(238, 336)).distance, lessThan(3));
    expect((positions[2] - const Offset(330, 275)).distance, lessThan(4));
    expect((positions.last - const Offset(344, 275)).distance, lessThan(2));
    expect(positions[1].dx, inExclusiveRange(positions[0].dx, positions[2].dx));
  });

  testWidgets('Ready fades into signed-out Login within 2.9 seconds', (
    tester,
  ) async {
    await tester.pumpWidget(const JobTrailApp());
    await tester.pump();
    await tester.pump(
      CinematicSplash.duration + const Duration(milliseconds: 1),
    );
    await tester.pump();
    expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
    expect(find.byType(CinematicSplash), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 221));
    await tester.pump();
    expect(find.byType(CinematicSplash), findsNothing);
    expect(find.byKey(const ValueKey('S01')), findsNothing);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets(
    'session replacement removes Home immediately during gate transitions',
    (tester) async {
      final restored = AuditProvider()..session = true;
      await tester.pumpWidget(JobTrailApp(authProvider: restored));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S01')), findsOneWidget);
      final pending = AuditProvider()..holdRestore = true;
      await tester.pumpWidget(JobTrailApp(authProvider: pending));
      expect(find.byKey(const ValueKey('S01')), findsNothing);
      pending.pendingRestore.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
    },
  );

  testWidgets(
    'reduced motion enabled during startup bypasses the fade and accepts input',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(const JobTrailApp());
      await tester.pump(const Duration(milliseconds: 500));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      await tester.pump();
      expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
      // Input decorations have their own constant-opacity fades. Check only
      // ancestors that could dim the entire Login screen during the gate fade.
      final pageFades = find.ancestor(
        of: find.byType(AuthScreen),
        matching: find.byType(FadeTransition),
      );
      for (final fade in tester.widgetList<FadeTransition>(pageFades)) {
        expect(fade.opacity.value, 1);
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk ke JobTrail'));
      await tester.pump();
      expect(find.text('Wajib diisi.'), findsNWidgets(2));
    },
  );
}
