import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/constants/app_dates.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/models/weekly_goal.dart';

ApplicationDraft draft({
  String company = 'Demo Baru',
  String position = 'Intern',
  DateTime? appliedAt,
  RecruitmentStatus status = RecruitmentStatus.applied,
  List<String> documentIds = const [],
  int? salary,
}) => ApplicationDraft(
  company: company,
  position: position,
  source: 'Situs perusahaan',
  appliedAt: appliedAt ?? DateTime.utc(2026, 11, 17),
  status: status,
  location: 'Surabaya',
  workType: WorkType.remote,
  documentIds: documentIds,
  salary: salary,
);

void main() {
  late JobTrailStore store;
  setUp(() => store = JobTrailStore.demo());
  tearDown(() => store.dispose());

  test('reference instant uses injected clock and normalizes UTC', () {
    final instant = DateTime.parse('2026-11-17T07:30:00+07:00');
    final custom = JobTrailStore.demo(clock: () => instant);
    addTearDown(custom.dispose);
    expect(custom.referenceInstantUtc, DateTime.utc(2026, 11, 17, 0, 30));
    expect(custom.referenceInstantUtc.isUtc, isTrue);
    expect(store.referenceInstantUtc, DateTime.utc(2026, 11, 17, 2));
  });

  test(
    'fixture has unique IDs, valid references and consistent latest status',
    () {
      expect(
        store.applications.map((a) => a.id).toSet().length,
        store.applications.length,
      );
      expect(
        store.agendas.map((a) => a.id).toSet().length,
        store.agendas.length,
      );
      expect(
        store.documents.map((a) => a.id).toSet().length,
        store.documents.length,
      );
      expect(
        store.history.map((a) => a.id).toSet().length,
        store.history.length,
      );
      for (final app in store.applications) {
        expect(store.historyFor(app.id).last.status, app.status);
        for (final id in app.documentIds) {
          expect(store.documentById(id), isNotNull);
        }
      }
      for (final agenda in store.agendas) {
        expect(store.applicationById(agenda.applicationId), isNotNull);
      }
      for (final event in store.history) {
        expect(store.applicationById(event.applicationId), isNotNull);
      }
      expect(store.applications.length, 3);
      expect(store.distribution()[RecruitmentStatus.interview], 1);
      expect(store.distribution()[RecruitmentStatus.offering], 0);
      expect(store.weeklyAchieved, 0);
    },
  );

  test('create/edit/status use one source, stable IDs and one notification per mutation', () {
    var notifications = 0;
    store.addListener(() => notifications++);
    final id = store.addApplication(draft(company: '  Baru  '));
    expect(store.applicationById(id)!.company, 'Baru');
    expect(store.applications.length, 4);
    expect(store.weeklyAchieved, 1);
    expect(store.weeklyProgress, 1 / 8);
    expect(store.historyFor(id).single.status, RecruitmentStatus.applied);
    store.updateApplication(id, draft(company: 'Diubah', salary: 2000000));
    expect(store.applicationById(id)!.id, id);
    expect(store.historyFor(id).length, 1);
    store.changeStatus(id, RecruitmentStatus.interview);
    store.changeStatus(id, RecruitmentStatus.offering);
    expect(store.historyFor(id).map((h) => h.status), [
      RecruitmentStatus.applied,
      RecruitmentStatus.interview,
      RecruitmentStatus.offering,
    ]);
    expect(store.distribution()[RecruitmentStatus.offering], 1);
    expect(notifications, 4);
    store.changeStatus(id, RecruitmentStatus.offering);
    expect(notifications, 4);
    store.updateApplication(id, draft());
    expect(store.applicationById(id)!.salary, isNull);
  });

  test('delete cascades agenda/history and retains shared documents', () {
    store.deleteApplication('app-nusa');
    expect(store.applicationById('app-nusa'), isNull);
    expect(store.agendasFor('app-nusa'), isEmpty);
    expect(store.historyFor('app-nusa'), isEmpty);
    expect(store.documents.length, 2);
    expect(store.applicationById('app-arunika'), isNotNull);
  });

  test('invalid applications fail atomically', () {
    var notifications = 0;
    store.addListener(() => notifications++);
    for (final invalid in [
      draft(company: ' '),
      draft(position: ''),
      draft(salary: -1),
      draft(documentIds: ['missing']),
      draft(documentIds: ['doc-cv', 'doc-cv']),
      draft(appliedAt: DateTime.utc(2026, 11, 18)),
      draft(appliedAt: DateTime(2026, 11, 17)),
    ]) {
      expect(() => store.addApplication(invalid), throwsArgumentError);
    }
    expect(store.applications.length, 3);
    expect(store.history.length, 5);
    expect(notifications, 0);
    expect(() => store.updateApplication('missing', draft()), throwsStateError);
    expect(() => store.deleteApplication('missing'), throwsStateError);
  });

  test(
    'cannot move applied date past history or reverse status chronology',
    () {
      expect(
        () => store.updateApplication('app-nusa', draft()),
        throwsArgumentError,
      );
      final early = JobTrailStore.demo(clock: () => DateTime.utc(2026, 11, 2));
      addTearDown(early.dispose);
      expect(
        () => early.changeStatus('app-nusa', RecruitmentStatus.offering),
        throwsArgumentError,
      );
      expect(
        early.applicationById('app-nusa')!.status,
        RecruitmentStatus.interview,
      );
    },
  );

  test('editing applied date cannot invalidate an existing agenda', () {
    final id = store.addApplication(
      draft(appliedAt: DateTime.utc(2026, 11, 15)),
    );
    store.saveAgenda(
      Agenda(
        id: store.nextAgendaId(),
        applicationId: id,
        type: AgendaType.interview,
        scheduledAt: DateTime.utc(2026, 11, 16, 3),
        locationOrLink: 'Ruang demo',
      ),
    );
    expect(() => store.updateApplication(id, draft()), throwsArgumentError);
    expect(store.applicationById(id)!.appliedAt, DateTime.utc(2026, 11, 15));
  });

  test('collections and nested document IDs cannot mutate source', () {
    expect(() => store.applications.clear(), throwsUnsupportedError);
    expect(() => store.agendas.clear(), throwsUnsupportedError);
    expect(() => store.documents.clear(), throwsUnsupportedError);
    expect(() => store.history.clear(), throwsUnsupportedError);
    expect(
      () => store.applications.first.documentIds.add('orphan'),
      throwsUnsupportedError,
    );
    final ids = ['doc-cv'];
    final input = draft(documentIds: ids);
    ids.clear();
    expect(input.documentIds, ['doc-cv']);
  });

  test('agenda upsert enforces valid application and UTC time', () {
    Agenda agenda(String appId, DateTime time) => Agenda(
      id: 'agenda-new',
      applicationId: appId,
      type: AgendaType.test,
      scheduledAt: time,
      locationOrLink: 'Ruang demo',
    );
    expect(
      () => store.saveAgenda(agenda('missing', DateTime.utc(2026, 11, 18))),
      throwsStateError,
    );
    expect(
      () => store.saveAgenda(agenda('app-nusa', DateTime(2026, 11, 18))),
      throwsArgumentError,
    );
    expect(
      () => store.saveAgenda(agenda('app-nusa', DateTime.utc(2026, 10, 1))),
      throwsArgumentError,
    );
    store.saveAgenda(agenda('app-nusa', DateTime.utc(2026, 11, 18)));
    store.saveAgenda(agenda('app-nusa', DateTime.utc(2026, 11, 19)));
    expect(store.agendasFor('app-nusa').length, 2);
    store.deleteAgenda('agenda-new');
    expect(store.agendasFor('app-nusa').length, 1);
  });

  test(
    'document metadata is shared and deletion refuses active references',
    () {
      expect(() => store.deleteDocument('doc-cv'), throwsStateError);
      store.saveDocument(
        AppDocument(
          id: 'doc-new',
          title: 'CV Baru',
          category: DocumentCategory.cvResume,
          fileName: 'demo.pdf',
          version: '1',
          updatedAt: DateTime.utc(2026, 11, 17),
        ),
      );
      final id = store.addApplication(draft(documentIds: ['doc-new']));
      expect(store.applicationById(id)!.documentIds, ['doc-new']);
      expect(() => store.deleteDocument('doc-new'), throwsStateError);
      store.updateApplication(id, draft());
      store.deleteDocument('doc-new');
      expect(store.documentById('doc-new'), isNull);
    },
  );

  test(
    'week boundaries, progress cap, zero target and empty data are safe',
    () {
      final empty = JobTrailStore.empty(
        referenceDate: DateTime.utc(2026, 11, 23),
      );
      addTearDown(empty.dispose);
      expect(empty.distribution().values.every((n) => n == 0), isTrue);
      expect(empty.weeklyProgress, 0);
      empty.addApplication(draft(appliedAt: DateTime.utc(2026, 11, 15)));
      empty.addApplication(draft(appliedAt: DateTime.utc(2026, 11, 16)));
      empty.addApplication(draft(appliedAt: DateTime.utc(2026, 11, 22)));
      empty.addApplication(draft(appliedAt: DateTime.utc(2026, 11, 23)));
      empty.setWeeklyGoal(
        WeeklyGoal(target: 1, weekStart: DateTime.utc(2026, 11, 16)),
      );
      expect(empty.weeklyAchieved, 2);
      expect(empty.weeklyProgress, 1);
      expect(
        empty
            .applicationsInPeriod(
              start: DateTime.utc(2026, 11, 16),
              end: DateTime.utc(2026, 11, 23),
            )
            .length,
        2,
      );
      empty.setWeeklyGoal(
        WeeklyGoal(target: 0, weekStart: DateTime.utc(2026, 11, 16)),
      );
      expect(empty.weeklyProgress, 0);
      expect(
        () => empty.setWeeklyGoal(
          WeeklyGoal(target: -1, weekStart: DateTime.utc(2026, 11, 16)),
        ),
        throwsArgumentError,
      );
      expect(
        () => empty.setWeeklyGoal(
          WeeklyGoal(target: 8, weekStart: DateTime.utc(2026, 11, 17)),
        ),
        throwsArgumentError,
      );
    },
  );

  test('fresh stores do not inherit mutations from another session', () {
    store.deleteApplication('app-nusa');
    final fresh = JobTrailStore.demo();
    addTearDown(fresh.dispose);
    expect(fresh.applications.length, 3);
    expect(fresh.applicationById('app-nusa'), isNotNull);
  });

  test('WIB formatting uses explicit UTC+07 independent of host timezone', () {
    expect(
      AppDates.formatWib(DateTime.utc(2026, 11, 16, 3)),
      '16/11/2026 10:00 WIB',
    );
    expect(
      AppDates.wibDate(DateTime.utc(2026, 11, 16, 18)),
      DateTime.utc(2026, 11, 17),
    );
  });
}
