import 'constants/app_dates.dart';

enum ActivityWeekStatus { active, inactive, pending }

typedef ActivityWeek = ({DateTime start, ActivityWeekStatus status});
typedef ActivityStreak = ({
  int consecutiveWeeks,
  bool hasActivity,
  List<ActivityWeek> weeks,
});

/// Computes recorded application activity using WIB civil dates, encoded as
/// UTC midnight by AppDates. The four display weeks end with the current week.
ActivityStreak calculateActivityStreak({
  required DateTime referenceDate,
  required Iterable<DateTime> appliedDates,
}) {
  _requireCivilDate(referenceDate, 'referenceDate');
  final currentWeek = _monday(referenceDate);
  final activeWeeks = <DateTime>{};
  for (final date in appliedDates) {
    _requireCivilDate(date, 'appliedDates');
    if (!date.isAfter(referenceDate)) activeWeeks.add(_monday(date));
  }

  const week = Duration(days: 7);
  var cursor = activeWeeks.contains(currentWeek)
      ? currentWeek
      : currentWeek.subtract(week);
  var consecutiveWeeks = 0;
  while (activeWeeks.contains(cursor)) {
    consecutiveWeeks++;
    cursor = cursor.subtract(week);
  }

  return (
    consecutiveWeeks: consecutiveWeeks,
    hasActivity: activeWeeks.isNotEmpty,
    weeks: List.unmodifiable([
      for (var offset = 3; offset >= 0; offset--)
        _activityWeek(
          currentWeek.subtract(week * offset),
          activeWeeks,
          offset == 0,
        ),
    ]),
  );
}

ActivityWeek _activityWeek(
  DateTime start,
  Set<DateTime> activeWeeks,
  bool isCurrent,
) => (
  start: start,
  status: activeWeeks.contains(start)
      ? ActivityWeekStatus.active
      : isCurrent
      ? ActivityWeekStatus.pending
      : ActivityWeekStatus.inactive,
);

DateTime _monday(DateTime date) =>
    date.subtract(Duration(days: date.weekday - DateTime.monday));

void _requireCivilDate(DateTime date, String field) {
  if (!AppDates.isDate(date)) {
    throw ArgumentError.value(
      date,
      field,
      'Expected a WIB civil date encoded as UTC midnight.',
    );
  }
}
