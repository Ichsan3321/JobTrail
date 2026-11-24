import '../core/constants/app_dates.dart';
import '../models/agenda.dart';
import '../models/app_document.dart';
import '../models/application.dart';
import '../models/recruitment_status.dart';
import '../models/status_history.dart';
import 'jobtrail_repository.dart';

typedef WireObject = Map<String, Object?>;

abstract final class JobTrailWire {
  static WireObject object(Object? raw) {
    if (raw is! Map<String, Object?>) throw const FormatException('object');
    return raw;
  }

  static List<WireObject> rows(WireObject root, String key) {
    final value = root[key];
    if (value is! List) throw const FormatException('array');
    return value.map(object).toList();
  }

  static String text(Object? value) {
    if (value is! String) throw const FormatException('text');
    return value;
  }

  static String uuid(Object? value) {
    final id = text(value);
    if (!RegExp(
      r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(id)) {
      throw const FormatException('uuid');
    }
    return id.toLowerCase();
  }

  static int positiveInt(Object? value) {
    if (value is! int || value < 1 || value > 2147483647) {
      throw const FormatException('positive integer');
    }
    return value;
  }

  static bool flag(Object? value) {
    if (value is! bool) throw const FormatException('boolean');
    return value;
  }

  static DateTime date(Object? value) {
    final input = text(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
      throw const FormatException('date');
    }
    final parsed = DateTime.parse('${input}T00:00:00Z');
    if (dateCode(parsed) != input) throw const FormatException('date');
    return parsed;
  }

  static String dateCode(DateTime value) {
    if (!AppDates.isDate(value) || value.year < 1 || value.year > 9999) {
      throw const FormatException('civil date');
    }
    return value.toIso8601String().substring(0, 10);
  }

  static DateTime instant(Object? value) {
    final input = text(value);
    if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(input) ||
        input.length < 20) {
      throw const FormatException('offset timestamp');
    }
    date(input.substring(0, 10));
    return DateTime.parse(input).toUtc();
  }

  static String _instantCode(DateTime value) => value.toUtc().toIso8601String();

  static T _enum<T extends Enum>(List<T> values, Object? value) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw const FormatException('enum code');
  }

  static int? _salary(Object? value) {
    if (value == null) return null;
    final input = text(value);
    final exact = BigInt.tryParse(input);
    if (!RegExp(r'^\d+$').hasMatch(input) ||
        exact == null ||
        exact > BigInt.from(9007199254740991)) {
      throw const FormatException(
        'salary outside exact Dart Web integer range',
      );
    }
    return exact.toInt();
  }

  static JobTrailSnapshot snapshot(Object? raw) {
    final root = object(raw);
    final referenceDate = date(root['reference_date']);
    final referenceInstant = instant(root['reference_instant']);
    if (AppDates.wibDate(referenceInstant) != referenceDate) {
      throw const FormatException('WIB reference mismatch');
    }
    final documents = rows(root, 'documents')
        .map(
          (row) => AppDocument(
            id: uuid(row['id']),
            title: text(row['title']),
            category: row['category'] == 'cv_resume'
                ? DocumentCategory.cvResume
                : _enum([DocumentCategory.portfolio], row['category']),
            fileName: text(row['file_name']),
            version: text(row['version']),
            updatedAt: instant(row['updated_at']),
            notes: text(row['notes']),
          ),
        )
        .toList();
    final documentIds = documents.map((item) => item.id).toSet();
    final links = <String, Set<String>>{};
    for (final row in rows(root, 'application_documents')) {
      final app = uuid(row['application_id']);
      final doc = uuid(row['document_id']);
      if (!documentIds.contains(doc) ||
          !links.putIfAbsent(app, () => {}).add(doc)) {
        throw const FormatException('invalid document link');
      }
    }
    final revisions = <String, int>{};
    final applications = rows(root, 'applications').map((row) {
      final id = uuid(row['id']);
      if (revisions.containsKey(id)) {
        throw const FormatException('duplicate application');
      }
      revisions[id] = positiveInt(row['revision']);
      return Application(
        id: id,
        company: text(row['company']),
        position: text(row['position']),
        source: text(row['source']),
        appliedAt: date(row['applied_on']),
        status: _enum(RecruitmentStatus.values, row['status']),
        location: text(row['location']),
        workType: row['work_type'] == 'on_site'
            ? WorkType.onSite
            : _enum([WorkType.hybrid, WorkType.remote], row['work_type']),
        salary: _salary(row['salary_monthly_idr']),
        notes: text(row['notes']),
        documentIds: links.remove(id)?.toList() ?? const [],
      );
    }).toList();
    String parent(Object? value) {
      final id = uuid(value);
      if (!revisions.containsKey(id)) {
        throw const FormatException('missing parent');
      }
      return id;
    }

    final agendas = rows(root, 'agendas')
        .map(
          (row) => Agenda(
            id: uuid(row['id']),
            applicationId: parent(row['application_id']),
            type: _enum(AgendaType.values, row['type']),
            scheduledAt: instant(row['scheduled_at']),
            locationOrLink: text(row['location_or_link']),
            notes: text(row['notes']),
          ),
        )
        .toList();
    final events =
        rows(root, 'history')
            .map(
              (row) => (
                event: StatusHistory(
                  id: uuid(row['id']),
                  applicationId: parent(row['application_id']),
                  status: _enum(RecruitmentStatus.values, row['status']),
                  changedAt: instant(row['changed_at']),
                ),
                sequence: positiveInt(row['event_no']),
              ),
            )
            .toList()
          ..sort((a, b) {
            final parentOrder = a.event.applicationId.compareTo(
              b.event.applicationId,
            );
            return parentOrder == 0
                ? a.sequence.compareTo(b.sequence)
                : parentOrder;
          });
    final history = events.map((row) => row.event).toList();
    if (links.isNotEmpty ||
        documentIds.length != documents.length ||
        agendas.map((item) => item.id).toSet().length != agendas.length ||
        history.map((item) => item.id).toSet().length != history.length ||
        events
                .map((row) => (row.event.applicationId, row.sequence))
                .toSet()
                .length !=
            events.length) {
      throw const FormatException('invalid snapshot relationships');
    }
    return JobTrailSnapshot(
      referenceDate: referenceDate,
      referenceInstantUtc: referenceInstant,
      applications: applications,
      agendas: agendas,
      documents: documents,
      history: history,
      applicationRevisions: revisions,
    );
  }

  static WireObject application(String id, ApplicationDraft draft) => {
    'p_id': uuid(id),
    'p_company': draft.company,
    'p_position': draft.position,
    'p_source': draft.source,
    'p_applied_on': dateCode(draft.appliedAt),
    'p_status': draft.status.name,
    'p_location': draft.location,
    'p_work_type': draft.workType == WorkType.onSite
        ? 'on_site'
        : draft.workType.name,
    'p_salary_monthly_idr': draft.salary == null
        ? null
        : _salary(draft.salary.toString()).toString(),
    'p_notes': draft.notes,
    'p_document_ids': draft.documentIds.map(uuid).toList(),
  };

  static WireObject agenda(Agenda item, SaveMode mode) => {
    'p_id': uuid(item.id),
    'p_create': mode == SaveMode.create,
    'p_application_id': uuid(item.applicationId),
    'p_type': item.type.name,
    'p_scheduled_at': _instantCode(item.scheduledAt),
    'p_location_or_link': item.locationOrLink,
    'p_notes': item.notes,
  };

  static WireObject document(AppDocument item, SaveMode mode) => {
    'p_id': uuid(item.id),
    'p_create': mode == SaveMode.create,
    'p_title': item.title,
    'p_category': item.category == DocumentCategory.cvResume
        ? 'cv_resume'
        : 'portfolio',
    'p_file_name': item.fileName,
    'p_version': item.version,
    'p_notes': item.notes,
  };
}
