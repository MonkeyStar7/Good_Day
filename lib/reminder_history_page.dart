import 'dart:async';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'data/vault_repository.dart';
import 'models/good_day_goal.dart';
import 'models/good_day_task.dart';
import 'reminder_pages.dart';

class ReminderHistoryPage extends StatefulWidget {
  const ReminderHistoryPage({
    super.key,
    required this.repository,
    required this.goals,
    required this.clock,
  });
  final VaultRepository repository;
  final List<GoodDayGoal> goals;
  final DateTime Function() clock;
  @override
  State<ReminderHistoryPage> createState() => _ReminderHistoryPageState();
}

class _HistoryRecord {
  const _HistoryRecord({
    required this.title,
    required this.notes,
    required this.kind,
    required this.date,
    required this.completed,
    required this.toggle,
    required this.remove,
    this.stopRepeat,
    this.goalId,
  });
  final String title, notes, kind;
  final String? goalId;
  final DateTime date;
  final bool completed;
  final Future<void> Function(bool) toggle;
  final Future<void> Function() remove;
  final Future<void> Function()? stopRepeat;
}

class _ReminderHistoryPageState extends State<ReminderHistoryPage> {
  List<_HistoryRecord> _records = [];
  bool _completed = true, _busy = true;
  String _query = '';
  String? _error;
  StreamSubscription<void>? _subscription;
  @override
  void initState() {
    super.initState();
    _subscription = widget.repository.reminderChanges.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tasks = await widget.repository.loadTasks();
      final plans = await widget.repository.loadPlans();
      final reminders = await widget.repository.loadReminders();
      final records = <_HistoryRecord>[
        for (final task in tasks)
          _HistoryRecord(
            title: task.title,
            notes: [
              task.notes,
              for (final step in task.subtasks)
                '${step.isCompleted ? '✓' : '○'} ${step.title}',
            ].where((line) => line.isNotEmpty).join('\n'),
            kind: '旧${task.period.taskLabel}',
            date: task.completedAt ?? task.scheduledDate,
            goalId: task.goalId,
            completed: task.isCompleted,
            toggle: (value) async {
              await widget.repository.setCompleted(task, value);
            },
            remove: () => widget.repository.deleteTask(task),
            stopRepeat: task.seriesId == null
                ? null
                : () => widget.repository.stopTaskSeries(task.seriesId!),
          ),
        for (final plan in plans)
          _HistoryRecord(
            title: plan.title,
            notes:
                '${plan.notes.isEmpty ? '' : '${plan.notes}\n'}原截止日期：${reminderDate(plan.deadline)}',
            kind: '旧计划',
            date: plan.completedAt ?? plan.createdAt,
            goalId: plan.goalId,
            completed: plan.isCompleted,
            toggle: (value) async {
              await widget.repository.setPlanCompleted(plan, value);
            },
            remove: () => widget.repository.deletePlan(plan),
          ),
        for (final item in reminders)
          _HistoryRecord(
            title: item.title,
            notes: [
              if (item.notes.isNotEmpty) item.notes,
              for (final task in item.subtasks)
                '${task.isCompleted ? '✓' : '○'} ${task.title}',
            ].join('\n'),
            kind:
                '提醒事项 · ${reminderDate(item.dueAt)} ${reminderTime(item.dueAt)}',
            date: item.completedAt ?? item.createdAt,
            goalId: item.goalId,
            completed: item.isCompleted,
            toggle: (value) => widget.repository.completeReminder(item, value),
            remove: () => widget.repository.deleteReminder(item),
          ),
      ]..sort((a, b) => b.date.compareTo(a.date));
      if (mounted) {
        setState(() {
          _records = records;
          _busy = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '读取失败：$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _records.where(
      (item) =>
          item.completed == _completed &&
          '${item.title} ${item.notes} ${item.kind}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final completed in [true, false])
              ChoiceChip(
                label: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: Text(
                    completed ? '已完成' : '未完成',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                showCheckmark: false,
                selected: _completed == completed,
                onSelected: (_) => setState(() => _completed = completed),
              ),
          ],
        ),
        TextField(
          key: const Key('history-search'),
          decoration: const InputDecoration(
            hintText: '搜索记录',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        if (_error != null) TextButton(onPressed: _load, child: Text(_error!)),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (records.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '没有${_completed ? '已完成' : '未完成'}记录',
                          style: TextStyle(color: context.appColors.muted),
                        ),
                      ),
                    for (final record in records) _record(record),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _record(_HistoryRecord record) {
    final goal = widget.goals
        .where((goal) => goal.id == record.goalId)
        .firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                height: 26,
                child: Checkbox(
                  value: record.completed,
                  shape: const CircleBorder(),
                  onChanged: (value) async {
                    try {
                      await record.toggle(value ?? false);
                      await _load();
                    } catch (error) {
                      if (mounted) setState(() => _error = '未保存，请重试：$error');
                    }
                  },
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.title,
                      style: TextStyle(
                        fontSize: 16,
                        color: goal == null
                            ? context.appColors.ink
                            : Color(goal.colorValue),
                        decoration: record.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${record.kind} · ${record.completed ? '完成于' : '记录于'} ${dateKey(record.date)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.muted,
                      ),
                    ),
                    if (record.notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          record.notes,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appColors.muted,
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 6,
                      children: [
                        TextButton(
                          onPressed: () =>
                              _confirmAction(record, '删除这条记录', record.remove),
                          child: const Text(
                            '删除',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        if (record.stopRepeat != null)
                          TextButton(
                            onPressed: () => _confirmAction(
                              record,
                              '结束重复',
                              record.stopRepeat!,
                            ),
                            child: const Text(
                              '结束重复',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: context.appColors.line),
      ],
    );
  }

  Future<void> _confirmAction(
    _HistoryRecord record,
    String label,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label？'),
        content: Text(record.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '未保存，请重试：$error');
    }
  }
}
