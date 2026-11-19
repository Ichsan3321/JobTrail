import '../../core/constants/app_dates.dart';

/// S05-private Indonesian date/time labels. Propose moving to AppDates
/// (shared, Ichsan) if other screens need the same copy.
abstract final class ScheduleFormat {
  static const _dayShort = ['SEN', 'SEL', 'RAB', 'KAM', 'JUM', 'SAB', 'MIN'];
  static const _dayLong = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  static const _monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  static const _monthLong = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// Single source for the S05 supported date range (JT-BUG-012): week
  /// navigation, the week strip, the date picker and the date validator all
  /// use these bounds. UTC civil dates, inclusive.
  static final DateTime firstDate = AppDates.date(2020, 1, 1);
  static final DateTime lastDate = AppDates.date(2035, 12, 31);

  /// Whether the civil [date] lies within [firstDate]..[lastDate].
  static bool isInRange(DateTime date) {
    final civil = AppDates.date(date.year, date.month, date.day);
    return !civil.isBefore(firstDate) && !civil.isAfter(lastDate);
  }

  /// [date] clamped to [firstDate]..[lastDate] (UTC civil date).
  static DateTime clampToRange(DateTime date) {
    final civil = AppDates.date(date.year, date.month, date.day);
    if (civil.isBefore(firstDate)) return firstDate;
    if (civil.isAfter(lastDate)) return lastDate;
    return civil;
  }

  /// Sunday that starts the MIN–SAB week containing [date] (UTC civil date).
  static DateTime weekStartSunday(DateTime date) =>
      date.subtract(Duration(days: date.weekday % 7));

  static DateTime addDays(DateTime date, int days) =>
      AppDates.date(date.year, date.month, date.day + days);

  /// "MIN"
  static String dayShort(DateTime date) => _dayShort[date.weekday - 1];

  /// "Minggu"
  static String dayLong(DateTime date) => _dayLong[date.weekday - 1];

  /// "November 2026"
  static String monthYear(DateTime date) =>
      '${_monthLong[date.month - 1]} ${date.year}';

  /// "Minggu, 15 Nov 2026"
  static String longDate(DateTime date) =>
      '${dayLong(date)}, ${date.day} ${_monthShort[date.month - 1]} ${date.year}';

  /// "Sabtu, 21 Nov"
  static String longDayMonth(DateTime date) =>
      '${dayLong(date)}, ${date.day} ${_monthShort[date.month - 1]}';

  /// "Selasa 17 November" (screen-reader labels).
  static String dayMonthLong(DateTime date) =>
      '${dayLong(date)} ${date.day} ${_monthLong[date.month - 1]}';

  /// "Sen, 16 Nov 2026"
  static String shortDate(DateTime date) =>
      '${shortDayMonth(date)} ${date.year}';

  /// Compact picker value: "Sel, 17 Nov" when [date] is in the same year as
  /// [reference], otherwise "1 Jan 2027" so the year is never hidden.
  static String fieldDate(DateTime date, DateTime reference) =>
      date.year == reference.year ? shortDayMonth(date) : dayMonthYear(date);

  /// "5 Nov 2026"
  static String dayMonthYear(DateTime date) =>
      '${date.day} ${_monthShort[date.month - 1]} ${date.year}';

  /// WIB civil [date] + [hour]:[minute] parsed with an explicit +07:00
  /// offset, returned as a UTC instant (store contract).
  static DateTime parseWib(DateTime date, int hour, int minute) {
    String two(int v) => v.toString().padLeft(2, '0');
    return DateTime.parse(
      '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-'
      '${two(date.day)}T${two(hour)}:${two(minute)}:00+07:00',
    ).toUtc();
  }

  /// "SEN, 16 NOV"
  static String groupHeader(DateTime date) =>
      '${dayShort(date)}, ${date.day} ${_monthShort[date.month - 1].toUpperCase()}';

  /// "Sen, 16 Nov"
  static String shortDayMonth(DateTime date) {
    final day = dayShort(date);
    return '${day[0]}${day.substring(1).toLowerCase()}, ${date.day} ${_monthShort[date.month - 1]}';
  }

  /// "10.00" in WIB (UTC+07), Figma time notation.
  static String timeWib(DateTime instant) {
    final civil = instant.toUtc().add(const Duration(hours: 7));
    return '${civil.hour.toString().padLeft(2, '0')}.${civil.minute.toString().padLeft(2, '0')}';
  }

  /// "hari ini" / "besok" / "Rab, 18 Nov" relative to [reference].
  static String relativeDay(DateTime date, DateTime reference) {
    final diff = date.difference(reference).inDays;
    if (diff == 0) return 'hari ini';
    if (diff == 1) return 'besok';
    return shortDayMonth(date);
  }
}
