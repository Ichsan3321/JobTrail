import 'dart:math';

import '../models/agenda.dart';
import '../models/app_document.dart';
import '../models/application.dart';
import '../models/recruitment_status.dart';
import '../models/status_history.dart';

/// Snapshot decoded in full before any record becomes visible to the store.
class JobTrailSnapshot {
  JobTrailSnapshot({
    required this.referenceDate,
    required this.referenceInstantUtc,
    required Iterable<Application> applications,
    required Iterable<Agenda> agendas,
    required Iterable<AppDocument> documents,
    required Iterable<StatusHistory> history,
    required Map<String, int> applicationRevisions,
  }) : applications = List.unmodifiable(applications),
       agendas = List.unmodifiable(agendas),
       documents = List.unmodifiable(documents),
       history = List.unmodifiable(history),
       applicationRevisions = Map.unmodifiable(applicationRevisions);

  final DateTime referenceDate;
  final DateTime referenceInstantUtc;
  final List<Application> applications;
  final List<Agenda> agendas;
  final List<AppDocument> documents;
  final List<StatusHistory> history;
  final Map<String, int> applicationRevisions;
}

enum RepositoryIssue {
  authentication,
  network,
  validation,
  revisionConflict,
  forbidden,
  unavailable,
  documentUnavailable,
  createConflict,
  documentInUse,
  busy,
  unexpected,
}

extension RepositoryIssueMessage on RepositoryIssue {
  String get message => switch (this) {
    RepositoryIssue.authentication => 'Sesi akun tidak aktif. Masuk kembali.',
    RepositoryIssue.network => 'Koneksi ke server terganggu. Coba muat ulang.',
    RepositoryIssue.validation => 'Periksa isian dan format data.',
    RepositoryIssue.revisionConflict =>
      'Data telah berubah. Bandingkan data terbaru dengan draft Anda.',
    RepositoryIssue.forbidden =>
      'Akun ini tidak diizinkan melakukan tindakan tersebut.',
    RepositoryIssue.unavailable => 'Data tidak tersedia.',
    RepositoryIssue.documentUnavailable =>
      'Dokumen terkait tidak tersedia. Pilih ulang dari daftar terbaru.',
    RepositoryIssue.createConflict =>
      'ID pembuatan sudah dipakai oleh permintaan berbeda.',
    RepositoryIssue.documentInUse => 'Dokumen masih tertaut ke lamaran.',
    RepositoryIssue.busy =>
      'Tunggu operasi yang sedang berlangsung atau muat ulang data.',
    RepositoryIssue.unexpected => 'Terjadi kesalahan saat memproses data.',
  };
}

class RepositoryFailure implements Exception {
  const RepositoryFailure(this.issue, {this.writeOutcomeUnknown = false});
  final RepositoryIssue issue;
  final bool writeOutcomeUnknown;
}

enum SaveMode { create, update }

/// Keep this exact intent across an ambiguous create retry.
class ApplicationCreation {
  ApplicationCreation(this.draft) : id = newRecordId();
  final String id;
  final ApplicationDraft draft;
}

typedef ApplicationReceipt = ({String id, int revision});
typedef ApplicationCreateReceipt = ({String id, int revision, bool replayed});
// Only pre-migration create receipts may omit the revision.
typedef AgendaReceipt = ({String id, int? revision, bool replayed});
typedef DocumentReceipt = ({
  String id,
  int? revision,
  DateTime updatedAt,
  bool replayed,
});

abstract interface class JobTrailRepository {
  Future<JobTrailSnapshot> loadSnapshot();
  Future<ApplicationCreateReceipt> createApplication(
    String id,
    ApplicationDraft draft,
  );
  Future<ApplicationReceipt> updateApplication(
    String id,
    int revision,
    ApplicationDraft draft,
  );
  Future<ApplicationReceipt> changeStatus(
    String id,
    int revision,
    RecruitmentStatus status,
  );
  Future<String> deleteApplication(String id, int revision);
  // Pass the captured revision for update. Omit it for create.
  Future<AgendaReceipt> saveAgenda(
    Agenda agenda,
    SaveMode mode, {
    int? expectedRevision,
  });
  Future<String> deleteAgenda(String id, int expectedRevision);
  Future<DocumentReceipt> saveDocument(
    AppDocument document,
    SaveMode mode, {
    int? expectedRevision,
  });
  Future<String> deleteDocument(String id, int expectedRevision);
  void dispose();
}

/// Allocate once per create intent and retain it with the immutable draft.
String newRecordId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
