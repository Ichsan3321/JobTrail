import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/auth/auth_configuration.dart';
import 'package:jobtrail/screens/auth/auth_provider.dart';

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

Future<void> _mount(
  WidgetTester tester,
  _SessionFake provider, {
  AccountHomeBuilder? home,
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
