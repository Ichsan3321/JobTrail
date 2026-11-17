import 'recruitment_status.dart';

enum WorkType {
  onSite('On-site'),
  hybrid('Hybrid'),
  remote('Remote');

  const WorkType(this.label);
  final String label;
}

/// Shared form payload. Salary is optional monthly IDR, not a formatted string.
class ApplicationDraft {
  ApplicationDraft({
    required this.company,
    required this.position,
    required this.source,
    required this.appliedAt,
    required this.status,
    required this.location,
    required this.workType,
    this.salary,
    this.notes = '',
    List<String> documentIds = const [],
  }) : documentIds = List.unmodifiable(documentIds);
  final String company;
  final String position;
  final String source;
  final DateTime appliedAt;
  final RecruitmentStatus status;
  final String location;
  final WorkType workType;
  final int? salary;
  final String notes;
  final List<String> documentIds;
}

/// Immutable entity. Updates replace the payload while preserving [id].
class Application extends ApplicationDraft {
  Application({
    required this.id,
    required super.company,
    required super.position,
    required super.source,
    required super.appliedAt,
    required super.status,
    required super.location,
    required super.workType,
    super.salary,
    super.notes,
    super.documentIds,
  });
  final String id;
  factory Application.fromDraft(String id, ApplicationDraft draft) =>
      Application(
        id: id,
        company: draft.company.trim(),
        position: draft.position.trim(),
        source: draft.source.trim(),
        appliedAt: draft.appliedAt,
        status: draft.status,
        location: draft.location.trim(),
        workType: draft.workType,
        salary: draft.salary,
        notes: draft.notes,
        documentIds: draft.documentIds,
      );
  ApplicationDraft withStatus(RecruitmentStatus value) => ApplicationDraft(
    company: company,
    position: position,
    source: source,
    appliedAt: appliedAt,
    status: value,
    location: location,
    workType: workType,
    salary: salary,
    notes: notes,
    documentIds: documentIds,
  );
}
