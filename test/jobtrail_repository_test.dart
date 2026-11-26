import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_wire.dart';
import 'package:jobtrail/data/supabase_jobtrail_repository.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const appId = '10000000-0000-4000-8000-000000000001';
const documentId = '20000000-0000-4000-8000-000000000001';
const agendaId = '30000000-0000-4000-8000-000000000001';
const eventId = '40000000-0000-4000-8000-000000000001';

WireObject wire({
  String company = 'Synthetic Co',
  Object? salary = '2010001',
}) => {
  'reference_date': '2026-11-24',
  'reference_instant': '2026-11-23T18:00:00Z',
  'applications': [
    {
      'id': appId,
      'company': company,
      'position': 'Engineering',
      'source': 'Website perusahaan',
      'applied_on': '2026-11-23',
      'status': 'interview',
      'location': 'Surabaya',
      'work_type': 'on_site',
      'salary_monthly_idr': salary,
      'notes': '',
      'revision': 7,
    },
  ],
  'agendas': [
    {
      'id': agendaId,
      'application_id': appId,
      'type': 'test',
      'scheduled_at': '2026-11-24T09:00:00+07:00',
      'location_or_link': 'Synthetic link',
      'notes': '',
    },
  ],
  'documents': [
    {
      'id': documentId,
      'title': 'Synthetic CV',
      'category': 'cv_resume',
      'file_name': 'sample.pdf',
      'version': '1',
      'updated_at': '2026-11-23T16:30:00Z',
      'notes': '',
    },
  ],
  'application_documents': [
    {'application_id': appId, 'document_id': documentId},
  ],
  'history': [
    {
      'id': '40000000-0000-4000-8000-000000000002',
      'application_id': appId,
      'status': 'interview',
      'changed_at': '2026-11-23T16:30:00Z',
      'event_no': 2,
    },
    {
      'id': eventId,
      'application_id': appId,
      'status': 'applied',
      'changed_at': '2026-11-23T16:30:00Z',
      'event_no': 1,
    },
  ],
};

void main() {
  test(
    'decodes coherent WIB snapshot, ordering, links and wire enum codes',
    () {
      final snapshot = JobTrailWire.snapshot(wire());
      expect(snapshot.referenceDate, DateTime.utc(2026, 11, 24));
      expect(snapshot.referenceInstantUtc, DateTime.utc(2026, 11, 23, 18));
      expect(
        snapshot.applications.single.appliedAt,
        DateTime.utc(2026, 11, 23),
      );
      expect(snapshot.applications.single.source, 'Website perusahaan');
      expect(snapshot.applications.single.salary, 2010001);
      expect(snapshot.applications.single.workType, WorkType.onSite);
      expect(snapshot.applications.single.documentIds, [documentId]);
      expect(snapshot.documents.single.category, DocumentCategory.cvResume);
      expect(
        snapshot.agendas.single.scheduledAt,
        DateTime.utc(2026, 11, 24, 2),
      );
      expect(snapshot.agendas.single.type, AgendaType.test);
      expect(snapshot.history.map((event) => event.status), [
        RecruitmentStatus.applied,
        RecruitmentStatus.interview,
      ]);
      expect(snapshot.applicationRevisions[appId], 7);
      expect(() => snapshot.applications.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.applicationRevisions.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('null, exact integer and invalid civil date handling', () {
    expect(
      JobTrailWire.snapshot(wire(salary: null)).applications.single.salary,
      isNull,
    );
    expect(
      JobTrailWire.snapshot(wire(salary: '9007199254740991'))
          .applications
          .single
          .salary,
      9007199254740991,
    );
    expect(
      () => JobTrailWire.snapshot(wire(salary: '9007199254740993')),
      throwsFormatException,
    );
    expect(
      () => JobTrailWire.snapshot(wire(salary: 100)),
      throwsFormatException,
    );
    expect(() => JobTrailWire.date('2026-02-30'), throwsFormatException);
    expect(
      () => JobTrailWire.instant('2026-11-24T09:00:00'),
      throwsFormatException,
    );
  });

  test('mismatched snapshot clock and orphaned link fail atomically', () {
    expect(
      () => JobTrailWire.snapshot(wire()..['reference_date'] = '2026-11-23'),
      throwsFormatException,
    );
    expect(
      () => JobTrailWire.snapshot(wire()..['documents'] = []),
      throwsFormatException,
    );
  });

  test(
    'UUID version and variant plus identifiers are stable across an intent',
    () {
      final draft = JobTrailWire.snapshot(wire()).applications.single;
      final intent = ApplicationCreation(draft);
      expect(
        intent.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(identical(intent.draft, draft), isTrue);
      expect(ApplicationCreation(draft).id, isNot(intent.id));
      expect(() => JobTrailWire.uuid('app-local-1'), throwsFormatException);
    },
  );

  test(
    'exact RPC arguments, receipts and document relationship payload',
    () async {
      final calls = <(String, WireObject)>[];
      final repo = SupabaseJobTrailRepository((name, params) async {
        calls.add((name, params));
        return switch (name) {
          'jobtrail_load_snapshot' => wire(),
          'jobtrail_create_application' => {
            'id': appId,
            'revision': 7,
            'replayed': true,
          },
          'jobtrail_update_application' ||
          'jobtrail_change_status' => {'id': appId, 'revision': 8},
          'jobtrail_save_agenda' => {'id': agendaId, 'replayed': false},
          'jobtrail_save_document' => {
            'id': documentId,
            'updated_at': '2026-11-24T09:00:00+07:00',
            'revision': 5,
            'replayed': false,
          },
          _ => params['p_id'],
        };
      }, isActive: () => true);
      final snapshot = await repo.loadSnapshot();
      final app = snapshot.applications.single;
      expect((await repo.createApplication(appId, app)).replayed, isTrue);
      await repo.updateApplication(
        appId,
        7,
        ApplicationDraft(
          company: app.company,
          position: app.position,
          source: 'Situs perusahaan',
          appliedAt: app.appliedAt,
          status: app.status,
          location: app.location,
          workType: app.workType,
        ),
      );
      await repo.changeStatus(appId, 8, RecruitmentStatus.offering);
      expect(await repo.deleteApplication(appId, 8), appId);
      expect(
        (await repo.saveAgenda(
          snapshot.agendas.single,
          SaveMode.create,
        )).replayed,
        isFalse,
      );
      expect(await repo.deleteAgenda(agendaId, 3), agendaId);
      expect(
        (await repo.saveDocument(
          snapshot.documents.single,
          SaveMode.update,
          expectedRevision: 4,
        )).updatedAt,
        DateTime.utc(2026, 11, 24, 2),
      );
      expect(await repo.deleteDocument(documentId, 5), documentId);
      expect(calls.map((call) => call.$1), [
        'jobtrail_load_snapshot',
        'jobtrail_create_application',
        'jobtrail_update_application',
        'jobtrail_change_status',
        'jobtrail_delete_application',
        'jobtrail_save_agenda',
        'jobtrail_delete_agenda',
        'jobtrail_save_document',
        'jobtrail_delete_document',
      ]);
      expect(calls[0].$2, isEmpty);
      expect(calls[1].$2, {
        'p_id': appId,
        'p_company': 'Synthetic Co',
        'p_position': 'Engineering',
        'p_source': 'Website perusahaan',
        'p_applied_on': '2026-11-23',
        'p_status': 'interview',
        'p_location': 'Surabaya',
        'p_work_type': 'on_site',
        'p_salary_monthly_idr': '2010001',
        'p_notes': '',
        'p_document_ids': [documentId],
      });
      expect(calls[2].$2['p_expected_revision'], 7);
      expect(calls[2].$2['p_source'], 'Situs perusahaan');
      expect(calls[2].$2['p_salary_monthly_idr'], isNull);
      expect(calls[2].$2['p_document_ids'], isEmpty);
      expect(calls[3].$2, {
        'p_id': appId,
        'p_expected_revision': 8,
        'p_status': 'offering',
      });
      expect(calls[4].$2, {'p_id': appId, 'p_expected_revision': 8});
      expect(calls[5].$2, {
        'p_id': agendaId,
        'p_create': true,
        'p_application_id': appId,
        'p_type': 'test',
        'p_scheduled_at': '2026-11-24T02:00:00.000Z',
        'p_location_or_link': 'Synthetic link',
        'p_notes': '',
      });
      expect(calls[7].$2, {
        'p_id': documentId,
        'p_create': false,
        'p_title': 'Synthetic CV',
        'p_category': 'cv_resume',
        'p_file_name': 'sample.pdf',
        'p_version': '1',
        'p_notes': '',
        'p_expected_revision': 4,
      });
      expect(calls[6].$2, {'p_id': agendaId, 'p_expected_revision': 3});
      expect(calls[8].$2, {'p_id': documentId, 'p_expected_revision': 5});
      expect(calls.every((call) => !call.$2.containsKey('p_user_id')), isTrue);
    },
  );

  for (final entry in {
    'PGRST301': RepositoryIssue.authentication,
    '42501': RepositoryIssue.forbidden,
    'JT001': RepositoryIssue.unavailable,
    'JT002': RepositoryIssue.revisionConflict,
    'JT003': RepositoryIssue.documentUnavailable,
    'JT004': RepositoryIssue.createConflict,
    'JT005': RepositoryIssue.documentInUse,
    '22023': RepositoryIssue.validation,
    'unrecognized': RepositoryIssue.unexpected,
  }.entries) {
    test('maps ${entry.key} without exposing the server error', () async {
      final repo = SupabaseJobTrailRepository((_, _) async {
        throw PostgrestException(
          message: 'synthetic internal detail',
          code: entry.key,
        );
      }, isActive: () => true);
      await expectLater(
        repo.deleteDocument(documentId, 1),
        throwsA(
          isA<RepositoryFailure>().having((e) => e.issue, 'issue', entry.value),
        ),
      );
    });
  }

  test(
    'explicit create retry preserves identical ID and payload after timeout',
    () async {
      final calls = <WireObject>[];
      final draft = JobTrailWire.snapshot(wire()).applications.single;
      final intent = ApplicationCreation(draft);
      final repo = SupabaseJobTrailRepository((_, params) async {
        calls.add(params);
        if (calls.length == 1) throw TimeoutException('synthetic timeout');
        return {'id': intent.id, 'revision': 1, 'replayed': true};
      }, isActive: () => true);
      await expectLater(
        repo.createApplication(intent.id, intent.draft),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.writeOutcomeUnknown,
            'ambiguous',
            true,
          ),
        ),
      );
      expect(
        (await repo.createApplication(intent.id, intent.draft)).replayed,
        isTrue,
      );
      expect(calls[1], calls[0]);
    },
  );

  test(
    'inactive owner cannot dispatch, and delayed RPC cannot publish',
    () async {
      final completion = Completer<Object?>();
      var active = true;
      var calls = 0;
      final repo = SupabaseJobTrailRepository((_, _) {
        calls++;
        return completion.future;
      }, isActive: () => active);
      final first = repo.loadSnapshot();
      active = false;
      completion.complete(wire());
      final denied = throwsA(
        isA<RepositoryFailure>().having(
          (e) => e.issue,
          'issue',
          RepositoryIssue.authentication,
        ),
      );
      await expectLater(first, denied);
      await expectLater(repo.loadSnapshot(), denied);
      expect(calls, 1);
    },
  );
}
