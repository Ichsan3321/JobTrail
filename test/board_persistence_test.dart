import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/constants/app_tokens.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/models/status_history.dart';
import 'package:jobtrail/widgets/app_shell.dart';

import 'support/fake_jobtrail_repository.dart';

/// S02 Board persistence (W13-011/012/014) against the scripted fake
/// repository: no network, no credentials.
const _appId = '10000000-0000-4000-8000-0000000000b2';

JobTrailSnapshot _snapshot({
  RecruitmentStatus status = RecruitmentStatus.interview,
  int revision = 7,
  String company = 'Board Synthetic',
  List<Application> extra = const [],
}) {
  final history = [
    StatusHistory(
      id: 'evt-applied',
      applicationId: _appId,
      status: RecruitmentStatus.applied,
      changedAt: DateTime.utc(2026, 11, 20, 2),
    ),
    if (status != RecruitmentStatus.applied)
      StatusHistory(
        id: 'evt-${status.name}',
        applicationId: _appId,
        status: status,
        changedAt: DateTime.utc(2026, 11, 23, 2),
      ),
  ];
  return JobTrailSnapshot(
    referenceDate: DateTime.utc(2026, 11, 24),
    referenceInstantUtc: DateTime.utc(2026, 11, 24, 2),
    applications: [
      Application(
        id: _appId,
        company: company,
        position: 'Mobile Intern',
        source: 'Website perusahaan',
        appliedAt: DateTime.utc(2026, 11, 20),
        status: status,
        location: 'Surabaya',
        workType: WorkType.hybrid,
      ),
      ...extra,
    ],
    agendas: const [],
    documents: const [],
    history: history,
    applicationRevisions: {
      _appId: revision,
      for (final app in extra) app.id: 1,
    },
  );
}

typedef _StatusCall = ({String id, int revision, RecruitmentStatus status});

class _Harness {
  _Harness() : repo = FakeJobTrailRepository(_snapshot) {
    store = JobTrailStore.connected(repo);
    repo.status = (id, revision, status) {
      calls.add((id: id, revision: revision, status: status));
      return onStatus(id, revision, status);
    };
  }

  final FakeJobTrailRepository repo;
  late final JobTrailStore store;
  final calls = <_StatusCall>[];
  late FutureOr<ApplicationReceipt> Function(String, int, RecruitmentStatus)
  onStatus;
}

Future<_Harness> _openPreview(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = _Harness();
  addTearDown(h.store.dispose);
  await h.store.refresh();
  expect(h.store.phase, StorePhase.ready);
  await tester.pumpWidget(
    JobTrailApp(showAuthentication: false, store: h.store),
  );
  await tester.tap(find.byKey(const ValueKey('nav-board')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('application-$_appId')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('board-preview-status')), findsOneWidget);
  return h;
}

Future<void> _pickStatus(WidgetTester tester, RecruitmentStatus status) async {
  await tester.tap(find.byKey(const ValueKey('board-preview-status')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('board-status-${status.name}')));
  await tester.pump();
}

/// Text of the status chip at the top of the preview sheet.
Finder _previewChip(RecruitmentStatus status) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(status.label),
);

void main() {
  testWidgets('W13-011: Ubah Status writes remotely with the captured revision '
      'and shows the reconciled server status', (tester) async {
    final h = await _openPreview(tester);
    h.onStatus = (id, _, status) {
      h.repo.read = () => _snapshot(status: status, revision: 8);
      return (id: id, revision: 8);
    };

    await _pickStatus(tester, RecruitmentStatus.offering);
    await tester.pumpAndSettle();

    expect(h.calls, [
      (id: _appId, revision: 7, status: RecruitmentStatus.offering),
    ]);
    expect(h.store.applicationById(_appId)?.status, RecruitmentStatus.offering);
    expect(h.store.applicationRevision(_appId), 8);
    // History comes from the server snapshot only: no local duplicate event.
    expect(h.store.historyFor(_appId).map((e) => e.status), [
      RecruitmentStatus.applied,
      RecruitmentStatus.offering,
    ]);
    expect(_previewChip(RecruitmentStatus.offering), findsOneWidget);
    expect(find.byKey(const ValueKey('board-preview-error')), findsNothing);
  });

  testWidgets('W13-014: revision captured when the intent opens is sent even '
      'if a refresh lands meanwhile; conflict keeps server data', (
    tester,
  ) async {
    final h = await _openPreview(tester);
    h.onStatus = (_, _, _) =>
        throw const RepositoryFailure(RepositoryIssue.revisionConflict);

    await tester.tap(find.byKey(const ValueKey('board-preview-status')));
    await tester.pumpAndSettle();
    // Another device changed the record; a background refresh lands while
    // the picker is open.
    h.repo.read = () =>
        _snapshot(status: RecruitmentStatus.screening, revision: 9);
    await h.store.refresh();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('board-status-offering')));
    await tester.pumpAndSettle();

    expect(h.calls.single.revision, 7, reason: 'never the silently newer 9');
    expect(
      h.store.applicationById(_appId)?.status,
      RecruitmentStatus.screening,
    );
    expect(_previewChip(RecruitmentStatus.screening), findsOneWidget);
    expect(
      find.textContaining('Data telah berubah'),
      findsOneWidget,
      reason: 'conflict is reported, server version is not overwritten',
    );
  });

  testWidgets('W13-014: choosing the same status sends nothing and adds no '
      'history', (tester) async {
    final h = await _openPreview(tester);
    h.onStatus = (_, _, _) => fail('same status must not be written');
    final readsBefore = h.repo.reads;

    await _pickStatus(tester, RecruitmentStatus.interview);
    await tester.pumpAndSettle();

    expect(h.calls, isEmpty);
    expect(h.repo.reads, readsBefore);
    expect(h.store.historyFor(_appId), hasLength(2));
  });

  testWidgets('W13-014: double tap while a write is pending dispatches once', (
    tester,
  ) async {
    final h = await _openPreview(tester);
    final pending = Completer<ApplicationReceipt>();
    h.onStatus = (_, _, _) => pending.future;

    await _pickStatus(tester, RecruitmentStatus.rejected);
    // Let the picker finish closing; the write itself is still pending.
    await tester.pumpAndSettle();
    expect(h.store.isMutating, isTrue);
    expect(find.text('Menyimpan…'), findsOneWidget);

    // Button is disabled: further taps open no picker and send nothing.
    await tester.tap(
      find.byKey(const ValueKey('board-preview-status')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-status-offering')), findsNothing);

    h.repo.read = () =>
        _snapshot(status: RecruitmentStatus.rejected, revision: 8);
    pending.complete((id: _appId, revision: 8));
    await tester.pumpAndSettle();

    expect(h.calls, hasLength(1));
    expect(h.store.isMutating, isFalse);
    expect(find.text('Ubah Status'), findsOneWidget);
  });

  testWidgets('W13-014: unknown write outcome is not reported as success', (
    tester,
  ) async {
    final h = await _openPreview(tester);
    h.onStatus = (_, _, _) => throw const RepositoryFailure(
      RepositoryIssue.network,
      writeOutcomeUnknown: true,
    );
    final readsBefore = h.repo.reads;

    await _pickStatus(tester, RecruitmentStatus.offering);
    await tester.pumpAndSettle();

    expect(h.calls, hasLength(1), reason: 'no automatic retry');
    expect(h.repo.reads, readsBefore + 1, reason: 'store reconciled');
    expect(find.textContaining('belum dapat dipastikan'), findsOneWidget);
    expect(
      h.store.applicationById(_appId)?.status,
      RecruitmentStatus.interview,
    );
  });

  testWidgets('W13-014: committed write with a failed reconcile says so and '
      'refreshes instead of writing again', (tester) async {
    final h = await _openPreview(tester);
    h.onStatus = (id, _, _) {
      h.repo.read = () =>
          throw const RepositoryFailure(RepositoryIssue.network);
      return (id: id, revision: 8);
    };
    final readsBefore = h.repo.reads;

    await _pickStatus(tester, RecruitmentStatus.offering);
    await tester.pumpAndSettle();

    expect(h.calls, hasLength(1));
    expect(find.byKey(const ValueKey('board-preview-notice')), findsOneWidget);
    expect(find.textContaining('Status tersimpan di server'), findsOneWidget);
    // Reconcile read + the follow-up refresh; never a second write.
    expect(h.repo.reads, readsBefore + 2);
  });

  testWidgets('W13-012: Board follows the reconciled snapshot and keeps the '
      'active filter', (tester) async {
    final h = await _openPreview(tester);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();

    final pill = find.byKey(const ValueKey('board-pill-interview'));
    await tester.ensureVisible(pill);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('application-$_appId')), findsOneWidget);

    h.repo.read = () => _snapshot(company: 'Renamed On Server', revision: 8);
    await h.store.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Renamed On Server'), findsOneWidget);

    h.repo.read = () =>
        _snapshot(status: RecruitmentStatus.offering, revision: 9);
    await h.store.refresh();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('application-$_appId')),
      findsNothing,
      reason: 'Interview filter still applied to the new snapshot',
    );
    expect(find.byKey(const ValueKey('board-no-match')), findsOneWidget);
  });

  testWidgets('W13-012: Buka Detail opens the same ID from the snapshot', (
    tester,
  ) async {
    await _openPreview(tester);
    await tester.tap(find.byKey(const ValueKey('board-preview-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(find.text('Board Synthetic'), findsWidgets);
  });

  testWidgets('W13-013: a receipt ID that arrives in the server snapshot is '
      'revealed through a filter that would hide it', (tester) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeJobTrailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    addTearDown(store.dispose);
    await store.refresh();
    final navigation = AppNavigation(store);
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigation.navigatorKey,
        home: AppShell(store: store, navigation: navigation),
      ),
    );
    navigation.showTab(AppTab.board);
    await tester.pumpAndSettle();

    final offering = find.byKey(const ValueKey('board-pill-offering'));
    await tester.ensureVisible(offering);
    await tester.tap(offering);
    await tester.pumpAndSettle();

    // S04 (Rifqi) awaits the create receipt and only hands the ID over once
    // the reconciled snapshot contains it; simulate that hand-over here.
    const receiptId = '10000000-0000-4000-8000-0000000000b3';
    repo.read = () => _snapshot(
      extra: [
        Application(
          id: receiptId,
          company: 'Receipt Studio',
          position: 'Integration Intern',
          source: 'LinkedIn',
          appliedAt: DateTime.utc(2026, 11, 24),
          status: RecruitmentStatus.applied,
          location: 'Surabaya',
          workType: WorkType.remote,
        ),
      ],
    );
    await store.refresh();
    expect(store.applicationById(receiptId), isNotNull);
    navigation.showTab(AppTab.board, applicationId: receiptId);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('application-$receiptId')).hitTestable(),
      findsOneWidget,
    );
  });

  group('PR #18 review', () {
    testWidgets('disabled Add looks and announces itself as unavailable', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _openPreview(tester);
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      // Tooltip may merge its message into the label, so match by pattern.
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('Tambah Lamaran'))),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('board-add')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, AppColors.border);
      expect(find.byTooltip('Tambah lamaran belum tersedia'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('board-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S04')), findsNothing);
      semantics.dispose();
    });

    testWidgets('stale/error snapshot blocks Ubah Status until reloaded', (
      tester,
    ) async {
      final h = await _openPreview(tester);
      h.onStatus = (id, _, _) => (id: id, revision: 8);
      h.repo.read = () =>
          throw const RepositoryFailure(RepositoryIssue.network);
      await h.store.refresh();
      await tester.pumpAndSettle();
      expect(h.store.phase, StorePhase.error);

      expect(find.textContaining('Data belum terbaru'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('board-preview-status')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('board-status-offering')), findsNothing);
      expect(h.calls, isEmpty);

      h.repo.read = _snapshot;
      await tester.tap(find.byKey(const ValueKey('board-preview-retry')));
      await tester.pumpAndSettle();
      expect(h.store.phase, StorePhase.ready);
      expect(find.byKey(const ValueKey('board-preview-notice')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('board-preview-status')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('board-status-offering')),
        findsOneWidget,
      );
    });

    testWidgets('a mutation already running elsewhere blocks Ubah Status', (
      tester,
    ) async {
      final h = await _openPreview(tester);
      final pending = Completer<ApplicationReceipt>();
      h.onStatus = (_, _, _) => pending.future;
      final other = h.store.changeStatusRemote(
        _appId,
        7,
        RecruitmentStatus.screening,
      );
      await tester.pump();
      expect(h.store.isMutating, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('board-preview-status')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('board-status-offering')), findsNothing);
      expect(h.calls, hasLength(1), reason: 'only the other mutation');

      h.repo.read = () =>
          _snapshot(status: RecruitmentStatus.screening, revision: 8);
      pending.complete((id: _appId, revision: 8));
      await other;
      await tester.pumpAndSettle();
      expect(find.text('Ubah Status'), findsOneWidget);
    });

    testWidgets('conflict with a failed reconcile does not claim latest data', (
      tester,
    ) async {
      final h = await _openPreview(tester);
      h.onStatus = (_, _, _) {
        h.repo.read = () =>
            throw const RepositoryFailure(RepositoryIssue.network);
        throw const RepositoryFailure(RepositoryIssue.revisionConflict);
      };

      await _pickStatus(tester, RecruitmentStatus.offering);
      await tester.pumpAndSettle();

      expect(h.store.phase, StorePhase.error);
      expect(find.textContaining('versi terbaru dari server'), findsNothing);
      expect(
        find.textContaining('versi terbaru belum berhasil dimuat'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('board-preview-retry')), findsOneWidget);
    });

    testWidgets('unknown outcome with a failed reconcile does not point at '
        'stale data', (tester) async {
      final h = await _openPreview(tester);
      h.onStatus = (_, _, _) {
        h.repo.read = () =>
            throw const RepositoryFailure(RepositoryIssue.network);
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      };

      await _pickStatus(tester, RecruitmentStatus.offering);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Periksa status terbaru di atas'),
        findsNothing,
      );
      expect(find.textContaining('belum berhasil dimuat'), findsOneWidget);
    });

    testWidgets('committed notice clears once the follow-up reload succeeds', (
      tester,
    ) async {
      final h = await _openPreview(tester);
      var readsAfterWrite = 0;
      h.onStatus = (id, _, _) {
        h.repo.read = () {
          readsAfterWrite++;
          if (readsAfterWrite == 1) {
            throw const RepositoryFailure(RepositoryIssue.network);
          }
          return _snapshot(status: RecruitmentStatus.offering, revision: 8);
        };
        return (id: id, revision: 8);
      };

      await _pickStatus(tester, RecruitmentStatus.offering);
      await tester.pumpAndSettle();

      expect(readsAfterWrite, 2, reason: 'failed reconcile + reload');
      expect(h.calls, hasLength(1), reason: 'never written twice');
      expect(find.byKey(const ValueKey('board-preview-notice')), findsNothing);
      expect(_previewChip(RecruitmentStatus.offering), findsOneWidget);
    });

    testWidgets('committed notice offers retry while reload keeps failing', (
      tester,
    ) async {
      final h = await _openPreview(tester);
      h.onStatus = (id, _, _) {
        h.repo.read = () =>
            throw const RepositoryFailure(RepositoryIssue.network);
        return (id: id, revision: 8);
      };

      await _pickStatus(tester, RecruitmentStatus.offering);
      await tester.pumpAndSettle();
      expect(
        find.text('Status tersimpan di server, tetapi data belum termuat.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('board-preview-retry')), findsOneWidget);

      h.repo.read = () =>
          _snapshot(status: RecruitmentStatus.offering, revision: 8);
      await tester.tap(find.byKey(const ValueKey('board-preview-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('board-preview-notice')), findsNothing);
      expect(h.calls, hasLength(1));
    });

    testWidgets('no dispatch when the preview is no longer the current route '
        'after the picker closes', (tester) async {
      final h = await _openPreview(tester);
      h.onStatus = (id, _, _) => fail('must not dispatch from a covered route');

      await tester.tap(find.byKey(const ValueKey('board-preview-status')));
      await tester.pumpAndSettle();
      final pickerContext = tester.element(
        find.byKey(const ValueKey('board-status-offering')),
      );
      final pickerRoute = ModalRoute.of(pickerContext)!;
      final navigator = Navigator.of(pickerContext);

      // Something else (e.g. an account/route change) lands on top...
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // ...and the picker is then resolved with a status underneath it.
      navigator.removeRoute(pickerRoute, RecruitmentStatus.offering);
      await tester.pumpAndSettle();

      expect(h.calls, isEmpty);
      expect(find.text('Other route'), findsOneWidget);
    });
  });
}
