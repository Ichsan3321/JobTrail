import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/auth/auth_configuration.dart';
import 'package:jobtrail/screens/auth/auth_provider.dart';

import 'jobtrail_persistence_test.dart' show snapshot;
import 'support/fake_jobtrail_repository.dart';

DateTime _future() => DateTime.now().add(const Duration(hours: 1));

class _SessionFake extends UnavailableAuthProvider
    implements SessionAuthProvider {
  _SessionFake({this.current = const AuthSession.signedOut()});

  int cancelled = 0;
  bool disposed = false;
  late final events = StreamController<AuthSession>.broadcast(
    onCancel: () => cancelled++,
  );
  AuthSession current;
  Completer<AuthSession>? restoring;
  Completer<void>? leaving;
  AuthIssue? loginFailure;
  bool registerImmediately = false;
  int resetRequests = 0;
  int confirmationRequests = 0;
  int passwordChanges = 0;

  void emit(AuthSession session) {
    current = session;
    events.add(session);
  }

  @override
  Stream<AuthSession> get sessionChanges => events.stream;

  @override
  Future<AuthSession> readSession() async =>
      restoring == null ? current : await restoring!.future;

  @override
  Future<void> signIn(String email, String password) async {
    if (loginFailure case final issue?) throw issue;
    emit(AuthSession.authenticated('account-a', _future()));
  }

  @override
  Future<void> register(String name, String email, String password) async {
    if (registerImmediately) {
      emit(AuthSession.authenticated('new-account', _future()));
    }
  }

  @override
  Future<void> sendReset(String email) async => resetRequests++;

  @override
  Future<void> resendVerification(String email) async => confirmationRequests++;

  @override
  Future<void> setPassword(String password) async {
    if (current.phase != AuthPhase.recovery) throw AuthIssue.invalidLink;
    passwordChanges++;
    emit(const AuthSession.signedOut());
  }

  @override
  Future<void> signOut() async {
    await leaving?.future;
    emit(const AuthSession.signedOut());
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(events.close());
  }
}

class _GoogleSessionFake extends _SessionFake implements GoogleOAuthProvider {
  _GoogleSessionFake({super.current, this.canSignInWithGoogle = true});

  @override
  final bool canSignInWithGoogle;
  int launches = 0;
  Completer<void>? launching;

  @override
  Future<void> signInWithGoogle() async {
    launches++;
    await launching?.future;
  }
}

Future<void> _mount(
  WidgetTester tester,
  _SessionFake provider, {
  AccountHomeBuilder? home,
  AccountRepositoryFactory? repository,
  JobTrailStore? demoStore,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    JobTrailApp(
      authProvider: provider,
      accountHomeBuilder: home,
      repositoryFactory: repository,
      store: demoStore,
      disposeSessionProvider: true,
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String field, String value) async {
  final target = find.byKey(ValueKey('auth-field-$field'));
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
}

void main() {
  const googleLabel = 'Lanjutkan dengan Google';
  const googleDisabled = 'Google Sign-In belum tersedia';

  test(
    'backend config fails closed and restricts callback origins and paths',
    () {
      AuthConfiguration config({
        String mode = 'supabase',
        String key = 'sb_publishable_example',
        String project = 'https://sample.supabase.co',
        String web = 'http://localhost:3000',
      }) => AuthConfiguration(
        mode: mode,
        projectUrl: project,
        publishableKey: key,
        webOrigin: web,
      );
      expect(config(mode: 'mock', key: '', project: '').isMock, isTrue);
      for (final build in [
        () => config(key: ''),
        () => config(key: 'sb_secret_example'),
        () => config(mode: 'unknown'),
        () => config(project: 'http://sample.supabase.co'),
        () => config(project: 'https://sample.supabase.co/path'),
        () => config(web: 'http://remote.example'),
      ]) {
        expect(build, throwsFormatException);
      }
      final valid = config();
      expect(
        valid.redirect(AuthCallback.confirmation, onWeb: true).toString(),
        'http://localhost:3000/?auth=confirm',
      );
      expect(
        valid.callback(
          Uri.parse('http://localhost:3000/?auth=recovery&code=x'),
          onWeb: true,
        ),
        AuthCallback.recovery,
      );
      expect(
        valid.callback(
          Uri.parse('http://localhost:3001/?auth=recovery&code=x'),
          onWeb: true,
        ),
        isNull,
      );
      expect(
        valid.callback(
          Uri.parse('http://localhost:3000/?auth=recovery&auth=confirm'),
          onWeb: true,
        ),
        isNull,
      );
      expect(
        valid.callback(
          Uri.parse('com.example.jobtrail://auth/recovery?code=x'),
          onWeb: false,
        ),
        AuthCallback.recovery,
      );
      expect(
        valid.callback(Uri.parse('evil://auth/recovery?code=x'), onWeb: false),
        isNull,
      );
    },
  );

  test('Google is opt-in for hosted Web on the configured origin', () {
    AuthConfiguration config({
      bool enabled = false,
      String mode = 'supabase',
    }) => AuthConfiguration(
      mode: mode,
      projectUrl: 'https://sample.supabase.co',
      publishableKey: 'sb_publishable_example',
      webOrigin: 'http://localhost:3000',
      googleOAuthEnabled: enabled,
    );

    final callback = Uri.parse(
      'http://localhost:3000/?auth=google&code=example',
    );
    final enabled = config(enabled: true);
    expect(
      enabled.redirect(AuthCallback.google, onWeb: true).toString(),
      'http://localhost:3000/?auth=google',
    );
    expect(enabled.allowsGoogleOAuth(callback, onWeb: true), isTrue);
    expect(enabled.callback(callback, onWeb: true), AuthCallback.google);
    for (final disabled in [config(), config(enabled: true, mode: 'mock')]) {
      expect(disabled.allowsGoogleOAuth(callback, onWeb: true), isFalse);
      expect(disabled.callback(callback, onWeb: true), isNull);
    }
    final native = Uri.parse('com.example.jobtrail://auth/google?code=example');
    expect(enabled.allowsGoogleOAuth(native, onWeb: false), isFalse);
    expect(enabled.callback(native, onWeb: false), isNull);
    for (final wrongOrigin in [
      callback.replace(port: 3001),
      callback.replace(host: '127.0.0.1'),
      callback.replace(scheme: 'https'),
      callback.replace(userInfo: 'unexpected'),
    ]) {
      expect(enabled.allowsGoogleOAuth(wrongOrigin, onWeb: true), isFalse);
      expect(enabled.callback(wrongOrigin, onWeb: true), isNull);
    }
    expect(
      enabled.callback(callback.replace(path: '/other'), onWeb: true),
      isNull,
    );
    expect(
      enabled.callback(
        callback.replace(query: 'auth=google&auth=confirm'),
        onWeb: true,
      ),
      isNull,
    );
  });

  testWidgets('hosted configuration can disable Google on Login and Register', (
    tester,
  ) async {
    final fake = _GoogleSessionFake(canSignInWithGoogle: false);
    await _mount(tester, fake);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, googleDisabled),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'Belum punya akun? Daftar sekarang');
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, googleDisabled),
          )
          .onPressed,
      isNull,
    );
    expect(fake.launches, 0);
  });

  testWidgets('mock Login keeps the disabled Google action and demo entry', (
    tester,
  ) async {
    await tester.pumpWidget(const JobTrailApp());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, googleDisabled),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'Demo pengembangan: buka Home tanpa login');
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
  });

  testWidgets('Google launches once while pending and retries after failure', (
    tester,
  ) async {
    final fake = _GoogleSessionFake()..launching = Completer<void>();
    await _mount(tester, fake);
    await _tap(tester, 'Belum punya akun? Daftar sekarang');
    final target = find.text(googleLabel);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.tap(target);
    await tester.pump();
    expect(fake.launches, 1);
    expect(find.text('Membuka Google…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Buat Akun'))
          .onPressed,
      isNull,
    );

    fake.launching!.completeError(StateError('raw provider error'));
    await tester.pumpAndSettle();
    expect(find.text(AuthIssue.googleFailed.message), findsOneWidget);
    expect(find.textContaining('raw provider error'), findsNothing);
    fake.launching = null;
    await _tap(tester, googleLabel);
    expect(fake.launches, 2);
    expect(find.text(AuthIssue.googleFailed.message), findsNothing);
    expect(find.text('Akun terhubung'), findsNothing);
  });

  for (final issue in [AuthIssue.googleCancelled, AuthIssue.googleFailed]) {
    testWidgets(
      'Google callback feedback stays on Login and can retry ($issue)',
      (tester) async {
        final fake = _GoogleSessionFake(
          current: AuthSession.signedOut(issue: issue),
        );
        await _mount(tester, fake);
        expect(find.text(issue.message), findsOneWidget);
        expect(find.text('Masuk ke JobTrail'), findsOneWidget);
        await _tap(tester, googleLabel);
        expect(fake.launches, 1);
        expect(find.text(issue.message), findsNothing);
      },
    );
  }

  testWidgets('Google session loads and restores isolated account snapshots', (
    tester,
  ) async {
    final firstSession = _GoogleSessionFake();
    final pending = Completer<JobTrailSnapshot>();
    final first = FakeJobTrailRepository(() => pending.future);
    final second = FakeJobTrailRepository(
      () => snapshot('Second account marker'),
    );
    final firstIdentity = AuthSession.authenticated('google-a', _future());
    final secondIdentity = AuthSession.authenticated('google-b', _future());
    await _mount(
      tester,
      firstSession,
      repository: (userId) {
        expect(userId, 'google-a');
        return first;
      },
    );
    await _tap(tester, googleLabel);
    expect(first.reads, 0);
    firstSession.emit(firstIdentity);
    await tester.idle();
    await tester.pump();
    expect(find.text('Memuat data JobTrail'), findsOneWidget);
    expect(first.reads, 1);
    await _tap(tester, 'Keluar');
    expect(first.disposed, isTrue);
    expect(find.text(googleLabel), findsOneWidget);

    final restored = _GoogleSessionFake(current: secondIdentity);
    await _mount(
      tester,
      restored,
      repository: (userId) {
        expect(userId, 'google-b');
        return second;
      },
    );
    pending.complete(snapshot('Previous account marker'));
    await tester.pumpAndSettle();
    expect(find.text('Previous account marker'), findsNothing);
    expect(find.text('Second account marker'), findsWidgets);
    expect(second.reads, 1);
    expect(restored.launches, 0);
  });

  testWidgets(
    'real mode shows safe login failure, then gates data and logs out',
    (tester) async {
      final fake = _SessionFake()..loginFailure = AuthIssue.invalidCredentials;
      await _mount(tester, fake);
      expect(find.byKey(const ValueKey('auth-demo-entry')), findsNothing);
      await _type(tester, 'email', 'tester@example.invalid');
      await _type(tester, 'password', 'validpass123');
      await _tap(tester, 'Masuk ke JobTrail');
      expect(find.text(AuthIssue.invalidCredentials.message), findsOneWidget);
      fake.loginFailure = null;
      await _tap(tester, 'Masuk ke JobTrail');
      expect(find.text('Akun terhubung'), findsOneWidget);
      expect(find.byKey(const ValueKey('S01')), findsNothing);
      await _tap(tester, 'Keluar');
      expect(find.text('Masuk ke JobTrail'), findsOneWidget);
    },
  );

  for (final immediate in [false, true]) {
    testWidgets('registration follows session presence: immediate=$immediate', (
      tester,
    ) async {
      final fake = _SessionFake()..registerImmediately = immediate;
      await _mount(tester, fake);
      await _tap(tester, 'Belum punya akun? Daftar sekarang');
      await _type(tester, 'name', 'Disposable Tester');
      await _type(tester, 'email', 'tester@example.invalid');
      await _type(tester, 'password', 'validpass123');
      await _type(tester, 'confirm', 'validpass123');
      await _tap(tester, 'Buat Akun');
      if (immediate) {
        expect(find.text('Akun terhubung'), findsOneWidget);
      } else {
        expect(find.text('Cek email kamu'), findsOneWidget);
        await _tap(tester, 'Kirim Ulang Email');
        expect(fake.confirmationRequests, 1);
        fake.emit(AuthSession.authenticated('confirmed-account', _future()));
        await tester.pumpAndSettle();
        expect(find.text('Akun terhubung'), findsOneWidget);
      }
    });
  }

  testWidgets(
    'recovery requests and session route stay outside protected Home',
    (tester) async {
      final fake = _SessionFake();
      await _mount(tester, fake);
      await _tap(tester, 'Lupa password?');
      await _type(tester, 'email', 'tester@example.invalid');
      await _tap(tester, 'Kirim Link Reset');
      expect(fake.resetRequests, 1);
      expect(find.text('Permintaan reset diterima'), findsOneWidget);
      fake.emit(AuthSession.recovery('account-a', _future()));
      await tester.pumpAndSettle();
      expect(find.text('Buat password baru'), findsOneWidget);
      expect(find.text('Akun terhubung'), findsNothing);
      await _type(tester, 'password', 'new-valid-pass123');
      await _type(tester, 'confirm', 'new-valid-pass123');
      await _tap(tester, 'Simpan Password Baru');
      expect(fake.passwordChanges, 1);
      expect(find.text('Masuk ke JobTrail'), findsOneWidget);
    },
  );

  testWidgets(
    'account switching destroys protected routes, modals, and the old store',
    (tester) async {
      final fake = _SessionFake(
        current: AuthSession.authenticated('account-a', _future()),
      );
      final injectedDemo = JobTrailStore.demo();
      addTearDown(injectedDemo.dispose);
      final stores = <String, JobTrailStore>{};
      late NavigatorState protectedNavigator;
      await _mount(
        tester,
        fake,
        demoStore: injectedDemo,
        home: (context, user, store, nav, signOut) {
          stores[user] = store;
          protectedNavigator = Navigator.of(context);
          return Scaffold(body: Text(user));
        },
      );
      final oldStore = stores['account-a']!;
      expect(oldStore.applications, isEmpty);
      oldStore.addApplication(
        ApplicationDraft(
          company: 'Account A only',
          position: 'Intern',
          source: 'LinkedIn',
          appliedAt: oldStore.referenceDate,
          status: RecruitmentStatus.applied,
          location: 'Surabaya',
          workType: WorkType.remote,
        ),
      );
      unawaited(
        protectedNavigator.push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const AlertDialog(title: Text('Protected dialog')),
                ),
                child: const Text('Protected detail'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'Protected detail');
      expect(find.text('Protected dialog'), findsOneWidget);
      fake.emit(AuthSession.authenticated('account-b', _future()));
      await tester.pumpAndSettle();
      expect(find.text('Protected dialog'), findsNothing);
      expect(find.text('Protected detail'), findsNothing);
      expect(find.text('account-b'), findsOneWidget);
      expect(stores['account-b']!.applications, isEmpty);
      expect(() => oldStore.addListener(() {}), throwsFlutterError);
    },
  );

  testWidgets(
    'refresh keeps scope; expiry and logout close it before completion',
    (tester) async {
      final fake = _SessionFake(
        current: AuthSession.authenticated('account-a', _future()),
      );
      final stores = <JobTrailStore>[];
      await _mount(
        tester,
        fake,
        home: (_, user, store, nav, signOut) {
          stores.add(store);
          return Scaffold(
            body: TextButton(
              onPressed: signOut,
              child: const Text('Scope logout'),
            ),
          );
        },
      );
      final original = stores.last;
      fake.emit(
        AuthSession.authenticated(
          'account-a',
          DateTime.now().add(const Duration(seconds: 2)),
        ),
      );
      await tester.pump();
      expect(stores.last, same(original));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(AuthIssue.expired.message), findsOneWidget);
      fake.emit(AuthSession.authenticated('account-a', _future()));
      await tester.pumpAndSettle();
      expect(stores.last, isNot(same(original)));
      fake.leaving = Completer<void>();
      await tester.tap(find.text('Scope logout'));
      await tester.pump();
      expect(find.text('Scope logout'), findsNothing);
      fake.emit(AuthSession.authenticated('account-a', _future()));
      await tester.pump();
      expect(find.text('Scope logout'), findsNothing);
      fake.leaving!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Masuk ke JobTrail'), findsOneWidget);
    },
  );

  testWidgets(
    'newer events win over restoration and subscriptions are disposed',
    (tester) async {
      final fake = _SessionFake()..restoring = Completer<AuthSession>();
      await _mount(
        tester,
        fake,
        settle: false,
        home: (_, user, store, nav, signOut) => Scaffold(body: Text(user)),
      );
      fake.emit(AuthSession.authenticated('new-account', _future()));
      await tester.pumpAndSettle();
      fake.restoring!.complete(
        AuthSession.authenticated('old-account', _future()),
      );
      await tester.pumpAndSettle();
      expect(find.text('old-account'), findsNothing);
      expect(find.text('new-account'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fake.cancelled, 1);
      expect(fake.disposed, isTrue);
    },
  );
}
