import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/activity_streak.dart';
import 'package:jobtrail/core/constants/app_dates.dart';

DateTime day(int day) => DateTime.utc(2026, 11, day);

ActivityStreak streak(DateTime reference, List<DateTime> applications) =>
    calculateActivityStreak(
      referenceDate: reference,
      appliedDates: applications,
    );

void main() {
  test('empty snapshot has zero and three inactive weeks before pending', () {
    final result = streak(day(26), []);
    expect(result.consecutiveWeeks, 0);
    expect(result.hasActivity, isFalse);
    expect(result.weeks.map((week) => week.start), [
      day(2),
      day(9),
      day(16),
      day(23),
    ]);
    expect(result.weeks.map((week) => week.status), [
      ActivityWeekStatus.inactive,
      ActivityWeekStatus.inactive,
      ActivityWeekStatus.inactive,
      ActivityWeekStatus.pending,
    ]);
    expect(() => result.weeks.clear(), throwsUnsupportedError);
  });

  test('one active week and repeated applications in it count once', () {
    final result = streak(day(26), [day(23), day(24), day(26), day(26)]);
    expect(result.consecutiveWeeks, 1);
    expect(result.hasActivity, isTrue);
    expect(result.weeks.last.status, ActivityWeekStatus.active);
  });

  test('activity can form a streak longer than the four displayed weeks', () {
    final result = streak(day(26), [
      day(26),
      day(17),
      day(9),
      day(2),
      DateTime.utc(2026, 10, 27),
    ]);
    expect(result.consecutiveWeeks, 5);
    expect(result.weeks, hasLength(4));
    expect(
      result.weeks.every((week) => week.status == ActivityWeekStatus.active),
      isTrue,
    );
  });

  test('pending current week keeps the previous streak until WIB rollover', () {
    final before = DateTime.utc(2026, 11, 29, 16, 59, 59, 999);
    final after = DateTime.utc(2026, 11, 29, 17);
    final applications = [day(11), day(17)];
    final sunday = streak(AppDates.wibDate(before), applications);
    expect(sunday.consecutiveWeeks, 2);
    expect(sunday.weeks.last, (
      start: day(23),
      status: ActivityWeekStatus.pending,
    ));
    final monday = streak(AppDates.wibDate(after), applications);
    expect(monday.consecutiveWeeks, 0);
    expect(monday.weeks.map((week) => week.status), [
      ActivityWeekStatus.active,
      ActivityWeekStatus.active,
      ActivityWeekStatus.inactive,
      ActivityWeekStatus.pending,
    ]);
  });

  test('a completed gap breaks a streak even when current week is active', () {
    final result = streak(day(26), [day(3), day(10), day(26)]);
    expect(result.consecutiveWeeks, 1);
    expect(result.weeks.map((week) => week.status), [
      ActivityWeekStatus.active,
      ActivityWeekStatus.active,
      ActivityWeekStatus.inactive,
      ActivityWeekStatus.active,
    ]);
  });

  test('month and year changes use continuous Monday buckets', () {
    final result = streak(DateTime.utc(2027, 1, 5), [
      DateTime.utc(2026, 12, 27),
      DateTime.utc(2026, 12, 31),
      DateTime.utc(2027, 1, 4),
    ]);
    expect(result.consecutiveWeeks, 3);
    expect(result.weeks.map((week) => week.start), [
      DateTime.utc(2026, 12, 14),
      DateTime.utc(2026, 12, 21),
      DateTime.utc(2026, 12, 28),
      DateTime.utc(2027, 1, 4),
    ]);
  });

  test(
    'future dates in current week and future weeks do not activate them',
    () {
      final result = streak(day(26), [day(27), day(30)]);
      expect(result.hasActivity, isFalse);
      expect(result.consecutiveWeeks, 0);
      expect(result.weeks.last.status, ActivityWeekStatus.pending);
    },
  );

  test('deleting the only application in a completed week recomputes from snapshot', () {
    final applications = [day(10), day(17), day(26)];
    expect(streak(day(26), applications).consecutiveWeeks, 3);
    applications.remove(day(17));
    expect(streak(day(26), applications).consecutiveWeeks, 1);
  });

  test('non-civil dates fail instead of silently using device timezone', () {
    expect(() => streak(DateTime(2026, 11, 26), []), throwsArgumentError);
    expect(
      () => streak(day(26), [DateTime.utc(2026, 11, 26, 1)]),
      throwsArgumentError,
    );
  });
}
