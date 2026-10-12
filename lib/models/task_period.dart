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

  String dateLabel(DateTime date) {
    final d = date.toLocal();
    switch (this) {
      case TaskPeriod.day:
        const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        return '${d.year}年${d.month}月${d.day}日 · ${weekdays[d.weekday - 1]}';
      case TaskPeriod.week:
        final first = start(d);
        final last = DateTime(first.year, first.month, first.day + 6);
        // ISO weeks begin on Monday; the Thursday determines the week-year.
        final thursday = DateTime.utc(first.year, first.month, first.day + 3);
        final january4 = DateTime.utc(thursday.year, 1, 4);
        final week1 = january4.subtract(Duration(days: january4.weekday - 1));
        final monday = DateTime.utc(first.year, first.month, first.day);
        final week = monday.difference(week1).inDays ~/ 7 + 1;
        String rangeDate(DateTime value) =>
            '${first.year != last.year ? '${value.year}年' : ''}${value.month}月${value.day}日';
        return '${thursday.year}年第$week周 · ${rangeDate(first)}—${rangeDate(last)}';
      case TaskPeriod.month:
        return '${d.year}年${d.month}月';
      case TaskPeriod.year:
        return '${d.year}年';
      case TaskPeriod.backlog:
        return '过期未完成 · 等待重新安排';
    }
  }

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
