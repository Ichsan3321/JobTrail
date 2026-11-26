import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/constants/app_dates.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/data/jobtrail_wire.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/widgets/app_shell.dart';
import 'package:jobtrail/widgets/status_chip.dart';

import 'application_detail_screen_test.dart'
    show
        deleteConfirmation,
        detailScrollable,
        mountApp,
        openDeleteDialog,
        openDetail,
        openStatusSheet,
        statusOption;
import 'jobtrail_persistence_test.dart' show TestSession, mount;
import 'jobtrail_repository_test.dart' show appId, documentId, wire;
import 'support/fake_jobtrail_repository.dart';

class _DetailRepository extends FakeJobTrailRepository {
  _DetailRepository(super.read);

  FutureOr<String> Function(String, int)? delete;
  final deleteCalls = <({String id, int revision})>[];

  @override
  Future<String> deleteApplication(String id, int revision) async {
    deleteCalls.add((id: id, revision: revision));
    final handleDelete = delete;
    return handleDelete == null
        ? super.deleteApplication(id, revision)
        : handleDelete(id, revision);
  }
}

JobTrailSnapshot _snapshot({
  String company = 'Synthetic Co',
  RecruitmentStatus status = RecruitmentStatus.interview,
  int revision = 7,
  bool deleted = false,
}) {
  final data = wire(company: company);
  if (deleted) {
    return JobTrailWire.snapshot({
      ...data,
      'applications': [],
      'agendas': [],
      'history': [],
      'application_documents': [],
    });
  }
  data['applications'] = [
    {
      ...JobTrailWire.rows(data, 'applications').single,
      'revision': revision,
      'status': status.name,
    },
  ];
  if (status != RecruitmentStatus.interview) {
    data['history'] = [
      {
        ...JobTrailWire.rows(data, 'history').first,
        'id': '40000000-0000-4000-8000-000000000003',
        'event_no': 3,
        'status': status.name,
      },
      ...JobTrailWire.rows(data, 'history'),
    ];
  }
  return JobTrailWire.snapshot(data);
}

Future<AppNavigation> _openConnected(
  WidgetTester tester,
  JobTrailStore store, {
  String id = appId,
}) async {
  final navigation = await mountApp(tester, store);
  await store.refresh();
  await tester.pumpAndSettle();
  await openDetail(tester, navigation, id);
  return navigation;
}

Future<void> _selectOffering(WidgetTester tester) async {
  await openStatusSheet(tester);
  await tester.tap(statusOption(RecruitmentStatus.offering));
  await tester.pumpAndSettle();
}

Future<void> _saveStatus(WidgetTester tester) async {
  await tester.tap(find.text('Simpan Status'));
  await tester.pumpAndSettle();
}

final _preview = find.byKey(const ValueKey('document-preview-sheet'));

Future<void> _openPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('detail-document-$documentId')));
  await tester.pumpAndSettle();
  expect(_preview, findsOneWidget);
}

Future<void> _closePreview(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Tutup'));
  await tester.pumpAndSettle();
  expect(_preview, findsNothing);
}

RecruitmentStatus _currentStatus(WidgetTester tester) => tester
    .widget<StatusChip>(find.byKey(const ValueKey('detail-current-status')))
    .status;

void main() {
  testWidgets(
    'status waits for the receipt and publishes ordered history once',
    (tester) async {
      var server = _snapshot();
      final repo = _DetailRepository(() => server);
      final store = JobTrailStore.connected(repo);
      final write = Completer<ApplicationReceipt>();
      final calls = <(String, int, RecruitmentStatus)>[];
      repo.status = (id, revision, status) {
        calls.add((id, revision, status));
        return write.future;
      };
      await _openConnected(tester, store);
      await _selectOffering(tester);

      final submit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Simpan Status'),
          )
          .onPressed!;
      submit();
      submit();
      await tester.pumpAndSettle();
      expect(calls, [(appId, 7, RecruitmentStatus.offering)]);
      expect(_currentStatus(tester), RecruitmentStatus.interview);
      expect(store.historyFor(appId), hasLength(2));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Ubah Status'),
            )
            .onPressed,
        isNull,
      );

      server = _snapshot(status: RecruitmentStatus.offering, revision: 8);
      write.complete((id: appId, revision: 8));
      await tester.pumpAndSettle();
      expect(_currentStatus(tester), RecruitmentStatus.offering);

      // A subsequent refresh and a same-status write return the same events.
      await store.refresh();
      await tester.pumpAndSettle();
      repo.status = (id, revision, status) {
        calls.add((id, revision, status));
        return (id: id, revision: revision);
      };
      await openStatusSheet(tester);
      await _saveStatus(tester);
      expect(calls.last, (appId, 8, RecruitmentStatus.offering));
      final events = store.historyFor(appId);
      expect(events.map((event) => event.changedAt).toSet(), hasLength(1));
      expect(events.map((event) => event.status), [
        RecruitmentStatus.applied,
        RecruitmentStatus.interview,
        RecruitmentStatus.offering,
      ]);
      final rows = [
        for (final event in events)
          find.text(
            '${event.status.label}\n${AppDates.formatWib(event.changedAt)}',
          ),
      ];
      await tester.scrollUntilVisible(
        rows.last,
        140,
        scrollable: detailScrollable(),
      );
      for (final row in rows) {
        expect(row, findsOneWidget);
      }
      expect(
        tester.getTopLeft(rows.first).dy,
        lessThan(tester.getTopLeft(rows[1]).dy),
      );
      expect(
        tester.getTopLeft(rows[1]).dy,
        lessThan(tester.getTopLeft(rows.last).dy),
      );
      expect(find.text('Saat ini'), findsOneWidget);
    },
  );

  testWidgets('status reconciles under Preview and reports after dismissal', (
    tester,
  ) async {
    final repo = _DetailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    final receipt = Completer<ApplicationReceipt>();
    final refreshed = Completer<JobTrailSnapshot>();
    var writes = 0;
    repo.status = (_, _, _) {
      writes++;
      return receipt.future;
    };
    await _openConnected(tester, store);
    await _selectOffering(tester);
    await _saveStatus(tester);
    await _openPreview(tester);

    var readsAfterCommit = 0;
    repo.read = () {
      if (++readsAfterCommit == 1) {
        throw const RepositoryFailure(RepositoryIssue.network);
      }
      return refreshed.future;
    };
    receipt.complete((id: appId, revision: 8));
    await tester.pumpAndSettle();

    expect(readsAfterCommit, 2);
    expect(store.isRefreshing, isTrue);
    expect(store.applicationById(appId)?.status, RecruitmentStatus.interview);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

    refreshed.complete(
      _snapshot(status: RecruitmentStatus.offering, revision: 8),
    );
    await tester.pumpAndSettle();
    expect(store.applicationById(appId)?.status, RecruitmentStatus.offering);
    expect(_preview, findsOneWidget);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(writes, 1);

    await _closePreview(tester);
    expect(_currentStatus(tester), RecruitmentStatus.offering);
    expect(find.textContaining('Data telah dimuat ulang.'), findsOneWidget);
    expect(writes, 1);
  });

  testWidgets('confirmed status retains its receipt through manual reload', (
    tester,
  ) async {
    final repo = _DetailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    var writes = 0;
    repo.status = (id, revision, _) {
      writes++;
      repo.read = () => throw const RepositoryFailure(RepositoryIssue.network);
      return (id: id, revision: revision + 1);
    };
    await _openConnected(tester, store);
    final previousReads = repo.reads;
    await _selectOffering(tester);
    await _saveStatus(tester);

    expect(writes, 1);
    expect(repo.reads, previousReads + 2);
    expect(_currentStatus(tester), RecruitmentStatus.interview);
    expect(store.applicationRevision(appId), 7);
    expect(find.textContaining('Data terbaru belum tersedia.'), findsOneWidget);
    expect(find.textContaining('Data telah dimuat ulang.'), findsNothing);

    repo.read = () =>
        _snapshot(status: RecruitmentStatus.screening, revision: 9);
    await tester.tap(find.text('Muat ulang'));
    await tester.pumpAndSettle();

    expect(writes, 1);
    expect(repo.reads, previousReads + 3);
    expect(_currentStatus(tester), RecruitmentStatus.screening);
    expect(store.applicationRevision(appId), 9);
    expect(find.textContaining('Data telah dimuat ulang.'), findsOneWidget);
  });

  testWidgets(
    'unknown status outcome uses the snapshot without claiming success',
    (tester) async {
      final repo = _DetailRepository(_snapshot);
      final store = JobTrailStore.connected(repo);
      var writes = 0;
      repo.status = (_, _, _) {
        writes++;
        repo.read = () =>
            _snapshot(status: RecruitmentStatus.screening, revision: 8);
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      };
      await _openConnected(tester, store);
      final previousReads = repo.reads;
      await _selectOffering(tester);
      await _saveStatus(tester);

      expect(writes, 1);
      expect(repo.reads, previousReads + 1);
      expect(_currentStatus(tester), RecruitmentStatus.screening);
      expect(store.historyFor(appId).last.status, RecruitmentStatus.screening);
      expect(
        find.textContaining('Hasil perubahan belum dapat dipastikan.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Perubahan status diterima server.'),
        findsNothing,
      );
    },
  );

  testWidgets('a rejected status write keeps the application snapshot', (
    tester,
  ) async {
    final repo = _DetailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    await _openConnected(tester, store);
    await _selectOffering(tester);
    await _saveStatus(tester);
    expect(
      find.textContaining(RepositoryIssue.forbidden.message),
      findsOneWidget,
    );
    expect(_currentStatus(tester), RecruitmentStatus.interview);
    expect(store.historyFor(appId), hasLength(2));
  });

  testWidgets('status submits the revision captured before a refresh', (
    tester,
  ) async {
    var server = _snapshot();
    final repo = _DetailRepository(() => server);
    final store = JobTrailStore.connected(repo);
    final revisions = <int>[];
    repo.status = (_, revision, _) {
      revisions.add(revision);
      throw const RepositoryFailure(RepositoryIssue.revisionConflict);
    };
    await _openConnected(tester, store);
    await _selectOffering(tester);
    server = _snapshot(status: RecruitmentStatus.screening, revision: 8);
    await store.refresh();
    await tester.pumpAndSettle();
    await _saveStatus(tester);
    expect(revisions, [7]);
    expect(store.applicationRevision(appId), 8);
    expect(_currentStatus(tester), RecruitmentStatus.screening);
    expect(find.textContaining('Data lamaran telah berubah.'), findsOneWidget);

    await openStatusSheet(tester);
    expect(
      tester
          .widget<RadioGroup<RecruitmentStatus>>(
            find.byType(RadioGroup<RecruitmentStatus>),
          )
          .groupValue,
      RecruitmentStatus.offering,
    );
    expect(revisions, [7]);
  });

  testWidgets(
    'delete conflict uses the original revision and retains relations',
    (tester) async {
      var server = _snapshot();
      final repo = _DetailRepository(() => server);
      repo.delete = (_, _) =>
          throw const RepositoryFailure(RepositoryIssue.revisionConflict);
      final store = JobTrailStore.connected(repo);
      final navigation = await _openConnected(tester, store);
      await openDeleteDialog(tester);
      server = _snapshot(revision: 8);
      await store.refresh();
      await tester.pumpAndSettle();
      await tester.tap(deleteConfirmation());
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, [(id: appId, revision: 7)]);
      expect(store.applicationRevision(appId), 8);
      expect(store.agendasFor(appId), hasLength(1));
      expect(store.historyFor(appId), hasLength(2));
      expect(store.applicationById(appId)!.documentIds, [documentId]);
      expect(navigation.selectedTab, AppTab.home);
      expect(
        find.textContaining('Data lamaran telah berubah.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('delete failure keeps the application on Detail', (tester) async {
    final repo = _DetailRepository(_snapshot);
    repo.delete = (_, _) =>
        throw const RepositoryFailure(RepositoryIssue.forbidden);
    final store = JobTrailStore.connected(repo);
    await _openConnected(tester, store);
    await openDeleteDialog(tester);
    await tester.tap(deleteConfirmation());
    await tester.pumpAndSettle();
    expect(repo.deleteCalls, [(id: appId, revision: 7)]);
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(
      find.textContaining(RepositoryIssue.forbidden.message),
      findsOneWidget,
    );
    expect(store.applicationById(appId), isNotNull);
    expect(store.agendasFor(appId), hasLength(1));
    expect(store.historyFor(appId), hasLength(2));
    expect(store.documentById(documentId), isNotNull);
  });

  testWidgets('delete skips the RPC when refresh removed the ID', (
    tester,
  ) async {
    final repo = _DetailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    final navigation = await _openConnected(tester, store);
    await openDeleteDialog(tester);

    repo.read = () => _snapshot(deleted: true);
    await store.refresh();
    await tester.pumpAndSettle();
    await tester.tap(deleteConfirmation());
    await tester.pumpAndSettle();

    expect(repo.deleteCalls, isEmpty);
    expect(navigation.selectedTab, AppTab.home);
    expect(find.textContaining('Lamaran tidak ditemukan'), findsOneWidget);
    expect(
      find.textContaining(RepositoryIssue.unavailable.message),
      findsOneWidget,
    );
  });

  testWidgets(
    'confirmed cascade waits for a fresh read and keeps document metadata',
    (tester) async {
      final repo = _DetailRepository(_snapshot);
      final store = JobTrailStore.connected(repo);
      final navigation = await _openConnected(tester, store);
      repo.delete = (id, _) {
        repo.read = () =>
            throw const RepositoryFailure(RepositoryIssue.network);
        return id;
      };
      await openDeleteDialog(tester);
      final confirm = tester
          .widget<FilledButton>(deleteConfirmation())
          .onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, [(id: appId, revision: 7)]);
      expect(navigation.selectedTab, AppTab.home);
      expect(store.applicationById(appId), isNotNull);
      expect(
        find.textContaining('Penghapusan diterima server.'),
        findsOneWidget,
      );

      repo.read = () => _snapshot(deleted: true);
      await tester.tap(find.text('Muat ulang'));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, hasLength(1));
      expect(find.byKey(const ValueKey('S02')), findsOneWidget);
      expect(find.byKey(const ValueKey('S03')), findsNothing);
      expect(store.applicationById(appId), isNull);
      expect(store.agendasFor(appId), isEmpty);
      expect(store.historyFor(appId), isEmpty);
      expect(store.applications.expand((app) => app.documentIds), isEmpty);
      expect(store.documentById(documentId), isNotNull);
    },
  );

  testWidgets(
    'confirmed delete reconciles under Preview before opening Board',
    (tester) async {
      final repo = _DetailRepository(_snapshot);
      final store = JobTrailStore.connected(repo);
      final navigation = await _openConnected(tester, store);
      final receipt = Completer<String>();
      repo.delete = (_, _) => receipt.future;

      await openDeleteDialog(tester);
      await tester.tap(deleteConfirmation());
      await tester.pumpAndSettle();
      expect(store.isMutating, isTrue);
      await _openPreview(tester);

      var readsAfterCommit = 0;
      repo.read = () {
        if (++readsAfterCommit == 1) {
          throw const RepositoryFailure(RepositoryIssue.network);
        }
        return _snapshot(deleted: true);
      };
      receipt.complete(appId);
      await tester.pumpAndSettle();

      expect(readsAfterCommit, 2);
      expect(repo.deleteCalls, [(id: appId, revision: 7)]);
      expect(store.applicationById(appId), isNull);
      expect(navigation.selectedTab, AppTab.home);
      expect(_preview, findsOneWidget);
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

      await _closePreview(tester);
      expect(navigation.selectedTab, AppTab.board);
      expect(find.byKey(const ValueKey('S03')), findsNothing);
      expect(store.agendasFor(appId), isEmpty);
      expect(store.historyFor(appId), isEmpty);
      expect(store.documentById(documentId), isNotNull);
    },
  );

  testWidgets(
    'unknown delete outcome reconciles without a replay or success claim',
    (tester) async {
      final repo = _DetailRepository(_snapshot);
      final store = JobTrailStore.connected(repo);
      final navigation = await _openConnected(tester, store);
      repo.delete = (_, _) {
        repo.read = () => _snapshot(deleted: true);
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      };
      final previousReads = repo.reads;
      await openDeleteDialog(tester);
      await tester.tap(deleteConfirmation());
      await tester.pumpAndSettle();

      expect(repo.reads, previousReads + 1);
      expect(repo.deleteCalls, hasLength(1));
      expect(store.applicationById(appId), isNull);
      expect(navigation.selectedTab, AppTab.home);
      expect(
        find.textContaining('Hasil perubahan belum dapat dipastikan.'),
        findsOneWidget,
      );
      expect(find.textContaining('Lamaran tidak ditemukan'), findsOneWidget);
    },
  );

  testWidgets('deletion finishing after Back leaves the current route alone', (
    tester,
  ) async {
    final repo = _DetailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    final navigation = await _openConnected(tester, store);
    final write = Completer<String>();
    repo.delete = (_, _) => write.future;
    await openDeleteDialog(tester);
    await tester.tap(deleteConfirmation());
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    repo.read = () => _snapshot(deleted: true);
    write.complete(appId);
    await tester.pumpAndSettle();
    expect(store.applicationById(appId), isNull);
    expect(navigation.selectedTab, AppTab.home);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late status error cannot show a snackbar after Back', (
    tester,
  ) async {
    final repo = _DetailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    final navigation = await _openConnected(tester, store);
    final write = Completer<ApplicationReceipt>();
    repo.status = (_, _, _) => write.future;
    await _selectOffering(tester);
    await _saveStatus(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    write.completeError(const RepositoryFailure(RepositoryIssue.forbidden));
    await tester.pumpAndSettle();

    expect(navigation.selectedTab, AppTab.home);
    expect(find.byKey(const ValueKey('S03')), findsNothing);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account switch isolates an old receipt from the new Detail', (
    tester,
  ) async {
    final session = TestSession();
    final previous = _DetailRepository(() => _snapshot(company: 'Account A'));
    final current = _DetailRepository(
      () =>
          _snapshot(company: 'Account B', status: RecruitmentStatus.screening),
    );
    final write = Completer<String>();
    previous.delete = (_, _) => write.future;
    await mount(tester, session, (id) => id == 'owner-a' ? previous : current);
    await tester.pumpAndSettle();

    final oldShell = tester.widget<AppShell>(find.byType(AppShell));
    await openDetail(tester, oldShell.navigation, appId);
    await openDeleteDialog(tester);
    await tester.tap(deleteConfirmation());
    await tester.pumpAndSettle();
    expect(previous.deleteCalls, hasLength(1));
    expect(oldShell.store.isMutating, isTrue);

    session.changes.add(session.signedIn('owner-b'));
    await tester.pumpAndSettle();
    expect(previous.disposed, isTrue);
    final newShell = tester.widget<AppShell>(find.byType(AppShell));
    await openDetail(tester, newShell.navigation, appId);
    final oldReads = previous.reads;
    final newReads = current.reads;
    previous.read = () => _snapshot(deleted: true);
    write.complete(appId);
    await tester.pumpAndSettle();

    expect(previous.reads, oldReads);
    expect(current.reads, newReads);
    expect(current.deleteCalls, isEmpty);
    expect(newShell.store.applicationById(appId)?.company, 'Account B');
    expect(_currentStatus(tester), RecruitmentStatus.screening);
    expect(newShell.navigation.selectedTab, AppTab.home);
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing ID keeps Back available with no mutation actions', (
    tester,
  ) async {
    final repo = _DetailRepository(_snapshot);
    final store = JobTrailStore.connected(repo);
    await _openConnected(tester, store, id: 'missing');
    expect(find.textContaining('Lamaran tidak ditemukan'), findsOneWidget);
    expect(find.text('Ubah Status'), findsNothing);
    expect(find.text('Hapus Lamaran'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
  });

  testWidgets('connected Detail previews metadata and scopes Schedule by ID', (
    tester,
  ) async {
    final store = JobTrailStore.connected(_DetailRepository(_snapshot));
    final navigation = await _openConnected(tester, store);
    expect(find.textContaining('Synthetic link'), findsOneWidget);
    expect(find.text('Edit Lamaran'), findsNothing);
    expect(find.byTooltip('Edit Lamaran'), findsNothing);
    expect(find.text('Tambah Agenda'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('detail-document-$documentId')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('document-preview-sheet')),
      findsOneWidget,
    );
    expect(find.text('sample.pdf'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);

    await tester.tap(find.text('Agenda berikutnya'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S05')), findsOneWidget);
    expect(navigation.scheduleApplicationId, appId);
    expect(find.byKey(const ValueKey('S03')), findsNothing);
  });
}
