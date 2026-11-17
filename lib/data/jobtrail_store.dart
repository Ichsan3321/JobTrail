import 'package:flutter/foundation.dart';

import '../core/constants/app_dates.dart';
import '../models/agenda.dart';
import '../models/app_document.dart';
import '../models/application.dart';
import '../models/recruitment_status.dart';
import '../models/status_history.dart';
import '../models/weekly_goal.dart';
import 'mock_data.dart';

/// Single in-memory source. Consumers receive immutable snapshots.
/// Inject a clock for live mutation timestamps; demo defaults to its fixed anchor.
class JobTrailStore extends ChangeNotifier {
  JobTrailStore._({
    required this.referenceDate,
    required this._weeklyGoal,
    required this._clock,
    Iterable<Application> applications = const [],
    Iterable<Agenda> agendas = const [],
    Iterable<AppDocument> documents = const [],
    Iterable<StatusHistory> history = const [],
  }) : _applications = {for (final value in applications) value.id: value},
       _agendas = {for (final value in agendas) value.id: value},
       _documents = {for (final value in documents) value.id: value},
       _history = List.of(history);

  factory JobTrailStore.demo({DateTime Function()? clock}) => JobTrailStore._(
    referenceDate: MockData.referenceDate,
    weeklyGoal: MockData.weeklyGoal,
    clock: clock ?? () => MockData.referenceInstant,
    applications: MockData.applications,
    agendas: MockData.agendas,
    documents: MockData.documents,
    history: MockData.history,
  );

  factory JobTrailStore.empty({
    DateTime? referenceDate,
    DateTime Function()? clock,
  }) {
    final date = referenceDate ?? MockData.referenceDate;
    if (!AppDates.isDate(date)) {
      throw ArgumentError('referenceDate harus tanggal UTC midnight.');
    }
    return JobTrailStore._(
      referenceDate: date,
      weeklyGoal: WeeklyGoal(
        target: 8,
        weekStart: date.subtract(Duration(days: date.weekday - 1)),
      ),
      clock: clock ?? () => DateTime.utc(date.year, date.month, date.day, 2),
    );
  }

  final DateTime referenceDate;
  final DateTime Function() _clock;
  final Map<String, Application> _applications;
  final Map<String, Agenda> _agendas;
  final Map<String, AppDocument> _documents;
  final List<StatusHistory> _history;
  WeeklyGoal _weeklyGoal;
  int _sequence = 0;

  List<Application> get applications => List.unmodifiable(_applications.values);
  List<Agenda> get agendas => List.unmodifiable(_agendas.values);
  List<AppDocument> get documents => List.unmodifiable(_documents.values);
  List<StatusHistory> get history => List.unmodifiable(_history);
  WeeklyGoal get weeklyGoal => _weeklyGoal;
  Application? applicationById(String id) => _applications[id];
  AppDocument? documentById(String id) => _documents[id];

  /// Session-unique IDs for new agenda/document metadata; keep the ID on edit.
  String nextAgendaId() => _newId('agenda');
  String nextDocumentId() => _newId('doc');

  List<Agenda> agendasFor(String applicationId) => List.unmodifiable(
    _agendas.values
        .where((item) => item.applicationId == applicationId)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)),
  );
  List<StatusHistory> historyFor(String applicationId) => List.unmodifiable(
    _history.where((item) => item.applicationId == applicationId).toList()
      ..sort((a, b) {
        final order = a.changedAt.compareTo(b.changedAt);
        return order != 0
            ? order
            : _history.indexOf(a).compareTo(_history.indexOf(b));
      }),
  );

  /// Inclusive start, exclusive end; comparisons use appliedAt civil dates.
  List<Application> applicationsInPeriod({DateTime? start, DateTime? end}) =>
      List.unmodifiable(
        _applications.values.where(
          (item) =>
              (start == null || !item.appliedAt.isBefore(start)) &&
              (end == null || item.appliedAt.isBefore(end)),
        ),
      );

  Map<RecruitmentStatus, int> distribution({DateTime? start, DateTime? end}) {
    final items = applicationsInPeriod(start: start, end: end);
    return Map.unmodifiable({
      for (final status in RecruitmentStatus.values)
        status: items.where((item) => item.status == status).length,
    });
  }

  int get weeklyAchieved => applicationsInPeriod(
    start: _weeklyGoal.weekStart,
    end: _weeklyGoal.weekStart.add(const Duration(days: 7)),
  ).length;
  double get weeklyProgress => _weeklyGoal.target == 0
      ? 0
      : (weeklyAchieved / _weeklyGoal.target).clamp(0.0, 1.0);

  String addApplication(ApplicationDraft draft) {
    _validateApplication(draft);
    final timestamp = _historyTimestamp(draft.appliedAt);
    final id = _newId('app');
    _applications[id] = Application.fromDraft(id, draft);
    _recordStatus(id, draft.status, timestamp);
    notifyListeners();
    return id;
  }

  void updateApplication(String id, ApplicationDraft draft) {
    final previous = _requireApplication(id);
    _validateApplication(draft);
    if (_agendas.values.any(
      (agenda) =>
          agenda.applicationId == id &&
          AppDates.wibDate(agenda.scheduledAt).isBefore(draft.appliedAt),
    )) {
      throw ArgumentError(
        'Tanggal lamaran tidak boleh melewati agenda terkait.',
      );
    }
    final latestHistory = historyFor(id);
    if (latestHistory.any(
      (item) => AppDates.wibDate(item.changedAt).isBefore(draft.appliedAt),
    )) {
      throw ArgumentError(
        'Tanggal lamaran tidak boleh melewati riwayat status.',
      );
    }
    final changed = previous.status != draft.status;
    final timestamp = changed ? _historyTimestamp(draft.appliedAt) : null;
    if (timestamp != null &&
        latestHistory.isNotEmpty &&
        timestamp.isBefore(latestHistory.last.changedAt)) {
      throw ArgumentError('Waktu perubahan mendahului riwayat status.');
    }
    _applications[id] = Application.fromDraft(id, draft);
    if (timestamp != null) _recordStatus(id, draft.status, timestamp);
    notifyListeners();
  }

  void changeStatus(String id, RecruitmentStatus status) {
    final app = _requireApplication(id);
    if (app.status == status) return;
    updateApplication(id, app.withStatus(status));
  }

  /// Caller must confirm deletion in UI. Shared documents are retained.
  void deleteApplication(String id) {
    _requireApplication(id);
    _applications.remove(id);
    _agendas.removeWhere((_, value) => value.applicationId == id);
    _history.removeWhere((value) => value.applicationId == id);
    notifyListeners();
  }

  /// Upsert metadata by stable ID. Does not upload or read a file.
  void saveDocument(AppDocument document) {
    _requireText(document.id, 'ID dokumen');
    _requireText(document.title, 'Judul dokumen');
    _requireText(document.fileName, 'Nama file');
    _requireText(document.version, 'Versi dokumen');
    if (!document.updatedAt.isUtc) throw ArgumentError('updatedAt harus UTC.');
    _documents[document.id] = document;
    notifyListeners();
  }

  void deleteDocument(String id) {
    if (!_documents.containsKey(id)) {
      throw StateError('Dokumen tidak ditemukan: $id');
    }
    if (_applications.values.any((item) => item.documentIds.contains(id))) {
      throw StateError(
        'Dokumen masih dipakai lamaran. Lepaskan referensinya dahulu.',
      );
    }
    _documents.remove(id);
    notifyListeners();
  }

  /// Upsert agenda. The caller supplies a stable ID; no orphan is accepted.
  void saveAgenda(Agenda agenda) {
    _requireText(agenda.id, 'ID agenda');
    _requireText(agenda.locationOrLink, 'Lokasi/link agenda');
    final app = _requireApplication(agenda.applicationId);
    if (!agenda.scheduledAt.isUtc ||
        AppDates.wibDate(agenda.scheduledAt).isBefore(app.appliedAt)) {
      throw ArgumentError(
        'Agenda harus UTC dan tidak mendahului tanggal lamaran.',
      );
    }
    _agendas[agenda.id] = agenda;
    notifyListeners();
  }

  void deleteAgenda(String id) {
    if (_agendas.remove(id) == null) {
      throw StateError('Agenda tidak ditemukan: $id');
    }
    notifyListeners();
  }

  void setWeeklyGoal(WeeklyGoal goal) {
    if (goal.target < 0 ||
        !AppDates.isDate(goal.weekStart) ||
        goal.weekStart.weekday != DateTime.monday) {
      throw ArgumentError(
        'Target minimal 0 dan weekStart harus Senin (tanggal UTC).',
      );
    }
    _weeklyGoal = goal;
    notifyListeners();
  }

  Application _requireApplication(String id) =>
      _applications[id] ?? (throw StateError('Lamaran tidak ditemukan: $id'));
  void _requireText(String text, String label) {
    if (text.trim().isEmpty) throw ArgumentError('$label wajib diisi.');
  }

  void _validateApplication(ApplicationDraft draft) {
    _requireText(draft.company, 'Perusahaan');
    _requireText(draft.position, 'Posisi');
    _requireText(draft.source, 'Sumber');
    _requireText(draft.location, 'Lokasi');
    if (!AppDates.isDate(draft.appliedAt) ||
        draft.appliedAt.isAfter(referenceDate)) {
      throw ArgumentError(
        'Tanggal lamaran harus tanggal UTC dan tidak melewati tanggal acuan demo.',
      );
    }
    if (draft.salary != null && draft.salary! < 0) {
      throw ArgumentError('Gaji minimal 0.');
    }
    if (draft.documentIds.toSet().length != draft.documentIds.length ||
        draft.documentIds.any((id) => !_documents.containsKey(id))) {
      throw ArgumentError('Referensi dokumen harus unik dan tersedia.');
    }
  }

  DateTime _historyTimestamp(DateTime appliedAt) {
    final timestamp = _clock().toUtc();
    if (AppDates.wibDate(timestamp).isBefore(appliedAt)) {
      throw ArgumentError('Clock mendahului tanggal lamaran.');
    }
    return timestamp;
  }

  String _newId(String prefix) {
    String id;
    do {
      id = '$prefix-local-${++_sequence}';
    } while (_applications.containsKey(id) ||
        _agendas.containsKey(id) ||
        _documents.containsKey(id) ||
        _history.any((item) => item.id == id));
    return id;
  }

  void _recordStatus(
    String applicationId,
    RecruitmentStatus status,
    DateTime timestamp,
  ) => _history.add(
    StatusHistory(
      id: _newId('history'),
      applicationId: applicationId,
      status: status,
      changedAt: timestamp,
    ),
  );
}
