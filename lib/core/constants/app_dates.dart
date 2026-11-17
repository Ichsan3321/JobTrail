/// Date-only values are UTC midnight civil dates, not local instants.
/// Agenda/history/document timestamps are UTC instants; WIB is always UTC+07.
abstract final class AppDates {
  static DateTime date(int year, int month, int day) =>
      DateTime.utc(year, month, day);
  static DateTime wibDate(DateTime instant) {
    final civil = instant.toUtc().add(const Duration(hours: 7));
    return date(civil.year, civil.month, civil.day);
  }

  static String formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  static String formatWib(DateTime instant) {
    final civil = instant.toUtc().add(const Duration(hours: 7));
    return '${formatDate(civil)} ${civil.hour.toString().padLeft(2, '0')}:${civil.minute.toString().padLeft(2, '0')} WIB';
  }

  static bool isDate(DateTime value) =>
      value.isUtc && value == date(value.year, value.month, value.day);
}
