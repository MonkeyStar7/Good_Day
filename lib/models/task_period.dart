enum TaskPeriod { day, week, month, year, backlog }

extension TaskPeriodRange on TaskPeriod {
  String get shortLabel => switch (this) {
    TaskPeriod.day => '日',
    TaskPeriod.week => '周',
    TaskPeriod.month => '月',
    TaskPeriod.year => '年',
    TaskPeriod.backlog => '待安排',
  };
  String get taskLabel => '$shortLabel待办';
  String get label => switch (this) {
    TaskPeriod.day => '今日',
    TaskPeriod.week => '本周',
    TaskPeriod.month => '本月',
    TaskPeriod.year => '本年',
    TaskPeriod.backlog => '待安排',
  };

  DateTime start(DateTime date) {
    final d = date.toLocal();
    return switch (this) {
      TaskPeriod.day => DateTime(d.year, d.month, d.day),
      TaskPeriod.week => DateTime(d.year, d.month, d.day - d.weekday + 1),
      TaskPeriod.month => DateTime(d.year, d.month),
      TaskPeriod.year => DateTime(d.year),
      TaskPeriod.backlog => throw StateError('待安排不对应一个日期范围'),
    };
  }

  DateTime end(DateTime date) {
    final first = start(date);
    return switch (this) {
      TaskPeriod.day => DateTime(first.year, first.month, first.day + 1),
      TaskPeriod.week => DateTime(first.year, first.month, first.day + 7),
      TaskPeriod.month => DateTime(first.year, first.month + 1),
      TaskPeriod.year => DateTime(first.year + 1),
      TaskPeriod.backlog => throw StateError('待安排不对应一个日期范围'),
    };
  }

  bool contains(DateTime date, DateTime anchor) =>
      !date.isBefore(start(anchor)) && date.isBefore(end(anchor));
}
