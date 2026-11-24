import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/data/jobtrail_wire.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/auth/auth_provider.dart';
import 'package:jobtrail/widgets/app_shell.dart';

import 'jobtrail_repository_test.dart' show appId, wire;
import 'support/fake_jobtrail_repository.dart';

JobTrailSnapshot snapshot([String company = 'Synthetic Co']) =>
    JobTrailWire.snapshot(wire(company: company));

JobTrailSnapshot emptySnapshot() => JobTrailSnapshot(
  referenceDate: DateTime.utc(2026, 11, 24),
  referenceInstantUtc: DateTime.utc(2026, 11, 23, 18),
  applications: [],
  agendas: [],
  documents: [],
  history: [],
  applicationRevisions: {},
);

Matcher failsWith(RepositoryIssue issue) => throwsA(
  isA<RepositoryFailure>().having((failure) => failure.issue, 'issue', issue),
);

class TestSession extends UnavailableAuthProvider
    implements SessionAuthProvider {
  final changes = StreamController<AuthSession>.broadcast();
  TestSession({this.displayName, this.email});
  final String? displayName;
  final String? email;
  int signOuts = 0;

  AuthSession signedIn(String owner) => AuthSession.authenticated(
    owner,
    DateTime.now().add(const Duration(hours: 1)),
    displayName: displayName,
    email: email,
  );
  @override
  Stream<AuthSession> get sessionChanges => changes.stream;
  @override
  Future<AuthSession> readSession() async => signedIn('owner-a');
  @override
  Future<void> signOut() async {
    signOuts++;
    changes.add(const AuthSession.signedOut());
  }

  @override
  void dispose() => unawaited(changes.close());
}

Future<void> mount(
  WidgetTester tester,
  TestSession session,
  AccountRepositoryFactory factory,
) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    JobTrailApp(
      authProvider: session,
      repositoryFactory: factory,
      disposeSessionProvider: true,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

void main() {
  test(
    'initial load and retry, empty phase, and server derived data',
    () async {
      final repo = FakeJobTrailRepository(
        () => throw const RepositoryFailure(RepositoryIssue.network),
      );
      final store = JobTrailStore.connected(repo);
      addTearDown(store.dispose);
      expect(store.phase, StorePhase.loading);
      expect(store.applications, isEmpty);
      await store.refresh();
      expect(store.phase, StorePhase.error);
      expect(store.failure?.issue, RepositoryIssue.network);
      repo.read = emptySnapshot;
      await store.refresh();
      expect(store.phase, StorePhase.empty);
      expect(store.hasSnapshot, isTrue);
      repo.read = snapshot;
      await store.refresh();
      expect(store.phase, StorePhase.ready);
      expect(store.referenceDate, DateTime.utc(2026, 11, 24));
      expect(store.referenceInstantUtc, DateTime.utc(2026, 11, 23, 18));
      expect(store.weeklyGoal.target, 8);
      expect(store.weeklyAchieved, 1);
      expect(store.distribution()[RecruitmentStatus.interview], 1);
      expect(store.historyFor(appId).map((h) => h.status), [
        RecruitmentStatus.applied,
        RecruitmentStatus.interview,
      ]);
      expect(store.applicationRevision(appId), 7);
      expect(() => store.documents.clear(), throwsUnsupportedError);
      expect(
        () => store.addApplication(store.applications.single),
        throwsStateError,
      );
      expect(store.applications, hasLength(1));
    },
  );

  test(
    'concurrent reads coalesce and writes publish only reconciled snapshots',
    () async {
      final read = Completer<JobTrailSnapshot>();
      final repo = FakeJobTrailRepository(() => read.future);
      final store = JobTrailStore.connected(repo);
      addTearDown(store.dispose);
      final first = store.refresh();
      expect(identical(store.refresh(), first), isTrue);
      read.complete(snapshot('Before'));
      await first;
      expect(repo.reads, 1);

      final write = Completer<ApplicationReceipt>();
      final committed = Completer<JobTrailSnapshot>();
      repo.status = (_, _, _) => write.future;
      repo.read = () => committed.future;
      final operation = store.changeStatusRemote(
        appId,
        7,
        RecruitmentStatus.offering,
      );
      expect(store.isMutating, isTrue);
      expect(store.applicationById(appId)?.company, 'Before');
      await expectLater(
        store.changeStatusRemote(appId, 7, RecruitmentStatus.offering),
        failsWith(RepositoryIssue.busy),
      );
      write.complete((id: appId, revision: 8));
      await Future<void>.delayed(Duration.zero);
      expect(store.applicationById(appId)?.company, 'Before');
      committed.complete(snapshot('Authoritative'));
      final result = await operation;
      expect(result.receipt.revision, 8);
      expect(result.snapshotCurrent, isTrue);
      expect(store.applicationById(appId)?.company, 'Authoritative');
      expect(store.isMutating, isFalse);
    },
  );

  test('confirmed receipt survives refresh failure and stale data blocks new writes', () async {
    final repo = FakeJobTrailRepository(snapshot);
    final store = JobTrailStore.connected(repo);
    addTearDown(store.dispose);
    await store.refresh();
    repo.status = (_, _, _) => (id: appId, revision: 8);
    repo.read = () => throw const RepositoryFailure(RepositoryIssue.network);
    final result = await store.changeStatusRemote(
      appId,
      7,
      RecruitmentStatus.offering,
    );
    expect(result.snapshotCurrent, isFalse);
    expect(result.receipt.revision, 8);
    expect(store.phase, StorePhase.error);
    expect(store.applicationRevision(appId), 7);
    await expectLater(
      store.changeStatusRemote(appId, 7, RecruitmentStatus.offering),
      failsWith(RepositoryIssue.busy),
    );
    repo.read = snapshot;
    await store.refresh();
    expect(store.phase, StorePhase.ready);
  });

  test(
    'revision conflict reconciles but never reapplies the original mutation',
    () async {
      final repo = FakeJobTrailRepository(snapshot);
      final store = JobTrailStore.connected(repo);
      addTearDown(store.dispose);
      await store.refresh();
      var dispatched = 0;
      repo.status = (_, revision, _) {
        dispatched++;
        expect(revision, 7);
        throw const RepositoryFailure(RepositoryIssue.revisionConflict);
      };
      repo.read = () => snapshot('Newer record');
      await expectLater(
        store.changeStatusRemote(appId, 7, RecruitmentStatus.offering),
        failsWith(RepositoryIssue.revisionConflict),
      );
      expect(dispatched, 1);
      expect(store.applicationById(appId)?.company, 'Newer record');
    },
  );

  test(
    'ambiguous mutation stays unconfirmed even after successful reconciliation',
    () async {
      final repo = FakeJobTrailRepository(snapshot);
      final store = JobTrailStore.connected(repo);
      addTearDown(store.dispose);
      await store.refresh();
      repo.status = (_, _, _) => throw const RepositoryFailure(
        RepositoryIssue.network,
        writeOutcomeUnknown: true,
      );
      await expectLater(
        store.changeStatusRemote(appId, 7, RecruitmentStatus.offering),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.writeOutcomeUnknown,
            'ambiguous',
            true,
          ),
        ),
      );
      expect(repo.reads, 2);
      expect(store.applicationById(appId)?.status, RecruitmentStatus.interview);
    },
  );

  test('authentication loss clears an already displayed snapshot', () async {
    final repo = FakeJobTrailRepository(snapshot);
    final store = JobTrailStore.connected(repo);
    addTearDown(store.dispose);
    await store.refresh();
    repo.read = () =>
        throw const RepositoryFailure(RepositoryIssue.authentication);
    await store.refresh();
    expect(store.phase, StorePhase.error);
    expect(store.hasSnapshot, isFalse);
    expect(store.applications, isEmpty);

    repo.read = snapshot;
    await store.refresh();
    repo.status = (_, _, _) =>
        throw const RepositoryFailure(RepositoryIssue.authentication);
    await expectLater(
      store.changeStatusRemote(appId, 7, RecruitmentStatus.offering),
      failsWith(RepositoryIssue.authentication),
    );
    expect(store.phase, StorePhase.error);
    expect(store.hasSnapshot, isFalse);
    expect(store.applicationRevision(appId), isNull);
  });

  test(
    'dispose discards a late committed response and clears previous owner data',
    () async {
      final repo = FakeJobTrailRepository(snapshot);
      final store = JobTrailStore.connected(repo);
      await store.refresh();
      final pending = Completer<ApplicationReceipt>();
      repo.status = (_, _, _) => pending.future;
      final result = store.changeStatusRemote(
        appId,
        7,
        RecruitmentStatus.offering,
      );
      store.dispose();
      pending.complete((id: appId, revision: 8));
      await expectLater(result, failsWith(RepositoryIssue.authentication));
      expect(store.applications, isEmpty);
      expect(repo.disposed, isTrue);
      expect(repo.reads, 1);
    },
  );

  testWidgets(
    'backend AppShell loads after retry, supports empty and prevents local writes',
    (tester) async {
      final session = TestSession();
      final repo = FakeJobTrailRepository(
        () => throw const RepositoryFailure(RepositoryIssue.network),
      );
      await mount(tester, session, (_) => repo);
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsNothing);
      expect(find.text('Coba lagi'), findsOneWidget);
      repo.read = emptySnapshot;
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.textContaining('Akun ini belum memiliki'), findsNothing);
      expect(find.textContaining('Baca saja'), findsNothing);
      expect(find.text('Belum ada lamaran.'), findsOneWidget);
      expect(find.text('0 dari 8 lamaran'), findsOneWidget);
      expect(find.textContaining('Streak belum tersedia'), findsNothing);
      expect(find.text('Keluar'), findsNothing);
      final add = tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('home-add')),
      );
      expect(add.onPressed, isNull);
      expect(add.tooltip, 'Tambah lamaran belum tersedia untuk akun ini');
      await tester.tap(find.byKey(const ValueKey('home-add')));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      expect(repo.reads, 2);
      await tester.tap(find.byTooltip('Buka menu akun'));
      await tester.pumpAndSettle();
      expect(find.text('Akun JobTrail'), findsOneWidget);
      await tester.tap(find.text('Keluar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya, keluar'));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsNothing);
      expect(repo.disposed, isTrue);
    },
  );

  testWidgets('account sheet shows identity and refreshes with retry', (
    tester,
  ) async {
    final session = TestSession(
      displayName: 'Ayu Pratama',
      email: 'ayu@example.invalid',
    );
    final repo = FakeJobTrailRepository(emptySnapshot);
    await mount(tester, session, (_) => repo);
    await tester.pumpAndSettle();
    expect(find.text('Selamat datang, Ayu Pratama'), findsOneWidget);
    expect(find.text('ayu@example.invalid'), findsNothing);
    expect(find.text('Muat ulang data'), findsNothing);
    await tester.tap(find.byTooltip('Buka menu akun'));
    await tester.pumpAndSettle();
    expect(find.text('Ayu Pratama'), findsOneWidget);
    expect(find.text('ayu@example.invalid'), findsOneWidget);
    expect(find.text('Terhubung ke JobTrail'), findsOneWidget);

    final read = Completer<JobTrailSnapshot>();
    repo.read = () => read.future;
    await tester.tap(find.text('Muat ulang data'));
    await tester.pump();
    expect(find.text('Memuat ulang data akun…'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text('Muat ulang data'),
              matching: find.byType(ListTile),
            ),
          )
          .enabled,
      isFalse,
    );
    read.completeError(const RepositoryFailure(RepositoryIssue.network));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sinkronisasi gagal.'), findsOneWidget);
    expect(repo.reads, 2);
    repo.read = emptySnapshot;
    await tester.tap(find.text('Muat ulang data'));
    await tester.pumpAndSettle();
    expect(find.text('Terhubung ke JobTrail'), findsOneWidget);
    expect(repo.reads, 3);
  });

  testWidgets('logout cancel keeps session and account switch clears dialog', (
    tester,
  ) async {
    final session = TestSession(email: 'old@example.invalid');
    final old = FakeJobTrailRepository(emptySnapshot);
    final fresh = FakeJobTrailRepository(emptySnapshot);
    await mount(tester, session, (id) => id == 'owner-a' ? old : fresh);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buka menu akun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(session.signOuts, 0);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('old@example.invalid'), findsOneWidget);
    expect(session.signOuts, 0);

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari JobTrail?'), findsOneWidget);
    session.changes.add(
      AuthSession.authenticated(
        'owner-b',
        DateTime.now().add(const Duration(hours: 1)),
        email: 'new@example.invalid',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari JobTrail?'), findsNothing);
    expect(find.text('old@example.invalid'), findsNothing);
    expect(old.disposed, isTrue);
    await tester.tap(find.byTooltip('Buka menu akun'));
    await tester.pumpAndSettle();
    expect(find.text('new@example.invalid'), findsOneWidget);
    expect(session.signOuts, 0);
  });

  testWidgets('mock Home keeps the brand and has no connected account menu', (
    tester,
  ) async {
    await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Buka menu akun'), findsNothing);
    expect(find.byTooltip('Tambah Lamaran'), findsOneWidget);
  });

  testWidgets(
    'switch during loading never applies the previous account snapshot',
    (tester) async {
      final session = TestSession();
      final pending = Completer<JobTrailSnapshot>();
      final old = FakeJobTrailRepository(() => pending.future);
      final fresh = FakeJobTrailRepository(
        () => snapshot('Second account marker'),
      );
      await mount(tester, session, (id) => id == 'owner-a' ? old : fresh);
      expect(find.text('Memuat data JobTrail'), findsOneWidget);
      session.changes.add(session.signedIn('owner-b'));
      await tester.pumpAndSettle();
      expect(old.disposed, isTrue);
      expect(find.text('Second account marker'), findsWidgets);
      pending.complete(snapshot('Previous account marker'));
      await tester.pumpAndSettle();
      expect(find.text('Previous account marker'), findsNothing);
      expect(find.text('Second account marker'), findsWidgets);
    },
  );

  testWidgets('logout during initial request invalidates its eventual result', (
    tester,
  ) async {
    final session = TestSession();
    final pending = Completer<JobTrailSnapshot>();
    final repo = FakeJobTrailRepository(() => pending.future);
    await mount(tester, session, (_) => repo);
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    pending.complete(snapshot('Must never display'));
    await tester.pumpAndSettle();
    expect(repo.disposed, isTrue);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('Must never display'), findsNothing);
  });
}
