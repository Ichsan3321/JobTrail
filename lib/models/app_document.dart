enum DocumentCategory {
  cvResume('CV/Resume'),
  portfolio('Portofolio');

  const DocumentCategory(this.label);
  final String label;
}

/// Metadata only. [fileName] does not imply an uploaded or accessible file.
class AppDocument {
  const AppDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.fileName,
    required this.version,
    required this.updatedAt,
    this.notes = '',
    this.revision,
  });
  final String id;
  final String title;
  final DocumentCategory category;
  final String fileName;
  final String version;
  final DateTime updatedAt;
  final String notes;

  /// Server revision, separate from the file's user-supplied version label.
  final int? revision;
}
