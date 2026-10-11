import 'dart:convert';

import 'good_day_task.dart';
import 'repeat_schedule.dart';

class TaskSeries {
  const TaskSeries({
    required this.id,
    required this.template,
    required this.enabled,
    this.generatedThrough,
  });
  final String id;
  final GoodDayTask template;
  final bool enabled;
  final DateTime? generatedThrough;
  RepeatSchedule get schedule =>
      RepeatSchedule(template.repeatAnchor!, template.repeat);
  TaskSeries advance(DateTime date) => TaskSeries(
    id: id,
    template: template,
    enabled: enabled,
    generatedThrough: date,
  );
  TaskSeries stop() => TaskSeries(
    id: id,
    template: template,
    enabled: false,
    generatedThrough: generatedThrough,
  );
  String toMarkdown() =>
      '---\ngoodday-series: ${jsonEncode({'id': id, 'enabled': enabled, 'generatedThrough': generatedThrough?.toIso8601String(), 'template': template.toMarkdown()})}\n---\n\n# 重复任务：${template.title}\n';
  factory TaskSeries.fromMarkdown(String source) {
    try {
      final lines = source.split(RegExp(r'\r?\n'));
      if (lines.length < 3 ||
          lines[0] != '---' ||
          lines[2] != '---' ||
          !lines[1].startsWith('goodday-series: ')) {
        throw const FormatException('重复任务格式无效');
      }
      final data = jsonDecode(
        lines[1].substring('goodday-series: '.length),
      ) as Map<String, dynamic>;
      final id = data['id'] as String;
      final template = GoodDayTask.fromMarkdown(data['template'] as String);
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
          template.repeatAnchor == null ||
          template.repeat == EventRepeat.once ||
          template.seriesId != id) {
        throw const FormatException('重复任务规则无效');
      }
      return TaskSeries(
        id: id,
        template: template,
        enabled: data['enabled'] as bool,
        generatedThrough: data['generatedThrough'] == null
            ? null
            : DateTime.parse(data['generatedThrough'] as String),
      );
    } on Object catch (error) {
      throw FormatException('无法读取重复任务：$error');
    }
  }
}
