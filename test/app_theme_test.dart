import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/constants/app_tokens.dart';
import 'package:jobtrail/core/theme/app_theme.dart';

void main() {
  test('display uses Poppins and keeps the existing type metrics', () {
    final theme = AppTheme.light;
    final text = theme.textTheme;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.bodyFamily,
      colorScheme: theme.colorScheme,
    ).textTheme;
    expect(
      text.displayLarge,
      base.displayLarge!.copyWith(fontFamily: 'Poppins'),
    );
    expect(
      text.displayMedium,
      base.displayMedium!.copyWith(fontFamily: 'Poppins'),
    );
    expect(
      text.displaySmall,
      base.displaySmall!.copyWith(fontFamily: 'Poppins'),
    );
    expect(text.headlineLarge, AppTypography.heading.copyWith(fontSize: 32));
    expect(text.headlineMedium, AppTypography.heading);
    expect(text.headlineSmall, AppTypography.section);
    expect(text.titleLarge, AppTypography.section);
    expect(text.titleMedium, base.titleMedium);
    expect(text.titleSmall, base.titleSmall);
    expect(text.bodyLarge, AppTypography.body.copyWith(fontSize: 16));
    expect(text.bodyMedium, AppTypography.body);
    expect(text.bodySmall, AppTypography.caption);
    expect(text.labelLarge, base.labelLarge);
    expect(text.labelMedium, base.labelMedium);
    expect(text.labelSmall, base.labelSmall);
  });

  test('shared surfaces use semantic roles and cards remain flat', () {
    final theme = AppTheme.light;
    final colors = theme.colorScheme;
    expect(theme.scaffoldBackgroundColor, colors.surfaceContainer);
    expect(theme.appBarTheme.backgroundColor, colors.surfaceContainer);
    expect(theme.appBarTheme.scrolledUnderElevation, 0);
    expect(theme.cardTheme.color, colors.surfaceContainerLowest);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.side.color, colors.outline);
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.card));
    expect(theme.inputDecorationTheme.fillColor, colors.surface);
    expect(theme.navigationBarTheme.backgroundColor, colors.surface);
    expect(theme.bottomSheetTheme.modalBackgroundColor, colors.surface);
  });

  testWidgets('form cancel label uses the branded body font at 2x', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
    await tester.tap(find.byKey(const ValueKey('home-add')));
    await tester.pumpAndSettle();

    final cancel = find.text('Batal');
    final label = tester.widget<RichText>(
      find.descendant(of: cancel, matching: find.byType(RichText)),
    );
    expect(label.text.style!.fontFamily, 'Plus Jakarta Sans');
    expect(label.text.style!.fontWeight, FontWeight.w700);
    expect(label.text.style!.fontSize, 14);
    expect(label.textScaler.scale(14), 28);
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
