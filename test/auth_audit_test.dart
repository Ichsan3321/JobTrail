import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/screens/auth/auth_brand.dart';
import 'package:jobtrail/screens/auth/auth_provider.dart';
import 'package:jobtrail/screens/auth/cinematic_splash.dart';

import 'auth_test.dart' show input, launch, tapText, PendingProvider;

class AuditProvider extends UnavailableAuthProvider {
  int restores = 0, calls = 0;
  bool session = false;
  Object? failure;
  List<String>? received;
  final pendingRestore = Completer<bool>();
  bool holdRestore = false;

  @override
  Future<bool> restoreSession() async {
    restores++;
    if (holdRestore) return pendingRestore.future;
    if (failure != null) throw failure!;
    return session;
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls++;
    received = [email, password];
    if (failure != null) throw failure!;
  }

  @override
  Future<void> register(String name, String email, String password) async {
    calls++;
    received = [name, email, password];
    throw const AuthUnavailable();
  }

  @override
  Future<void> sendReset(String email) async {
    calls++;
    received = [email];
    throw const AuthUnavailable();
  }
}

Future<void> mount(WidgetTester tester, AuthProvider provider) async {
  await tester.pumpWidget(JobTrailApp(authProvider: provider));
  await tester.pumpAndSettle();
}

Future<void> credentials(WidgetTester tester) async {
  await input(tester, 'email', '  qa@example.com  ');
  await input(tester, 'password', '  password123  ');
}

Finder get home => find.byKey(const ValueKey('S01'));

void main() {
  testWidgets('session timeout fails closed and retry resolves signed out', (
    tester,
  ) async {
    final provider = AuditProvider()..holdRestore = true;
    await tester.pumpWidget(JobTrailApp(authProvider: provider));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(find.text('Pemeriksaan sesi gagal.'), findsOneWidget);
    provider.holdRestore = false;
    await tapText(tester, 'Coba lagi');
    expect(provider.restores, 2);
    expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
    // A late result from the timed-out check must not open Home.
    provider.pendingRestore.complete(true);
    await tester.pumpAndSettle();
    expect(home, findsNothing);
  });

  testWidgets('changing provider ignores the previous pending session', (
    tester,
  ) async {
    final first = AuditProvider()..holdRestore = true;
    await tester.pumpWidget(JobTrailApp(authProvider: first));
    await tester.pump(const Duration(seconds: 3));
    final second = AuditProvider();
    await tester.pumpWidget(JobTrailApp(authProvider: second));
    await tester.pumpAndSettle();
    first.pendingRestore.complete(true);
    await tester.pumpAndSettle();
    expect(second.restores, 1);
    expect(home, findsNothing);
    expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
  });

  for (final established in [false, true]) {
    testWidgets(
      'sign-in opens Home only with established session: $established',
      (tester) async {
        final provider = AuditProvider();
        await mount(tester, provider);
        await credentials(tester);
        provider.session = established;
        await tapText(tester, 'Masuk ke JobTrail');
        expect(provider.received, ['qa@example.com', '  password123  ']);
        expect(provider.restores, 2);
        expect(home, established ? findsOneWidget : findsNothing);
        expect(find.byType(MaterialApp), findsOneWidget);
        if (!established) {
          expect(
            find.textContaining('Autentikasi belum terhubung.'),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets('login times out, unlocks retry and ignores late completion', (
    tester,
  ) async {
    final provider = PendingProvider()..session.complete(false);
    await mount(tester, provider);
    await credentials(tester);
    final submit = find.widgetWithText(FilledButton, 'Masuk ke JobTrail');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    expect(provider.attempts, 1);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Permintaan gagal. Silakan coba lagi.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    provider.login.complete();
    await tester.pumpAndSettle();
    expect(home, findsNothing);
  });

  testWidgets('disposed login and session futures do not use stale context', (
    tester,
  ) async {
    final pending = AuditProvider()..holdRestore = true;
    await tester.pumpWidget(JobTrailApp(authProvider: pending));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.pendingRestore.complete(true);
    await tester.pumpAndSettle();
    final login = PendingProvider()..session.complete(false);
    await mount(tester, login);
    await credentials(tester);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    login.login.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider exceptions never expose credentials or raw details', (
    tester,
  ) async {
    final provider = AuditProvider();
    await mount(tester, provider);
    await credentials(tester);
    provider.failure = StateError('secret-token backend exception');
    await tapText(tester, 'Masuk ke JobTrail');
    expect(find.text('Permintaan gagal. Silakan coba lagi.'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
    expect(home, findsNothing);
  });

  testWidgets(
    'validation blocks invalid email, blank name and weak passwords',
    (tester) async {
      final provider = AuditProvider();
      await mount(tester, provider);
      await input(tester, 'email', 'invalid@');
      await input(tester, 'password', 'short');
      await tapText(tester, 'Masuk ke JobTrail');
      expect(find.text('Masukkan email yang valid.'), findsOneWidget);
      expect(find.text('Minimal 8 karakter.'), findsOneWidget);
      expect(provider.calls, 0);
      await tapText(tester, 'Belum punya akun? Daftar sekarang');
      await input(tester, 'name', '   ');
      await tapText(tester, 'Buat Akun');
      expect(find.text('Wajib diisi.'), findsWidgets);
      expect(provider.calls, 0);
    },
  );

  testWidgets('register failure stays on form; previews never call provider', (
    tester,
  ) async {
    final provider = AuditProvider();
    await mount(tester, provider);
    await tapText(tester, 'Belum punya akun? Daftar sekarang');
    await input(tester, 'name', '  QA User  ');
    await credentials(tester);
    await input(tester, 'confirm', '  password123  ');
    await tapText(tester, 'Buat Akun');
    expect(provider.received, ['QA User', 'qa@example.com', '  password123  ']);
    expect(find.text('Mulai langkah barumu'), findsOneWidget);
    await tapText(tester, 'Pratinjau pengembangan: verifikasi email');
    await tapText(tester, 'Kirim Ulang Email');
    expect(provider.calls, 1);
    await tapText(tester, 'Kembali ke Login');
    await tapText(tester, 'Lupa password?');
    await tapText(tester, 'Kirim Link Reset');
    expect(provider.received, ['qa@example.com']);
    expect(find.text('Lupa password?'), findsOneWidget);
    await tapText(tester, 'Pratinjau pengembangan: email reset terkirim');
    await tapText(tester, 'Kirim Ulang Link');
    await tapText(tester, 'Simulasi buka link reset dari email');
    await credentialsForReset(tester);
    await tapText(tester, 'Simpan Password Baru');
    expect(provider.calls, 2);
    expect(home, findsNothing);
  });

  testWidgets('password toggles are independent and cleared on navigation', (
    tester,
  ) async {
    await launch(tester);
    await tapText(tester, 'Belum punya akun? Daftar sekarang');
    await input(tester, 'password', 'password123');
    await input(tester, 'confirm', 'password123');
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(2)).obscureText, isTrue);
    expect(tester.widget<TextField>(fields.at(3)).obscureText, isTrue);
    final toggle = find.byTooltip('Tampilkan password').first;
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(2)).obscureText, isFalse);
    expect(tester.widget<TextField>(fields.at(3)).obscureText, isTrue);
    await tapText(tester, 'Sudah punya akun? Masuk');
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, isEmpty);
    expect(field.obscureText, isTrue);
  });

  testWidgets('system Back returns each auth subpage to Login', (tester) async {
    await launch(tester);
    for (final link in [
      'Belum punya akun? Daftar sekarang',
      'Lupa password?',
    ]) {
      await tapText(tester, link);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
    }
  });

  testWidgets('enabling reduced motion mid-splash completes once', (
    tester,
  ) async {
    var completions = 0;
    await tester.pumpWidget(
      MaterialApp(home: CinematicSplash(onComplete: () => completions++)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'splash V2 matches storyboard mark sizes and positions at phase anchors',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(home: CinematicSplash(onComplete: () => completed++)),
      );
      await tester.pump();
      final mark = find.byType(AuthBrand);
      expect(tester.widget<AuthBrand>(mark).size, 52);
      for (final anchor in [
        (500, 92.0, 245.0),
        (800, 148.0, 223.0),
        (900, 148.0, 217.0),
      ]) {
        await tester.pump(Duration(milliseconds: anchor.$1));
        expect(tester.widget<AuthBrand>(mark).size, closeTo(anchor.$2, .01));
        expect(tester.getTopLeft(mark).dy, closeTo(anchor.$3, .01));
        expect(completed, 0);
      }
      await tester.pump(const Duration(milliseconds: 451));
      expect(completed, 1);
    },
  );

  testWidgets(
    'startup honors reduced motion without waiting for the cinematic duration',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(const JobTrailApp());
      await tester.pump();
      await tester.pump();
      expect(find.byType(CinematicSplash), findsNothing);
      expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
      expect(home, findsNothing);
    },
  );

  for (final size in [const Size(393, 852), const Size(320, 640)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all auth pages at $size, ${scale}x, keyboard 280px', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final semantics = tester.ensureSemantics();
        try {
          await launch(tester);
          expect(find.byType(MaterialApp), findsOneWidget);
          expect(
            tester
                .widget<Image>(
                  find
                      .descendant(
                        of: find.byType(AuthBrand),
                        matching: find.byType(Image),
                      )
                      .first,
                )
                .image,
            isA<AssetImage>().having(
              (image) => image.assetName,
              'official mark',
              'assets/home/auth-official-mark.png',
            ),
          );

          Future<void> checkPage() async {
            final fields = find.byType(TextFormField);
            if (fields.evaluate().isNotEmpty) {
              await tester.showKeyboard(fields.last);
            }
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            await tester.pumpAndSettle();
            final submit = find.byType(FilledButton);
            await tester.ensureVisible(submit);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(submit).bottom,
              lessThanOrEqualTo(size.height - 280),
            );
            expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            expect(tester.takeException(), isNull);
            tester.view.viewInsets = FakeViewPadding.zero;
            await tester.pumpAndSettle();
          }

          await checkPage();
          expect(
            tester
                .widget<OutlinedButton>(find.byType(OutlinedButton))
                .onPressed,
            isNull,
          );
          await tapText(tester, 'Belum punya akun? Daftar sekarang');
          await checkPage();
          await tapText(tester, 'Pratinjau pengembangan: verifikasi email');
          await checkPage();
          await tapText(tester, 'Kembali ke Login');
          await tapText(tester, 'Lupa password?');
          await checkPage();
          await tapText(tester, 'Pratinjau pengembangan: email reset terkirim');
          await checkPage();
          await tapText(tester, 'Simulasi buka link reset dari email');
          await checkPage();
          await tapText(tester, 'Kembali ke Login');
          expect(find.text('Lanjutkan perjalananmu'), findsOneWidget);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}

Future<void> credentialsForReset(WidgetTester tester) async {
  await input(tester, 'password', 'password123');
  await input(tester, 'confirm', 'password123');
}
