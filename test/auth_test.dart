import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/screens/auth/auth_provider.dart';
import 'package:jobtrail/screens/auth/cinematic_splash.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> input(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey('auth-field-$key'));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
}

Future<void> launch(WidgetTester tester) async {
  await tester.pumpWidget(const JobTrailApp(showAuthentication: true));
  await tester.pumpAndSettle();
}

class RestoredProvider extends UnavailableAuthProvider {
  @override
  Future<bool> restoreSession() async => true;
}

class PendingProvider extends UnavailableAuthProvider {
  final session = Completer<bool>();
  final login = Completer<void>();
  int attempts = 0;
  @override
  Future<bool> restoreSession() => session.future;
  @override
  Future<void> signIn(String email, String password) {
    attempts++;
    return login.future;
  }
}

void main() {
  testWidgets(
    'session remains gated until resolved, failed check retries safely',
    (tester) async {
      final provider = PendingProvider();
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: true, authProvider: provider),
      );
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('S01')), findsNothing);
      provider.session.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Pemeriksaan sesi gagal.'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    },
  );
  testWidgets(
    'in-flight login is disabled and does not create duplicate requests',
    (tester) async {
      final provider = PendingProvider()..session.complete(false);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: true, authProvider: provider),
      );
      await tester.pumpAndSettle();
      await input(tester, 'email', 'qa@example.com');
      await input(tester, 'password', 'password123');
      final submit = find.widgetWithText(FilledButton, 'Masuk ke JobTrail');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull,
      );
      expect(provider.attempts, 1);
      provider.login.completeError(const AuthUnavailable());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Autentikasi belum terhubung.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'real startup animates then remains signed out; demo is explicit',
    (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: true));
      expect(find.byType(CinematicSplash), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(CinematicSplash), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
      expect(find.byKey(const ValueKey('S01')), findsNothing);
      await tapText(tester, 'Demo pengembangan: buka Home tanpa login');
      expect(find.byKey(const ValueKey('S01')), findsOneWidget);
    },
  );
  testWidgets('restored provider session routes to the existing Home', (
    tester,
  ) async {
    await tester.pumpWidget(
      JobTrailApp(showAuthentication: true, authProvider: RestoredProvider()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
  });
  testWidgets('login validates and never invents an unavailable session', (
    tester,
  ) async {
    await launch(tester);
    await tapText(tester, 'Masuk ke JobTrail');
    expect(find.text('Wajib diisi.'), findsNWidgets(2));
    await input(tester, 'email', 'qa@example.com');
    await input(tester, 'password', 'password123');
    await tester.ensureVisible(find.byTooltip('Tampilkan password'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tampilkan password'));
    await tester.pump();
    expect(find.byTooltip('Sembunyikan password'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('auth-field-password')),
          )
          .controller!
          .text,
      'password123',
    );
    await tapText(tester, 'Masuk ke JobTrail');
    expect(find.textContaining('Autentikasi belum terhubung.'), findsOneWidget);
    expect(find.byKey(const ValueKey('S01')), findsNothing);
  });
  testWidgets(
    'register mismatch, verify preview, recovery and password preview are honest',
    (tester) async {
      await launch(tester);
      await tapText(tester, 'Belum punya akun? Daftar sekarang');
      await input(tester, 'name', 'QA User');
      await input(tester, 'email', 'qa@example.com');
      await input(tester, 'password', 'password123');
      await input(tester, 'confirm', 'different123');
      await tapText(tester, 'Buat Akun');
      expect(find.text('Konfirmasi password belum cocok.'), findsOneWidget);
      await tapText(tester, 'Pratinjau pengembangan: verifikasi email');
      expect(find.text('Cek email kamu'), findsOneWidget);
      expect(find.textContaining('Tidak ada email terkirim'), findsOneWidget);
      await tapText(tester, 'Kembali ke Login');
      await tapText(tester, 'Lupa password?');
      await input(tester, 'email', 'qa@example.com');
      await tapText(tester, 'Kirim Link Reset');
      expect(
        find.textContaining('Autentikasi belum terhubung.'),
        findsOneWidget,
      );
      await tapText(tester, 'Pratinjau pengembangan: email reset terkirim');
      expect(find.text('Pratinjau email reset'), findsOneWidget);
      await tapText(tester, 'Simulasi buka link reset dari email');
      await input(tester, 'password', 'password123');
      await input(tester, 'confirm', 'password123');
      await tapText(tester, 'Simpan Password Baru');
      expect(
        find.textContaining('Autentikasi belum terhubung.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('reduced motion skips cinematic animation', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await launch(tester);
    expect(find.byType(CinematicSplash), findsNothing);
    expect(find.text('Masuk ke JobTrail'), findsOneWidget);
  });
  testWidgets('auth pages remain scrollable at narrow width and 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester);
    await tapText(tester, 'Belum punya akun? Daftar sekarang');
    await tapText(tester, 'Pratinjau pengembangan: verifikasi email');
    await tapText(tester, 'Kembali ke Login');
    await tapText(tester, 'Lupa password?');
    await tapText(tester, 'Pratinjau pengembangan: email reset terkirim');
    await tapText(tester, 'Simulasi buka link reset dari email');
    await tapText(tester, 'Kembali ke Login');
    expect(tester.takeException(), isNull);
  });
}
