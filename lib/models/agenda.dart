enum AgendaType {
  interview('Interview'),
  test('Test/Psikotes');

  const AgendaType(this.label);
  final String label;
}

class Agenda {
  const Agenda({
    required this.id,
    required this.applicationId,
    required this.type,
    required this.scheduledAt,
    required this.locationOrLink,
    this.notes = '',
    this.revision,
  });
  final String id;
  final String applicationId;
  final AgendaType type;
  final DateTime scheduledAt;
  final String locationOrLink;
  final String notes;

  /// Null for local records and snapshots from before the revision migration.
  final int? revision;
}
