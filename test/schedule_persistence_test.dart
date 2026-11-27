import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/schedule/schedule_screen.dart';

import 'jobtrail_persistence_test.dart' show TestSession, mount;
import 'support/fake_jobtrail_repository.dart';

// S05 persistence (W13-023, W13-025, W13-026). Backend mode only, through a
// scripted fake repository: no network, no credentials, no hosted writes.
//
// Snapshot clock: reference date Tue 24 Nov 2026 (WIB civil date) and
// reference instant 03.00 UTC == 10.00 WIB. The device clock is never used.

final _referenceDate = DateTime.utc(2026, 11, 24);
final _referenceInstant = DateTime.utc(2026, 11, 24, 3);

Application _app(
  String id,
  String company,
  String position,
  RecruitmentStatus status,
  int appliedDay,
) => Application(
  id: id,
  company: company,
  position: position,
  source: 'LinkedIn',
  appliedAt: DateTime.utc(2026, 11, appliedDay),
  status: status,
  location: 'Surabaya',
  workType: WorkType.hybrid,
);

final _appA = _app(
  'app-a',
  'Sinar Data',
  'Data Analyst Intern',
  RecruitmentStatus.interview,
  10,
);
final _appB = _app(
  'app-b',
  'Kopi Teknologi',
  'QA Intern',
  RecruitmentStatus.test,
  12,
);
const _appALabel = 'Sinar Data — Data Analyst Intern';

/// 17.30 UTC on 24 Nov is 00.30 WIB on 25 Nov.
final _crossing = Agenda(
  id: 'agenda-cross',
  applicationId: 'app-a',
  type: AgendaType.interview,
  scheduledAt: DateTime.utc(2026, 11, 24, 17, 30),
  locationOrLink: 'Google Meet',
  revision: 1,
);

/// 09.00 WIB on the reference date: before the 10.00 WIB reference instant.
final _earlierToday = Agenda(
  id: 'agenda-earlier',
  applicationId: 'app-b',
  type: AgendaType.test,
  scheduledAt: DateTime.utc(2026, 11, 24, 2),
  locationOrLink: 'Tes online',
  revision: 1,
);

/// Parent is missing from the snapshot; it must never be rendered.
final _orphan = Agenda(
  id: 'agenda-orphan',
  applicationId: 'app-gone',
  type: AgendaType.interview,
  scheduledAt: DateTime.utc(2026, 11, 24, 5),
  locationOrLink: 'Kantor',
  revision: 1,
);

typedef _SaveCall = ({Agenda agenda, SaveMode mode, int? expectedRevision});

/// Server-like fake: committed agendas live in [rows]; every read returns a
/// fresh snapshot of [apps] and [rows]. Saves are scripted per test.
class _ScheduleRepo extends FakeJobTrailRepository {
  _ScheduleRepo({List<Application>? apps, List<Agenda>? rows})
    : apps = apps ?? [_appA, _appB],
      rows = rows ?? [_crossing, _earlierToday, _orphan],
      super(_unset) {
    read = current;
  }

  static JobTrailSnapshot _unset() => throw StateError('read not set');

  List<Application> apps;
  final List<Agenda> rows;
  final saves = <_SaveCall>[];
  late FutureOr<AgendaReceipt> Function(Agenda, SaveMode) onSave = commit;

  JobTrailSnapshot current() => JobTrailSnapshot(
    referenceDate: _referenceDate,
    referenceInstantUtc: _referenceInstant,
    applications: apps,
    agendas: rows,
    documents: const [],
    history: const [],
    applicationRevisions: {for (final app in apps) app.id: 1},
  );

  /// IDs whose `agendas` row belongs to another account (global PK `id`).
  final foreignIds = <String>{};

  /// Create fingerprint: the payload `jobtrail_save_agenda` hashes on create.
  static List<Object> _fingerprint(Agenda a) => [
    a.applicationId,
    a.type.name,
    a.scheduledAt.toUtc().toIso8601String(),
    a.locationOrLink.trim(),
    a.notes,
  ];

  /// Mirrors the create branch of `jobtrail_save_agenda`
  /// (supabase/migrations/20261124000200_jobtrail_access.sql, with revisions
  /// from 20261126000100_jobtrail_entity_revisions.sql, see
  /// docs/ENTITY_REVISION_CONTRACT.md): own row + same fingerprint →
  /// `replayed: true` with the row's current revision; own row + different
  /// fingerprint → JT004; ID held by another account → JT004; else insert at
  /// revision 1.
  AgendaReceipt commit(Agenda agenda, SaveMode mode) {
    final own = rows.where((row) => row.id == agenda.id).firstOrNull;
    if (own != null) {
      if (!listEquals(_fingerprint(own), _fingerprint(agenda))) {
        throw const RepositoryFailure(RepositoryIssue.createConflict);
      }
      return (id: agenda.id, revision: own.revision, replayed: true);
    }
    if (foreignIds.contains(agenda.id)) {
      throw const RepositoryFailure(RepositoryIssue.createConflict);
    }
    final row = Agenda(
      id: agenda.id,
      applicationId: agenda.applicationId,
      type: agenda.type,
      scheduledAt: agenda.scheduledAt,
      locationOrLink: agenda.locationOrLink,
      notes: agenda.notes,
      revision: 1,
    );
    rows.add(row);
    return (id: row.id, revision: row.revision, replayed: false);
  }

  @override
  Future<AgendaReceipt> saveAgenda(
    Agenda agenda,
    SaveMode mode, {
    int? expectedRevision,
  }) async {
    saves.add((agenda: agenda, mode: mode, expectedRevision: expectedRevision));
    return onSave(agenda, mode);
  }

  /// The next [count] reads fail like a dropped connection, then reads
  /// return the server state again.
  void failReads(int count) {
    var left = count;
    read = () {
      if (left > 0) {
        left--;
        throw const RepositoryFailure(RepositoryIssue.network);
      }
      return current();
    };
  }

  /// The next read waits for the returned completer (a slow response that
  /// can outlive the route, tab or session that started it).
  Completer<void> holdNextRead() {
    final gate = Completer<void>();
    var held = true;
    read = () async {
      if (held) {
        held = false;
        await gate.future;
      }
      return current();
    };
    return gate;
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<JobTrailStore> _open(
  WidgetTester tester,
  _ScheduleRepo repo, {
  bool load = true,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = JobTrailStore.connected(repo);
  addTearDown(store.dispose);
  if (load) await store.refresh();
  await tester.pumpWidget(JobTrailApp(showAuthentication: false, store: store));
  await tester.tap(_key('nav-schedule'));
  await tester.pumpAndSettle();
  return store;
}

Future<void> _tapInSheet(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

/// Opens the sheet and fills a valid agenda: Sinar Data, interview,
/// [day] Nov 2026 10.00 WIB, "Kantor Sinar". Day 30 falls in the next
/// Sunday-based week, so revealing it visibly moves the week filter.
Future<void> _fillSheet(WidgetTester tester, {String day = '25'}) async {
  await tester.tap(_key('schedule-add'));
  await tester.pumpAndSettle();
  expect(_key('add-agenda-sheet'), findsOneWidget);
  await _tapInSheet(tester, 'agenda-application');
  await tester.tap(find.text(_appALabel).last);
  await tester.pumpAndSettle();
  await _tapInSheet(tester, 'agenda-type-interview');
  await _tapInSheet(tester, 'agenda-date');
  await tester.tap(find.text(day).last);
  await tester.tap(find.text('Pilih'));
  await tester.pumpAndSettle();
  await _tapInSheet(tester, 'agenda-time');
  final inputs = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(inputs.at(0), '10');
  await tester.enterText(inputs.at(1), '00');
  await tester.tap(find.text('Pilih'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_key('agenda-location'));
  await tester.enterText(_key('agenda-location'), 'Kantor Sinar');
  await tester.pumpAndSettle();
}

String _saveLabel(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: _key('agenda-save'), matching: find.byType(Text)),
    )
    .map((text) => text.data)
    .join();

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed != null;

void _expectSamePayload(Agenda a, Agenda b) {
  expect(identical(a, b), isTrue, reason: 'retry must resend the same intent');
  expect(b.id, a.id);
  expect(b.applicationId, a.applicationId);
  expect(b.type, a.type);
  expect(b.scheduledAt, a.scheduledAt);
  expect(b.locationOrLink, a.locationOrLink);
  expect(b.notes, a.notes);
}

void main() {
  group('W13-023 create agenda via saveAgendaRemote', () {
    testWidgets('add is disabled until the first snapshot is loaded', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo, load: false);
      final add = tester.widget<InkWell>(_key('schedule-add'));
      expect(add.onTap, isNull);
      expect(store.allowsLocalWrites, isFalse);

      await store.refresh();
      await tester.pumpAndSettle();
      expect(tester.widget<InkWell>(_key('schedule-add')).onTap, isNotNull);
    });

    testWidgets('create sends one explicit create and shows the WIB date', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      final readsBefore = repo.reads;
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, hasLength(1));
      final sent = repo.saves.single;
      expect(sent.mode, SaveMode.create);
      // Create omits p_expected_revision; the server starts the row at 1.
      expect(sent.expectedRevision, isNull);
      // Backend IDs come from nextAgendaId() (UUID), not a local counter.
      expect(
        sent.agenda.id,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-')),
      );
      expect(sent.agenda.applicationId, 'app-a');
      expect(sent.agenda.type, AgendaType.interview);
      expect(sent.agenda.scheduledAt, DateTime.utc(2026, 11, 25, 3));
      expect(sent.agenda.locationOrLink, 'Kantor Sinar');
      // The store reconciled from the server before announcing the save.
      expect(repo.reads, readsBefore + 1);
      expect(store.agendas.where((a) => a.id == sent.agenda.id), hasLength(1));
      expect(store.agendaRevision(sent.agenda.id), 1);

      expect(_key('add-agenda-sheet'), findsNothing);
      expect(find.text('Agenda tersimpan: Rab, 25 Nov, 10.00 WIB'), findsOne);
      expect(_key('agenda-${sent.agenda.id}'), findsOneWidget);
    });

    testWidgets('double tap while saving dispatches one write', (tester) async {
      final repo = _ScheduleRepo();
      final pending = Completer<AgendaReceipt>();
      repo.onSave = (_, _) => pending.future;
      await _open(tester, repo);
      await _fillSheet(tester);

      await tester.tap(_key('agenda-save'));
      await tester.pump();
      expect(_saveLabel(tester), 'Menyimpan…');
      expect(_enabled(tester, 'agenda-save'), isFalse);
      expect(_enabled(tester, 'agenda-cancel'), isFalse);
      await tester.tap(_key('agenda-save'), warnIfMissed: false);
      await tester.pump();
      // Back/barrier cannot abandon a request in flight.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(_key('agenda-discard-dialog'), findsNothing);
      expect(repo.saves, hasLength(1));

      final agenda = repo.saves.single.agenda;
      pending.complete(repo.commit(agenda, SaveMode.create));
      await tester.pumpAndSettle();
      expect(repo.saves, hasLength(1));
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(_key('agenda-${agenda.id}'), findsOneWidget);
    });

    testWidgets('ambiguous outcome locks the draft and retries same intent', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      repo.onSave = (_, _) => throw const RepositoryFailure(
        RepositoryIssue.network,
        writeOutcomeUnknown: true,
      );
      final store = await _open(tester, repo);
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');

      // Not claimed as saved, not claimed as failed: the sheet stays open.
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(find.textContaining('Status penyimpanan belum pasti'), findsOne);
      expect(find.textContaining('Agenda tersimpan'), findsNothing);
      expect(_saveLabel(tester), 'Kirim ulang');
      // The payload is pinned: edits are blocked until the outcome is known.
      final location = tester.widget<TextField>(
        find.descendant(
          of: _key('agenda-location'),
          matching: find.byType(TextField),
        ),
      );
      expect(location.readOnly, isTrue);
      await _tapInSheet(tester, 'agenda-type-test');
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, hasLength(2));
      _expectSamePayload(repo.saves[0].agenda, repo.saves[1].agenda);
      expect(repo.saves[1].mode, SaveMode.create);
      expect(repo.saves[1].agenda.type, AgendaType.interview);

      // The second attempt (handler still throws) keeps the same intent.
      repo.onSave = repo.commit;
      await _tapInSheet(tester, 'agenda-save');
      expect(repo.saves, hasLength(3));
      _expectSamePayload(repo.saves[0].agenda, repo.saves[2].agenda);
      expect(_key('add-agenda-sheet'), findsNothing);
      final id = repo.saves.first.agenda.id;
      expect(store.agendas.where((a) => a.id == id), hasLength(1));
    });

    testWidgets('ambiguous outcome already committed closes as saved', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      repo.onSave = (agenda, mode) {
        repo.commit(agenda, mode);
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      };
      await _open(tester, repo);
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, hasLength(1));
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(find.text('Agenda tersimpan: Rab, 25 Nov, 10.00 WIB'), findsOne);
    });

    testWidgets('closing an uncertain draft warns and reloads the snapshot', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      repo.onSave = (_, _) => throw const RepositoryFailure(
        RepositoryIssue.network,
        writeOutcomeUnknown: true,
      );
      await _open(tester, repo);
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');
      final reads = repo.reads;

      await _tapInSheet(tester, 'agenda-cancel');
      expect(find.textContaining('belum pasti. Jika ditutup'), findsOne);
      await tester.tap(_key('agenda-discard-confirm'));
      await tester.pumpAndSettle();
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(repo.reads, reads + 1);
      expect(repo.saves, hasLength(1));
    });

    testWidgets('committed but stale snapshot is reported and reloaded once', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      final reads = repo.reads;
      // The reconciling read after the write fails; the automatic re-read
      // is held so the confirmed-but-stale state can be inspected.
      late Completer<void> gate;
      var failed = false;
      repo.read = () {
        if (!failed) {
          failed = true;
          gate = repo.holdNextRead();
          throw const RepositoryFailure(RepositoryIssue.network);
        }
        return repo.current();
      };
      await _fillSheet(tester);
      await tester.ensureVisible(_key('agenda-save'));
      await tester.tap(_key('agenda-save'));
      await tester.pump();
      await tester.pump();

      // Confirmed on the server: the sheet says so and offers no write.
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(_key('agenda-saved-stale'), findsOneWidget);
      expect(find.textContaining('Agenda tersimpan di server'), findsOne);
      expect(_saveLabel(tester), 'Tersimpan');
      expect(_enabled(tester, 'agenda-save'), isFalse);
      expect(repo.reads, reads + 2);

      gate.complete();
      await tester.pumpAndSettle();
      expect(_key('add-agenda-sheet'), findsNothing);
      // The committed write is never repeated; only the snapshot is reloaded.
      expect(repo.saves, hasLength(1));
      expect(repo.reads, reads + 2);
      expect(store.phase, StorePhase.ready);
      final id = repo.saves.single.agenda.id;
      expect(store.agendas.where((a) => a.id == id), hasLength(1));
      expect(find.text('Agenda tersimpan: Rab, 25 Nov, 10.00 WIB'), findsOne);
      expect(_key('agenda-$id'), findsOneWidget);
    });

    testWidgets('definitive rejection unlocks the form and claims nothing', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      repo.onSave = (_, _) =>
          throw const RepositoryFailure(RepositoryIssue.validation);
      final store = await _open(tester, repo);
      final before = store.agendas.length;
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');

      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(find.text(RepositoryIssue.validation.message), findsOne);
      expect(find.textContaining('Agenda tersimpan'), findsNothing);
      expect(_saveLabel(tester), 'Simpan Agenda');
      expect(store.agendas, hasLength(before));

      // Editable again; the next submit is a new intent with a new ID.
      await tester.enterText(_key('agenda-location'), 'Kantor Baru');
      repo.onSave = repo.commit;
      await _tapInSheet(tester, 'agenda-save');
      expect(repo.saves, hasLength(2));
      expect(repo.saves[1].agenda.id, isNot(repo.saves[0].agenda.id));
      expect(repo.saves[1].agenda.locationOrLink, 'Kantor Baru');
      expect(_key('add-agenda-sheet'), findsNothing);
    });

    testWidgets(
      'late commit after a proven absence: identical resend replays',
      (tester) async {
        final repo = _ScheduleRepo();
        final store = await _open(tester, repo);
        Agenda? lateIntent;
        repo.onSave = (agenda, mode) {
          if (lateIntent == null) {
            // The response is lost and the reconciling read still sees no row;
            // the server applies the request only after that read.
            lateIntent = agenda;
            throw const RepositoryFailure(
              RepositoryIssue.network,
              writeOutcomeUnknown: true,
            );
          }
          return repo.commit(agenda, mode);
        };
        await _fillSheet(tester);
        await _tapInSheet(tester, 'agenda-save');
        expect(_saveLabel(tester), 'Kirim ulang');
        expect(_enabled(tester, 'agenda-save'), isTrue);
        expect(_key('agenda-reload'), findsNothing);
        repo.commit(lateIntent!, SaveMode.create);

        // Resending the pinned intent must replay, never conflict or duplicate.
        await _tapInSheet(tester, 'agenda-save');
        expect(repo.saves, hasLength(2));
        _expectSamePayload(repo.saves[0].agenda, repo.saves[1].agenda);
        expect(repo.saves[1].expectedRevision, isNull);
        final id = repo.saves.first.agenda.id;
        expect(repo.rows.where((row) => row.id == id), hasLength(1));
        expect(store.agendaRevision(id), 1);
        expect(_key('add-agenda-sheet'), findsNothing);
        expect(find.textContaining('Agenda tersimpan'), findsOne);
      },
    );

    testWidgets('createConflict on an identical retry is not a save', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      repo.onSave = (_, _) => throw const RepositoryFailure(
        RepositoryIssue.network,
        writeOutcomeUnknown: true,
      );
      final store = await _open(tester, repo);
      final before = repo.rows.length;
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');
      expect(_saveLabel(tester), 'Kirim ulang');

      // Per the SQL, an identical payload on an own row replays. JT004 for
      // the same ID + payload therefore means the ID is not this account's
      // record (here: held by another account), so nothing was saved.
      final firstId = repo.saves.first.agenda.id;
      repo.foreignIds.add(firstId);
      repo.onSave = repo.commit;
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, hasLength(2));
      _expectSamePayload(repo.saves[0].agenda, repo.saves[1].agenda);
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(find.textContaining('Agenda tersimpan'), findsNothing);
      expect(
        find.text('Agenda belum tersimpan. Ketuk Simpan untuk mencoba lagi.'),
        findsOne,
      );
      expect(find.text(RepositoryIssue.createConflict.message), findsNothing);
      expect(store.agendas.where((a) => a.id == firstId), isEmpty);
      // The intent is dropped and the form unlocked; a new submit is a new
      // intent (new ID) with the same user-entered values.
      expect(_saveLabel(tester), 'Simpan Agenda');
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, hasLength(3));
      final second = repo.saves[2].agenda;
      expect(second.id, isNot(firstId));
      expect(second.scheduledAt, repo.saves[0].agenda.scheduledAt);
      expect(second.locationOrLink, repo.saves[0].agenda.locationOrLink);
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(repo.rows, hasLength(before + 1));
      expect(store.agendas.where((a) => a.id == second.id), hasLength(1));
    });

    testWidgets('createConflict on a first submit shows the S05 message', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      repo.onSave = (_, _) =>
          throw const RepositoryFailure(RepositoryIssue.createConflict);
      final store = await _open(tester, repo);
      final before = store.agendas.length;
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, hasLength(1));
      expect(
        find.text('Agenda belum tersimpan. Ketuk Simpan untuk mencoba lagi.'),
        findsOne,
      );
      expect(find.text(RepositoryIssue.createConflict.message), findsNothing);
      expect(find.textContaining('Agenda tersimpan'), findsNothing);
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(_saveLabel(tester), 'Simpan Agenda');
      expect(store.agendas, hasLength(before));

      repo.onSave = repo.commit;
      await _tapInSheet(tester, 'agenda-save');
      expect(repo.saves, hasLength(2));
      expect(repo.saves[1].agenda.id, isNot(repo.saves[0].agenda.id));
      expect(_key('add-agenda-sheet'), findsNothing);
    });

    testWidgets('parent removed by reload is rejected before any write', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      await _fillSheet(tester);
      repo.apps = [_appB];
      repo.rows.removeWhere((row) => row.applicationId == 'app-a');
      await store.refresh();
      await tester.pumpAndSettle();
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, isEmpty);
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(
        find.text('Lamaran terkait sudah tidak tersedia. Pilih lamaran lain.'),
        findsOne,
      );
    });

    testWidgets('server-side missing parent shows the same safe message', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      repo.onSave = (_, _) =>
          throw const RepositoryFailure(RepositoryIssue.unavailable);
      await _open(tester, repo);
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.saves, hasLength(1));
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(
        find.text('Lamaran terkait sudah tidak tersedia. Pilih lamaran lain.'),
        findsOne,
      );
    });
  });

  group('W13-026 recovery through the sheet (read before any resend)', () {
    testWidgets('read fails → Muat ulang → ID found → saved, no second write', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      repo.onSave = (agenda, mode) {
        // Committed on the server; the response is lost and both the
        // reconciling read and the first reload fail.
        repo.commit(agenda, mode);
        repo.failReads(2);
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      };
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');

      expect(store.phase, StorePhase.error);
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(find.textContaining('Agenda tersimpan'), findsNothing);
      expect(find.textContaining('Ketuk "Muat ulang"'), findsOne);
      expect(_key('agenda-reload'), findsOneWidget);
      // Without a fresh snapshot there is no proof of absence: no resend.
      expect(_saveLabel(tester), 'Kirim ulang');
      expect(_enabled(tester, 'agenda-save'), isFalse);
      await tester.tap(_key('agenda-save'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.saves, hasLength(1));

      // A failed reload keeps the intent pinned and still writes nothing.
      final reads = repo.reads;
      await _tapInSheet(tester, 'agenda-reload');
      expect(repo.reads, reads + 1);
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(_key('agenda-reload'), findsOneWidget);
      expect(_enabled(tester, 'agenda-save'), isFalse);

      await _tapInSheet(tester, 'agenda-reload');
      expect(repo.reads, reads + 2);
      expect(repo.saves, hasLength(1));
      final id = repo.saves.single.agenda.id;
      expect(repo.rows.where((row) => row.id == id), hasLength(1));
      expect(store.phase, StorePhase.ready);
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(find.text('Agenda tersimpan: Rab, 25 Nov, 10.00 WIB'), findsOne);
      expect(_key('agenda-$id'), findsOneWidget);
    });

    testWidgets('read fails → Muat ulang → ID absent → Kirim ulang resends '
        'the same ID and payload', (tester) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      repo.onSave = (agenda, mode) {
        // Nothing committed; the reconciling read fails.
        repo.failReads(1);
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      };
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');
      expect(_key('agenda-reload'), findsOneWidget);
      expect(_enabled(tester, 'agenda-save'), isFalse);

      await _tapInSheet(tester, 'agenda-reload');
      // The fresh snapshot proves the ID absent: resend unlocked, not sent.
      expect(store.phase, StorePhase.ready);
      expect(repo.saves, hasLength(1));
      expect(_key('agenda-reload'), findsNothing);
      expect(_saveLabel(tester), 'Kirim ulang');
      expect(_enabled(tester, 'agenda-save'), isTrue);
      expect(find.textContaining('agenda yang sama'), findsOne);
      final location = tester.widget<TextField>(
        find.descendant(
          of: _key('agenda-location'),
          matching: find.byType(TextField),
        ),
      );
      expect(location.readOnly, isTrue);

      repo.onSave = repo.commit;
      await _tapInSheet(tester, 'agenda-save');
      expect(repo.saves, hasLength(2));
      _expectSamePayload(repo.saves[0].agenda, repo.saves[1].agenda);
      expect(repo.saves[1].mode, SaveMode.create);
      expect(repo.saves[1].expectedRevision, isNull);
      final id = repo.saves.first.agenda.id;
      expect(repo.rows.where((row) => row.id == id), hasLength(1));
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(find.text('Agenda tersimpan: Rab, 25 Nov, 10.00 WIB'), findsOne);
    });

    testWidgets('confirmed receipt + stale snapshot: recovery only reads', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      repo.onSave = (agenda, mode) {
        final receipt = repo.commit(agenda, mode);
        // Reconciling read, automatic re-read and first manual reload fail.
        repo.failReads(3);
        return receipt;
      };
      await _fillSheet(tester);
      final reads = repo.reads;
      await _tapInSheet(tester, 'agenda-save');

      expect(repo.reads, reads + 2);
      expect(store.phase, StorePhase.error);
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(_key('agenda-saved-stale'), findsOneWidget);
      expect(_key('agenda-reload'), findsOneWidget);
      expect(_saveLabel(tester), 'Tersimpan');
      expect(_enabled(tester, 'agenda-save'), isFalse);
      expect(
        find.descendant(
          of: _key('agenda-cancel'),
          matching: find.text('Tutup'),
        ),
        findsOne,
      );
      await tester.tap(_key('agenda-save'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await _tapInSheet(tester, 'agenda-reload');
      expect(repo.reads, reads + 3);
      expect(_key('add-agenda-sheet'), findsOneWidget);
      expect(_key('agenda-reload'), findsOneWidget);

      await _tapInSheet(tester, 'agenda-reload');
      expect(repo.reads, reads + 4);
      // Zero additional writes across every recovery step.
      expect(repo.saves, hasLength(1));
      final id = repo.saves.single.agenda.id;
      expect(store.agendaRevision(id), 1);
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(find.text('Agenda tersimpan: Rab, 25 Nov, 10.00 WIB'), findsOne);
      expect(_key('agenda-$id'), findsOneWidget);
    });

    testWidgets('confirmed agenda missing from a fresh read is never resent', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      await _open(tester, repo);
      repo.onSave = (agenda, mode) {
        final receipt = repo.commit(agenda, mode);
        repo.failReads(2);
        return receipt;
      };
      await _fillSheet(tester);
      await _tapInSheet(tester, 'agenda-save');
      // Deleted elsewhere before the reload succeeds.
      repo.rows.removeWhere((row) => row.id == repo.saves.single.agenda.id);
      await _tapInSheet(tester, 'agenda-reload');

      expect(find.textContaining('tidak ada pada data terbaru'), findsOne);
      expect(_key('agenda-reload'), findsNothing);
      expect(_enabled(tester, 'agenda-save'), isFalse);
      await _tapInSheet(tester, 'agenda-cancel');
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(repo.saves, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('saved ID is kept until a read finds it, then revealed', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      repo.onSave = (agenda, mode) {
        final receipt = repo.commit(agenda, mode);
        repo.failReads(2);
        return receipt;
      };
      // 30 Nov is in the next week: revealing it moves the week filter.
      await _fillSheet(tester, day: '30');
      await _tapInSheet(tester, 'agenda-save');
      final id = repo.saves.single.agenda.id;
      expect(_key('schedule-day-2026-11-30'), findsNothing);

      // Closing a confirmed sheet needs no discard and starts a read. That
      // read fails as well, so the saved ID is kept, not revealed.
      final reads = repo.reads;
      repo.failReads(1);
      await _tapInSheet(tester, 'agenda-cancel');
      expect(_key('agenda-discard-dialog'), findsNothing);
      expect(_key('add-agenda-sheet'), findsNothing);
      expect(repo.reads, reads + 1);
      expect(store.phase, StorePhase.error);
      expect(store.agendaById(id), isNull);
      // Not in the snapshot yet: no feedback, no filter change.
      expect(find.byType(SnackBar), findsNothing);
      expect(_key('schedule-day-2026-11-24'), findsOneWidget);
      expect(_key('schedule-day-2026-11-30'), findsNothing);

      // The shell's own retry reads again; the kept ID is now revealed.
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(repo.saves, hasLength(1));
      expect(_key('schedule-day-2026-11-30'), findsOneWidget);
      expect(_key('schedule-day-2026-11-24'), findsNothing);
      expect(_key('agenda-$id'), findsOneWidget);
      expect(find.text('Agenda tersimpan: Sen, 30 Nov, 10.00 WIB'), findsOne);
    });
  });

  group('W13-026 late completion has a single owner', () {
    AppNavigation nav(WidgetTester tester) =>
        tester.widget<ScheduleScreen>(find.byType(ScheduleScreen)).navigation;

    /// Confirmed write, both reads failed, sheet closed while the read that
    /// closing starts is still in flight. Returns that read's gate.
    Future<Completer<void>> closedAwaitingRead(
      WidgetTester tester,
      _ScheduleRepo repo,
    ) async {
      repo.onSave = (agenda, mode) {
        final receipt = repo.commit(agenda, mode);
        repo.failReads(2);
        return receipt;
      };
      await _fillSheet(tester, day: '30');
      await _tapInSheet(tester, 'agenda-save');
      final gate = repo.holdNextRead();
      await _tapInSheet(tester, 'agenda-cancel');
      expect(_key('add-agenda-sheet'), findsNothing);
      return gate;
    }

    void expectNoFeedback(WidgetTester tester) {
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Agenda tersimpan'), findsNothing);
    }

    testWidgets('sheet route closed while the save is in flight', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final pending = Completer<AgendaReceipt>();
      repo.onSave = (_, _) => pending.future;
      final store = await _open(tester, repo);
      await _fillSheet(tester, day: '30');
      await tester.ensureVisible(_key('agenda-save'));
      await tester.tap(_key('agenda-save'));
      await tester.pump();
      // Navigation closes the modal route even while a request is pending.
      nav(tester).showTab(AppTab.schedule);
      await tester.pumpAndSettle();
      expect(_key('add-agenda-sheet'), findsNothing);

      pending.complete(repo.commit(repo.saves.single.agenda, SaveMode.create));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.saves, hasLength(1));
      expect(store.agendaById(repo.saves.single.agenda.id), isNotNull);
      expectNoFeedback(tester);
      expect(_key('schedule-day-2026-11-24'), findsOneWidget);
      expect(_key('schedule-day-2026-11-30'), findsNothing);
    });

    testWidgets('route no longer current when the read finds the ID', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      final navigation = nav(tester);
      final gate = await closedAwaitingRead(tester, repo);
      unawaited(navigation.openDetail('app-a'));
      await tester.pumpAndSettle();

      gate.complete();
      await tester.pumpAndSettle();
      expect(store.agendaById(repo.saves.single.agenda.id), isNotNull);
      expectNoFeedback(tester);
      navigation.back();
      await tester.pumpAndSettle();
      expectNoFeedback(tester);
      expect(_key('schedule-day-2026-11-24'), findsOneWidget);
      expect(_key('schedule-day-2026-11-30'), findsNothing);
      expect(repo.saves, hasLength(1));
    });

    testWidgets('Schedule tab no longer active when the read finds the ID', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      final navigation = nav(tester);
      final gate = await closedAwaitingRead(tester, repo);
      navigation.showTab(AppTab.home);
      await tester.pumpAndSettle();

      gate.complete();
      await tester.pumpAndSettle();
      expect(store.agendaById(repo.saves.single.agenda.id), isNotNull);
      expectNoFeedback(tester);
      navigation.showTab(AppTab.schedule);
      await tester.pumpAndSettle();
      expectNoFeedback(tester);
      expect(_key('schedule-day-2026-11-24'), findsOneWidget);
      expect(_key('schedule-day-2026-11-30'), findsNothing);
      expect(repo.saves, hasLength(1));
    });

    for (final switchAccount in [false, true]) {
      testWidgets(
        'save completing after ${switchAccount ? 'account switch' : 'logout'}'
        ' gives no feedback',
        (tester) async {
          final session = TestSession();
          final repo = _ScheduleRepo();
          final other = _ScheduleRepo(apps: [_appB], rows: []);
          final pending = Completer<AgendaReceipt>();
          repo.onSave = (_, _) => pending.future;
          await mount(tester, session, (id) => id == 'owner-a' ? repo : other);
          await tester.pumpAndSettle();
          await tester.tap(_key('nav-schedule'));
          await tester.pumpAndSettle();
          await _fillSheet(tester, day: '30');
          await tester.ensureVisible(_key('agenda-save'));
          await tester.tap(_key('agenda-save'));
          await tester.pump();
          expect(repo.saves, hasLength(1));

          if (switchAccount) {
            session.changes.add(session.signedIn('owner-b'));
          } else {
            await session.signOut();
          }
          await tester.pumpAndSettle();
          expect(repo.disposed, isTrue);
          expect(_key('add-agenda-sheet'), findsNothing);

          // The server accepted the request; the old session must not react.
          final agenda = repo.saves.single.agenda;
          pending.complete(repo.commit(agenda, SaveMode.create));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(repo.saves, hasLength(1));
          expect(other.saves, isEmpty);
          expectNoFeedback(tester);
          if (switchAccount) {
            await tester.tap(_key('nav-schedule'));
            await tester.pumpAndSettle();
            expect(_key('agenda-${agenda.id}'), findsNothing);
            expect(_key('schedule-day-2026-11-30'), findsNothing);
            expectNoFeedback(tester);
          } else {
            expect(find.byType(ScheduleScreen), findsNothing);
          }
        },
      );
    }
  });

  group('W13-025 snapshot reading, WIB dates and Detail scope', () {
    testWidgets('today and week come from the snapshot reference date', (
      tester,
    ) async {
      await _open(tester, _ScheduleRepo());
      expect(
        tester.widget<Text>(_key('schedule-today')).data,
        'Hari ini · Selasa, 24 Nov 2026',
      );
    });

    testWidgets('UTC/WIB crossing: 17.30 UTC lands on the next WIB day', (
      tester,
    ) async {
      await _open(tester, _ScheduleRepo());
      await tester.tap(_key('schedule-day-2026-11-25'));
      await tester.pumpAndSettle();
      expect(_key('agenda-agenda-cross'), findsOneWidget);
      expect(_key('agenda-agenda-earlier'), findsNothing);

      await tester.tap(_key('schedule-day-2026-11-25'));
      await tester.tap(_key('schedule-day-2026-11-24'));
      await tester.pumpAndSettle();
      expect(_key('agenda-agenda-cross'), findsNothing);
      expect(_key('agenda-agenda-earlier'), findsOneWidget);
    });

    testWidgets('past/upcoming split uses the reference instant, not dates', (
      tester,
    ) async {
      await _open(tester, _ScheduleRepo());
      // 09.00 WIB is past at 10.00 WIB on the same civil day.
      expect(_key('agenda-past-agenda-earlier'), findsOneWidget);
      expect(_key('agenda-past-agenda-cross'), findsNothing);
      expect(
        tester.widget<Text>(_key('schedule-summary-title')).data,
        '1 agenda dalam 7 hari ke depan',
      );
      expect(
        tester.widget<Text>(_key('schedule-summary-detail')).data,
        '1 interview · 0 test/psikotes · terdekat besok 00.30 WIB',
      );
    });

    testWidgets('agenda whose parent is missing is never rendered', (
      tester,
    ) async {
      await _open(tester, _ScheduleRepo());
      expect(_key('agenda-agenda-orphan'), findsNothing);
      expect(tester.takeException(), isNull);
      final all = tester.widget<Text>(
        find.descendant(
          of: _key('schedule-filter-all'),
          matching: find.text('2'),
        ),
      );
      expect(all.data, '2');
    });

    testWidgets('Detail scope lists only agendasFor(applicationId)', (
      tester,
    ) async {
      await _open(tester, _ScheduleRepo());
      final navigation = tester
          .widget<ScheduleScreen>(find.byType(ScheduleScreen))
          .navigation;
      navigation.showTab(AppTab.schedule, applicationId: 'app-b');
      await tester.pumpAndSettle();
      expect(find.text('Agenda untuk Kopi Teknologi'), findsOne);
      expect(_key('agenda-agenda-earlier'), findsOneWidget);
      expect(_key('agenda-agenda-cross'), findsNothing);

      navigation.showTab(AppTab.schedule, applicationId: 'app-gone');
      await tester.pumpAndSettle();
      expect(find.text('Agenda untuk lamaran ini'), findsOne);
      expect(_key('agenda-agenda-orphan'), findsNothing);
      expect(_key('schedule-empty'), findsOneWidget);
    });

    testWidgets('reload replaces agendas without duplicates or stale rows', (
      tester,
    ) async {
      final repo = _ScheduleRepo();
      final store = await _open(tester, repo);
      repo.rows
        ..removeWhere((row) => row.id == 'agenda-cross')
        ..add(
          Agenda(
            id: 'agenda-cross',
            applicationId: 'app-a',
            type: AgendaType.interview,
            // Moved to 26 Nov 08.00 WIB on the server.
            scheduledAt: DateTime.utc(2026, 11, 26, 1),
            locationOrLink: 'Google Meet',
          ),
        );
      await store.refresh();
      await store.refresh();
      await tester.pumpAndSettle();

      expect(store.agendas.where((a) => a.id == 'agenda-cross'), hasLength(1));
      await tester.tap(_key('schedule-day-2026-11-25'));
      await tester.pumpAndSettle();
      expect(_key('agenda-agenda-cross'), findsNothing);
      await tester.tap(_key('schedule-day-2026-11-26'));
      await tester.pumpAndSettle();
      expect(_key('agenda-agenda-cross'), findsOneWidget);
    });
  });
}
