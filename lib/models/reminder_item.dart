import 'dart:convert';

enum RepeatUnit { none, hour, day, week, month, year }

enum LeadUnit { minute, hour, day, week, month }

class ReminderRule {
  const ReminderRule(this.unit, {this.interval = 1, this.weekdays = const []});
  final RepeatUnit unit;
  final int interval;
  final List<int> weekdays;
  static const presets = <String, ReminderRule>{
    '不重复': ReminderRule(RepeatUnit.none),
    '每小时': ReminderRule(RepeatUnit.hour),
    '每天': ReminderRule(RepeatUnit.day),
    '工作日': ReminderRule(RepeatUnit.week, weekdays: [1, 2, 3, 4, 5]),
    '周末': ReminderRule(RepeatUnit.week, weekdays: [6, 7]),
    '每周': ReminderRule(RepeatUnit.week),
    '每两周': ReminderRule(RepeatUnit.week, interval: 2),
    '每个月': ReminderRule(RepeatUnit.month),
    '每三个月': ReminderRule(RepeatUnit.month, interval: 3),
    '每六个月': ReminderRule(RepeatUnit.month, interval: 6),
    '每年': ReminderRule(RepeatUnit.year),
  };
  Map<String, Object> toJson() => {
    'unit': unit.name,
    'interval': interval,
    'weekdays': weekdays,
  };
  factory ReminderRule.fromJson(Map<String, dynamic> json) {
    final result = ReminderRule(
      RepeatUnit.values.byName(json['unit'] as String),
      interval: json['interval'] as int,
      weekdays: (json['weekdays'] as List).cast<int>(),
    );
    if (result.interval < 1 ||
        result.interval > 999 ||
        result.weekdays.any((day) => day < 1 || day > 7) ||
        result.weekdays.toSet().length != result.weekdays.length) {
      throw const FormatException('重复设置无效');
    }
    return result;
  }
  String get label {
    for (final entry in presets.entries) {
      if (jsonEncode(entry.value.toJson()) == jsonEncode(toJson())) {
        return entry.key;
      }
    }
    final unitLabel = switch (unit) {
      RepeatUnit.none => '',
      RepeatUnit.hour => '小时',
      RepeatUnit.day => '天',
      RepeatUnit.week => '周',
      RepeatUnit.month => '个月',
      RepeatUnit.year => '年',
    };
    final days = weekdays.isEmpty
        ? ''
        : ' · ${weekdays.map((d) => '周${'一二三四五六日'[d - 1]}').join('、')}';
    return '每 $interval $unitLabel$days';
  }

  DateTime? nextAfter(DateTime anchor, DateTime boundary) {
    if (unit == RepeatUnit.none) return null;
    if (boundary.isBefore(anchor)) return anchor;
    DateTime at(int year, int month, int day) =>
        DateTime(year, month, day, anchor.hour, anchor.minute);
    if (unit == RepeatUnit.hour) {
      final step = interval * 60;
      return anchor.add(
        Duration(
          minutes: (boundary.difference(anchor).inMinutes ~/ step + 1) * step,
        ),
      );
    }
    if (unit == RepeatUnit.week) {
      final monday = DateTime.utc(
        anchor.year,
        anchor.month,
        anchor.day - anchor.weekday + 1,
      );
      final days = weekdays.isEmpty ? [anchor.weekday] : weekdays;
      for (var offset = 0; offset <= interval * 7 + 7; offset++) {
        final date = at(boundary.year, boundary.month, boundary.day + offset);
        final week =
            DateTime.utc(
              date.year,
              date.month,
              date.day,
            ).difference(monday).inDays ~/
            7;
        if (week % interval == 0 &&
            days.contains(date.weekday) &&
            date.isAfter(boundary) &&
            !date.isBefore(anchor)) {
          return date;
        }
      }
      throw StateError('无法计算下次重复时间');
    }
    if (unit == RepeatUnit.day) {
      final days = DateTime.utc(
        boundary.year,
        boundary.month,
        boundary.day,
      ).difference(DateTime.utc(anchor.year, anchor.month, anchor.day)).inDays;
      var step = days ~/ interval;
      var candidate = at(
        anchor.year,
        anchor.month,
        anchor.day + step * interval,
      );
      if (!candidate.isAfter(boundary)) {
        candidate = at(
          anchor.year,
          anchor.month,
          anchor.day + (++step) * interval,
        );
      }
      return candidate;
    }
    final months = unit == RepeatUnit.year ? interval * 12 : interval;
    final delta =
        (boundary.year - anchor.year) * 12 + boundary.month - anchor.month;
    var step = delta ~/ months;
    DateTime calendar(int n) {
      final first = DateTime(anchor.year, anchor.month + n * months);
      final last = DateTime(first.year, first.month + 1, 0).day;
      return at(first.year, first.month, anchor.day > last ? last : anchor.day);
    }

    var candidate = calendar(step);
    if (!candidate.isAfter(boundary)) candidate = calendar(++step);
    return candidate;
  }
}

class EarlyReminder {
  const EarlyReminder(this.amount, this.unit);
  final int amount;
  final LeadUnit unit;
  static const presets = <String, EarlyReminder?>{
    '无': null,
    '5 分钟前': EarlyReminder(5, LeadUnit.minute),
    '15 分钟前': EarlyReminder(15, LeadUnit.minute),
    '30 分钟前': EarlyReminder(30, LeadUnit.minute),
    '1 小时前': EarlyReminder(1, LeadUnit.hour),
    '2 小时前': EarlyReminder(2, LeadUnit.hour),
    '1 天前': EarlyReminder(1, LeadUnit.day),
    '2 天前': EarlyReminder(2, LeadUnit.day),
    '1 周前': EarlyReminder(1, LeadUnit.week),
    '1 个月前': EarlyReminder(1, LeadUnit.month),
  };
  String get label =>
      '$amount ${switch (unit) {
        LeadUnit.minute => '分钟',
        LeadUnit.hour => '小时',
        LeadUnit.day => '天',
        LeadUnit.week => '周',
        LeadUnit.month => '个月',
      }}前';
  Map<String, Object> toJson() => {'amount': amount, 'unit': unit.name};
  factory EarlyReminder.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'] as int;
    if (amount < 1 || amount > 200) throw const FormatException('提前提醒数值无效');
    return EarlyReminder(
      amount,
      LeadUnit.values.byName(json['unit'] as String),
    );
  }
  DateTime before(DateTime due) {
    if (unit == LeadUnit.month) {
      final first = DateTime(due.year, due.month - amount);
      final last = DateTime(first.year, first.month + 1, 0).day;
      return DateTime(
        first.year,
        first.month,
        due.day.clamp(1, last),
        due.hour,
        due.minute,
      );
    }
    if (unit == LeadUnit.day || unit == LeadUnit.week) {
      return DateTime(
        due.year,
        due.month,
        due.day - amount * (unit == LeadUnit.week ? 7 : 1),
        due.hour,
        due.minute,
      );
    }
    return due.subtract(
      Duration(minutes: amount * (unit == LeadUnit.hour ? 60 : 1)),
    );
  }
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.createdAt,
    this.notes = '',
    this.goalId,
    this.rule = const ReminderRule(RepeatUnit.none),
    this.early,
    this.enabled = true,
    this.completedAt,
    this.deletedAt,
    this.seriesRoot,
    this.anchor,
    this.earlyHandled = false,
    this.dueHandled = false,
    this.pendingPhase,
    this.snoozedUntil,
  });
  final String id, title, notes;
  final DateTime dueAt, createdAt;
  final String? goalId, seriesRoot, pendingPhase;
  final ReminderRule rule;
  final EarlyReminder? early;
  final bool enabled, earlyHandled, dueHandled;
  final DateTime? completedAt, deletedAt, anchor, snoozedUntil;
  bool get isCompleted => completedAt != null;
  int get daySection => dueAt.hour < 12
      ? 0
      : dueAt.hour < 17
      ? 1
      : 2;
  String? phaseDue(DateTime now) {
    if (!enabled || isCompleted || deletedAt != null) return null;
    if (pendingPhase == 'early' && !dueHandled && !now.isBefore(dueAt)) {
      return 'due';
    }
    if (pendingPhase != null) {
      return snoozedUntil == null || !now.isBefore(snoozedUntil!)
          ? pendingPhase
          : null;
    }
    if (!dueHandled && !now.isBefore(dueAt)) return 'due';
    if (early != null &&
        !earlyHandled &&
        !now.isBefore(early!.before(dueAt)) &&
        now.isBefore(dueAt)) {
      return 'early';
    }
    return null;
  }

  DateTime phaseTime(String phase) =>
      phase == 'early' ? early!.before(dueAt) : dueAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'dueAt': dueAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'goalId': goalId,
    'rule': rule.toJson(),
    'early': early?.toJson(),
    'enabled': enabled,
    'completedAt': completedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'seriesRoot': seriesRoot,
    'anchor': anchor?.toIso8601String(),
    'earlyHandled': earlyHandled,
    'dueHandled': dueHandled,
    'pendingPhase': pendingPhase,
    'snoozedUntil': snoozedUntil?.toIso8601String(),
  };
  ReminderItem patch(Map<String, dynamic> values) =>
      ReminderItem.fromJson({...toJson(), ...values});
  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    DateTime? date(String name) => json[name] == null
        ? null
        : DateTime.parse(json[name] as String).toLocal();
    final id = json['id'] as String;
    final phase = json['pendingPhase'] as String?;
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
        (json['title'] as String).trim().isEmpty ||
        (phase != null && phase != 'early' && phase != 'due') ||
        (phase == 'early' && json['early'] == null) ||
        (json['snoozedUntil'] != null && phase == null)) {
      throw const FormatException('提醒事项内容无效');
    }
    return ReminderItem(
      id: id,
      title: json['title'] as String,
      notes: json['notes'] as String,
      dueAt: date('dueAt')!,
      createdAt: date('createdAt')!,
      goalId: json['goalId'] as String?,
      rule: ReminderRule.fromJson(json['rule'] as Map<String, dynamic>),
      early: json['early'] == null
          ? null
          : EarlyReminder.fromJson(json['early'] as Map<String, dynamic>),
      enabled: json['enabled'] as bool,
      completedAt: date('completedAt'),
      deletedAt: date('deletedAt'),
      seriesRoot: json['seriesRoot'] as String?,
      anchor: date('anchor'),
      earlyHandled: json['earlyHandled'] as bool,
      dueHandled: json['dueHandled'] as bool,
      pendingPhase: phase,
      snoozedUntil: date('snoozedUntil'),
    );
  }
  String toMarkdown() =>
      '---\ngoodday-reminder: ${jsonEncode(toJson())}\n---\n\n# ${title.replaceAll(RegExp(r'[\r\n]+'), ' ')}\n\n$notes\n';
  factory ReminderItem.fromMarkdown(String source) {
    try {
      final lines = source.split(RegExp(r'\r?\n'));
      if (lines.length < 3 ||
          lines.first != '---' ||
          lines[2] != '---' ||
          !lines[1].startsWith('goodday-reminder: ')) {
        throw const FormatException('提醒文件格式无效');
      }
      return ReminderItem.fromJson(
        jsonDecode(lines[1].substring('goodday-reminder: '.length))
            as Map<String, dynamic>,
      );
    } on Object catch (error) {
      throw FormatException('无法读取提醒事项：$error');
    }
  }
}
