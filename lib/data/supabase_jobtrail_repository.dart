import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/agenda.dart';
import '../models/app_document.dart';
import '../models/application.dart';
import '../models/recruitment_status.dart';
import 'jobtrail_repository.dart';
import 'jobtrail_wire.dart';

typedef ScopedRpc = Future<Object?> Function(String name, WireObject arguments);

class SupabaseJobTrailRepository implements JobTrailRepository {
  SupabaseJobTrailRepository(
    this._rpc, {
    required this._isActive,
    this._onDispose,
  });

  final ScopedRpc _rpc;
  final bool Function() _isActive;
  final void Function()? _onDispose;
  bool _disposed = false;

  void _checkScope() {
    if (_disposed || !_isActive()) {
      throw const RepositoryFailure(RepositoryIssue.authentication);
    }
  }

  Future<T> _call<T>(
    String name,
    WireObject Function() args,
    T Function(Object? value) decode, {
    bool write = true,
  }) async {
    _checkScope();
    final WireObject parameters;
    try {
      parameters = args();
    } on FormatException {
      throw const RepositoryFailure(RepositoryIssue.validation);
    }
    try {
      final raw = await _rpc('jobtrail_$name', parameters);
      _checkScope();
      return decode(raw);
    } on RepositoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      _checkScope();
      final issue = switch (error.code) {
        'PGRST301' || 'PGRST303' || '401' => RepositoryIssue.authentication,
        '42501' || '403' => RepositoryIssue.forbidden,
        'JT001' => RepositoryIssue.unavailable,
        'JT002' => RepositoryIssue.revisionConflict,
        'JT003' => RepositoryIssue.documentUnavailable,
        'JT004' => RepositoryIssue.createConflict,
        'JT005' => RepositoryIssue.documentInUse,
        '22023' ||
        '22003' ||
        '22007' ||
        '22P02' ||
        '23502' ||
        '23514' => RepositoryIssue.validation,
        '40001' ||
        'PGRST000' ||
        'PGRST001' ||
        'PGRST002' ||
        'PGRST003' ||
        '429' ||
        '502' ||
        '503' ||
        '504' => RepositoryIssue.network,
        _ => RepositoryIssue.unexpected,
      };
      throw RepositoryFailure(
        issue,
        writeOutcomeUnknown:
            write && issue == RepositoryIssue.network && error.code != '40001',
      );
    } on FormatException {
      throw RepositoryFailure(
        RepositoryIssue.unexpected,
        writeOutcomeUnknown: write,
      );
    } on TimeoutException {
      _checkScope();
      throw RepositoryFailure(
        RepositoryIssue.network,
        writeOutcomeUnknown: write,
      );
    } catch (error) {
      _checkScope();
      final transport =
          error.runtimeType.toString().contains('ClientException') ||
          error.runtimeType.toString().contains('SocketException');
      throw RepositoryFailure(
        transport ? RepositoryIssue.network : RepositoryIssue.unexpected,
        writeOutcomeUnknown: write,
      );
    }
  }

  String _matchingId(Object? raw, String expected) {
    final result = JobTrailWire.uuid(raw);
    if (result != JobTrailWire.uuid(expected)) {
      throw const FormatException('receipt ID');
    }
    return result;
  }

  ApplicationReceipt _applicationReceipt(Object? raw, String expected) {
    final row = JobTrailWire.object(raw);
    return (
      id: _matchingId(row['id'], expected),
      revision: JobTrailWire.positiveInt(row['revision']),
    );
  }

  @override
  Future<JobTrailSnapshot> loadSnapshot() => _call(
    'load_snapshot',
    () => const {},
    JobTrailWire.snapshot,
    write: false,
  );

  @override
  Future<ApplicationCreateReceipt> createApplication(
    String id,
    ApplicationDraft draft,
  ) => _call('create_application', () => JobTrailWire.application(id, draft), (
    raw,
  ) {
    final row = JobTrailWire.object(raw);
    final receipt = _applicationReceipt(raw, id);
    return (
      id: receipt.id,
      revision: receipt.revision,
      replayed: JobTrailWire.flag(row['replayed']),
    );
  });

  @override
  Future<ApplicationReceipt> updateApplication(
    String id,
    int revision,
    ApplicationDraft draft,
  ) => _call(
    'update_application',
    () => {
      ...JobTrailWire.application(id, draft),
      'p_expected_revision': JobTrailWire.positiveInt(revision),
    },
    (raw) => _applicationReceipt(raw, id),
  );

  @override
  Future<ApplicationReceipt> changeStatus(
    String id,
    int revision,
    RecruitmentStatus status,
  ) => _call(
    'change_status',
    () => {
      'p_id': JobTrailWire.uuid(id),
      'p_expected_revision': JobTrailWire.positiveInt(revision),
      'p_status': status.name,
    },
    (raw) => _applicationReceipt(raw, id),
  );

  @override
  Future<AgendaReceipt> saveAgenda(
    Agenda agenda,
    SaveMode mode, {
    int? expectedRevision,
  }) => _call(
    'save_agenda',
    () => _entitySaveArgs(
      JobTrailWire.agenda(agenda, mode),
      mode,
      expectedRevision,
    ),
    (raw) {
      final row = JobTrailWire.object(raw);
      return (
        id: _matchingId(row['id'], agenda.id),
        revision: JobTrailWire.entityRevision(
          row,
          required: mode == SaveMode.update,
        ),
        replayed: JobTrailWire.flag(row['replayed']),
      );
    },
  );

  @override
  Future<DocumentReceipt> saveDocument(
    AppDocument document,
    SaveMode mode, {
    int? expectedRevision,
  }) => _call(
    'save_document',
    () => _entitySaveArgs(
      JobTrailWire.document(document, mode),
      mode,
      expectedRevision,
    ),
    (raw) {
      final row = JobTrailWire.object(raw);
      return (
        id: _matchingId(row['id'], document.id),
        revision: JobTrailWire.entityRevision(
          row,
          required: mode == SaveMode.update,
        ),
        updatedAt: JobTrailWire.instant(row['updated_at']),
        replayed: JobTrailWire.flag(row['replayed']),
      );
    },
  );

  WireObject _entitySaveArgs(WireObject args, SaveMode mode, int? revision) {
    if (mode == SaveMode.update) {
      args['p_expected_revision'] = JobTrailWire.positiveInt(revision);
    } else if (revision != null) {
      throw const FormatException('create cannot specify a revision');
    }
    return args;
  }

  Future<String> _delete(String resource, String id, int revision) => _call(
    'delete_$resource',
    () => {
      'p_id': JobTrailWire.uuid(id),
      'p_expected_revision': JobTrailWire.positiveInt(revision),
    },
    (raw) => _matchingId(raw, id),
  );

  @override
  Future<String> deleteApplication(String id, int revision) =>
      _delete('application', id, revision);
  @override
  Future<String> deleteAgenda(String id, int expectedRevision) =>
      _delete('agenda', id, expectedRevision);
  @override
  Future<String> deleteDocument(String id, int expectedRevision) =>
      _delete('document', id, expectedRevision);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose?.call();
  }
}
