import 'dart:async';

import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';

/// A deterministic scripted repository for offline integration and widget tests.
/// The same port can be injected into a debug preview without an SDK client.
class FakeJobTrailRepository implements JobTrailRepository {
  FakeJobTrailRepository(this.read);

  FutureOr<JobTrailSnapshot> Function() read;
  FutureOr<ApplicationCreateReceipt> Function(String, ApplicationDraft)? create;
  FutureOr<ApplicationReceipt> Function(String, int, RecruitmentStatus)? status;
  int reads = 0;
  bool disposed = false;

  @override
  Future<JobTrailSnapshot> loadSnapshot() async {
    reads++;
    return read();
  }

  @override
  Future<ApplicationCreateReceipt> createApplication(
    String id,
    ApplicationDraft draft,
  ) async => (create ?? _unsupported)(id, draft);

  @override
  Future<ApplicationReceipt> changeStatus(
    String id,
    int revision,
    RecruitmentStatus value,
  ) async => (status ?? _unsupported)(id, revision, value);

  Never _unsupported([Object? a, Object? b, Object? c]) =>
      throw const RepositoryFailure(RepositoryIssue.forbidden);

  @override
  Future<ApplicationReceipt> updateApplication(
    String id,
    int revision,
    ApplicationDraft draft,
  ) async => _unsupported();
  @override
  Future<String> deleteApplication(String id, int revision) async =>
      _unsupported();
  @override
  Future<AgendaReceipt> saveAgenda(Agenda agenda, SaveMode mode) async =>
      _unsupported();
  @override
  Future<String> deleteAgenda(String id) async => _unsupported();
  @override
  Future<DocumentReceipt> saveDocument(
    AppDocument document,
    SaveMode mode,
  ) async => _unsupported();
  @override
  Future<String> deleteDocument(String id) async => _unsupported();
  @override
  void dispose() => disposed = true;
}
