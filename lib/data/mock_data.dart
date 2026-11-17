import '../models/agenda.dart';
import '../models/app_document.dart';
import '../models/application.dart';
import '../models/recruitment_status.dart';
import '../models/status_history.dart';
import '../models/weekly_goal.dart';

/// One provisional foundation fixture. Review conflicts in docs/DUMMY_DATA.md.
abstract final class MockData {
  static final referenceDate = DateTime.utc(2026, 11, 17);
  static final referenceInstant = DateTime.parse('2026-11-17T09:00:00+07:00')
      .toUtc();
  static final weeklyGoal = WeeklyGoal(
    target: 8,
    weekStart: DateTime.utc(2026, 11, 16),
  );
  static final documents = List<AppDocument>.unmodifiable([
    AppDocument(
      id: 'doc-cv',
      title: 'CV Demo',
      category: DocumentCategory.cvResume,
      fileName: 'cv_demo.pdf',
      version: '1',
      updatedAt: DateTime.utc(2026, 11, 10),
    ),
    AppDocument(
      id: 'doc-portfolio',
      title: 'Portofolio Demo',
      category: DocumentCategory.portfolio,
      fileName: 'portofolio_demo.pdf',
      version: '1',
      updatedAt: DateTime.utc(2026, 11, 10),
    ),
  ]);
  static final applications = List<Application>.unmodifiable([
    Application(
      id: 'app-lentera',
      company: 'Lentera Tech',
      position: 'Frontend Developer Intern',
      source: 'Situs perusahaan',
      appliedAt: DateTime.utc(2026, 11, 12),
      status: RecruitmentStatus.applied,
      location: 'Bandung',
      workType: WorkType.hybrid,
      documentIds: ['doc-cv'],
    ),
    Application(
      id: 'app-nusa',
      company: 'Nusa Digital',
      position: 'UI/UX Designer Intern',
      source: 'Situs perusahaan',
      appliedAt: DateTime.utc(2026, 11, 1),
      status: RecruitmentStatus.interview,
      location: 'Jakarta',
      workType: WorkType.onSite,
      documentIds: ['doc-cv', 'doc-portfolio'],
    ),
    Application(
      id: 'app-arunika',
      company: 'Arunika Finance',
      position: 'Business Analyst Intern',
      source: 'Situs perusahaan',
      appliedAt: DateTime.utc(2026, 11, 5),
      status: RecruitmentStatus.screening,
      location: 'Jakarta',
      workType: WorkType.hybrid,
      documentIds: ['doc-cv'],
    ),
  ]);
  static final agendas = List<Agenda>.unmodifiable([
    Agenda(
      id: 'agenda-nusa',
      applicationId: 'app-nusa',
      type: AgendaType.interview,
      scheduledAt: DateTime.parse('2026-11-16T10:00:00+07:00').toUtc(),
      locationOrLink: 'Google Meet (demo)',
    ),
    Agenda(
      id: 'agenda-arunika',
      applicationId: 'app-arunika',
      type: AgendaType.test,
      scheduledAt: DateTime.parse('2026-11-17T13:00:00+07:00').toUtc(),
      locationOrLink: 'Link via email (demo)',
    ),
  ]);
  static final history = List<StatusHistory>.unmodifiable([
    for (final app in applications)
      StatusHistory(
        id: 'history-${app.id}-initial',
        applicationId: app.id,
        status: RecruitmentStatus.applied,
        changedAt: DateTime.parse(
          '${app.appliedAt.toIso8601String().substring(0, 10)}T09:00:00+07:00',
        ).toUtc(),
      ),
    StatusHistory(
      id: 'history-nusa-interview',
      applicationId: 'app-nusa',
      status: RecruitmentStatus.interview,
      changedAt: DateTime.utc(2026, 11, 13, 2),
    ),
    StatusHistory(
      id: 'history-arunika-screening',
      applicationId: 'app-arunika',
      status: RecruitmentStatus.screening,
      changedAt: DateTime.utc(2026, 11, 12, 2),
    ),
  ]);
}
