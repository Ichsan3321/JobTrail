import 'package:flutter/foundation.dart';

import '../core/constants/app_dates.dart';
import '../models/agenda.dart';
import '../models/app_document.dart';
import '../models/application.dart';
import '../models/recruitment_status.dart';
import '../models/status_history.dart';
import '../models/weekly_goal.dart';
import 'jobtrail_repository.dart';
import 'mock_data.dart';

enum StorePhase { loading, ready, empty, error }

/// A receipt proves the RPC committed. The caller must wait for refresh before
/// opening a route that expects the record to be present in the snapshot.
class CommittedMutation<T> {
  const CommittedMutation(this.receipt, {required this.snapshotCurrent});
  final T receipt;
  final bool snapshotCurrent;
}

/// Shared source for explicit mock mode and authenticated snapshots.
/// Inject a clock for live mutation timestamps; demo defaults to its fixed anchor.
class JobTrailStore extends ChangeNotifier {
  JobTrailStore._({
    required this._referenceDate,
    this._repository,
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

  factory JobTrailStore.connected(JobTrailRepository repository) {
    final date = AppDates.wibDate(DateTime.now());
    return JobTrailStore._(
      referenceDate: date,
      weeklyGoal: WeeklyGoal(target: 8, weekStart: _weekStart(date)),
      clock: DateTime.now,
      repository: repository,
    ).._phase = StorePhase.loading;
  }

  static DateTime _weekStart(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));

  DateTime _referenceDate;
  DateTime get referenceDate => _referenceDate;
  DateTime? _serverInstant;
  final DateTime Function() _clock;
  final JobTrailRepository? _repository;
  final Map<String, int> _revisions = {};
  StorePhase _phase = StorePhase.ready;
  RepositoryFailure? _failure;
  bool _disposed = false;
  bool _mutating = false;
  Future<void>? _refresh;

  bool get isConnected => _repository != null;
  bool get allowsLocalWrites => !isConnected && !_disposed;
  StorePhase get phase => _phase;
  RepositoryFailure? get failure => _failure;
  bool get isMutating => _mutating;
  bool get isRefreshing => _refresh != null;
  bool get hasSnapshot => _serverInstant != null;
  int? applicationRevision(String id) => _revisions[id];

  void _requireLocal() {
    if (!allowsLocalWrites) {
      throw StateError('Aksi ini memerlukan integrasi penyimpanan server.');
    }
  }

  void _requireActive() {
    if (_disposed) {
      throw const RepositoryFailure(RepositoryIssue.authentication);
    }
  }

  Future<void> refresh() {
    final repository = _repository;
    if (_disposed || repository == null || _mutating) return Future.value();
    return _refresh ??= Future<void>.microtask(() async {
      try {
        if (_disposed) return;
        if (!hasSnapshot) _phase = StorePhase.loading;
        notifyListeners();
        await _reconcile(repository);
      } finally {
        _refresh = null;
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<bool> _reconcile(JobTrailRepository repository) async {
    try {
      final snapshot = await repository.loadSnapshot();
      if (_disposed) return false;
      _applications
        ..clear()
        ..addEntries(
          snapshot.applications.map((item) => MapEntry(item.id, item)),
        );
      _agendas
        ..clear()
        ..addEntries(snapshot.agendas.map((item) => MapEntry(item.id, item)));
      _documents
        ..clear()
        ..addEntries(snapshot.documents.map((item) => MapEntry(item.id, item)));
      _history
        ..clear()
        ..addAll(snapshot.history);
      _revisions
        ..clear()
        ..addAll(snapshot.applicationRevisions);
      _referenceDate = snapshot.referenceDate;
      _serverInstant = snapshot.referenceInstantUtc;
      _weeklyGoal = WeeklyGoal(target: 8, weekStart: _weekStart(referenceDate));
      _phase = _applications.isEmpty && _agendas.isEmpty && _documents.isEmpty
          ? StorePhase.empty
          : StorePhase.ready;
      _failure = null;
      return true;
    } catch (error) {
      if (_disposed) return false;
      _phase = StorePhase.error;
      _failure = error is RepositoryFailure
          ? error
          : const RepositoryFailure(RepositoryIssue.unexpected);
      if (_failure?.issue == RepositoryIssue.authentication) _clearSnapshot();
      return false;
    }
  }

  Future<CommittedMutation<T>> _mutate<T>(
    Future<T> Function(JobTrailRepository repository) operation,
  ) async {
    _requireActive();
    final repository = _repository;
    if (repository == null ||
        _mutating ||
        isRefreshing ||
        (_phase != StorePhase.ready && _phase != StorePhase.empty)) {
      throw const RepositoryFailure(RepositoryIssue.busy);
    }
    _mutating = true;
    notifyListeners();
    try {
      final receipt = await operation(repository);
      _requireActive();
      final current = await _reconcile(repository);
      _requireActive();
      return CommittedMutation(receipt, snapshotCurrent: current);
    } on RepositoryFailure catch (failure) {
      _requireActive();
      if (failure.issue == RepositoryIssue.authentication) {
        _clearSnapshot();
        _failure = failure;
        _phase = StorePhase.error;
      } else if (failure.writeOutcomeUnknown ||
          failure.issue == RepositoryIssue.revisionConflict ||
          failure.issue == RepositoryIssue.unavailable ||
          failure.issue == RepositoryIssue.documentUnavailable) {
        await _reconcile(repository);
        _requireActive();
      }
      rethrow;
    } finally {
      _mutating = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<CommittedMutation<ApplicationCreateReceipt>> createApplicationRemote(
    ApplicationCreation intent,
  ) => _mutate((repo) => repo.createApplication(intent.id, intent.draft));

  Future<CommittedMutation<ApplicationReceipt>> updateApplicationRemote(
    String id,
    int expectedRevision,
    ApplicationDraft draft,
  ) => _mutate((repo) => repo.updateApplication(id, expectedRevision, draft));

  Future<CommittedMutation<ApplicationReceipt>> changeStatusRemote(
    String id,
    int expectedRevision,
    RecruitmentStatus status,
  ) => _mutate((repo) => repo.changeStatus(id, expectedRevision, status));

  Future<CommittedMutation<String>> deleteApplicationRemote(
    String id,
    int expectedRevision,
  ) => _mutate((repo) => repo.deleteApplication(id, expectedRevision));

  Future<CommittedMutation<AgendaReceipt>> saveAgendaRemote(
    Agenda item,
    SaveMode mode,
  ) => _mutate((repo) => repo.saveAgenda(item, mode));

  Future<CommittedMutation<String>> deleteAgendaRemote(String id) =>
      _mutate((repo) => repo.deleteAgenda(id));

  Future<CommittedMutation<DocumentReceipt>> saveDocumentRemote(
    AppDocument item,
    SaveMode mode,
  ) => _mutate((repo) => repo.saveDocument(item, mode));

  Future<CommittedMutation<String>> deleteDocumentRemote(String id) =>
      _mutate((repo) => repo.deleteDocument(id));

  @override
  void dispose() {
    _disposed = true;
    _repository?.dispose();
    if (isConnected) _clearSnapshot();
    super.dispose();
  }

  void _clearSnapshot() {
    _applications.clear();
    _agendas.clear();
    _documents.clear();
    _history.clear();
    _revisions.clear();
    _serverInstant = null;
  }

  /// Current injected reference instant, normalized to UTC.
  DateTime get referenceInstantUtc => _serverInstant ?? _clock().toUtc();
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
  String nextAgendaId() => isConnected ? newRecordId() : _newId('agenda');
  String nextDocumentId() => isConnected ? newRecordId() : _newId('doc');

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
    _requireLocal();
    _validateApplication(draft);
    final timestamp = _historyTimestamp(draft.appliedAt);
    final id = _newId('app');
    _applications[id] = Application.fromDraft(id, draft);
    _recordStatus(id, draft.status, timestamp);
    notifyListeners();
    return id;
  }

  void updateApplication(String id, ApplicationDraft draft) {
    _requireLocal();
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
    _requireLocal();
    final app = _requireApplication(id);
    if (app.status == status) return;
    updateApplication(id, app.withStatus(status));
  }

  /// Caller must confirm deletion in UI. Shared documents are retained.
  void deleteApplication(String id) {
    _requireLocal();
    _requireApplication(id);
    _applications.remove(id);
    _agendas.removeWhere((_, value) => value.applicationId == id);
    _history.removeWhere((value) => value.applicationId == id);
    notifyListeners();
  }

  /// Upsert metadata by stable ID. Does not upload or read a file.
  void saveDocument(AppDocument document) {
    _requireLocal();
    _requireText(document.id, 'ID dokumen');
    _requireText(document.title, 'Judul dokumen');
    _requireText(document.fileName, 'Nama file');
    _requireText(document.version, 'Versi dokumen');
    if (!document.updatedAt.isUtc) throw ArgumentError('updatedAt harus UTC.');
    _documents[document.id] = document;
    notifyListeners();
  }

  void deleteDocument(String id) {
    _requireLocal();
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
    _requireLocal();
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
    _requireLocal();
    if (_agendas.remove(id) == null) {
      throw StateError('Agenda tidak ditemukan: $id');
    }
    notifyListeners();
  }

  void setWeeklyGoal(WeeklyGoal goal) {
    _requireLocal();
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
    final timestamp = referenceInstantUtc;
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
