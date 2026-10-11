import 'dart:async';

import 'package:flutter/material.dart';

import 'data/vault_repository.dart';
import 'models/good_day_task.dart';
import 'models/repeat_schedule.dart';
import 'models/task_series.dart';

enum TaskView { today, tomorrow, upcoming, history, all }

extension TaskViewLabel on TaskView {
  String get label => switch (this) {
    TaskView.today => '今天',
    TaskView.tomorrow => '明天',
    TaskView.upcoming => '未来',
    TaskView.history => '历史',
    TaskView.all => '全部',
  };
}

class TaskBrowserPage extends StatefulWidget {
  const TaskBrowserPage({
    super.key,
    required this.repository,
    required this.clock,
    required this.onEditingChanged,
    this.initialView = TaskView.tomorrow,
  });
  final VaultRepository repository;
  final DateTime Function() clock;
  final void Function(bool editing) onEditingChanged;
  final TaskView initialView;
  @override
  State<TaskBrowserPage> createState() => _TaskBrowserPageState();
}

class _TaskBrowserPageState extends State<TaskBrowserPage>
    with WidgetsBindingObserver {
  List<GoodDayTask> _tasks = [];
  List<TaskSeries> _series = [];
  late TaskView _view;
  String _query = '';
  DateTime? _date;
  bool _busy = true;
  String? _error;
  Timer? _refreshTimer;
  bool _editing = false;
  late DateTime _loadedDate;
  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _loadedDate = widget.clock();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy && !_editing && !isSameDay(_loadedDate, widget.clock())) {
        unawaited(_load());
      }
    });
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.onEditingChanged(false);
    super.dispose();
  }

  Future<void> _load() async {
    widget.onEditingChanged(true);
    try {
      final tasks = await widget.repository.loadTasks();
      final series = await widget.repository.loadTaskSeries();
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _series = series;
          _busy = false;
          _error = null;
          _loadedDate = widget.clock();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '读取失败：$error';
          _busy = false;
        });
      }
    } finally {
      widget.onEditingChanged(_editing);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && !_editing) {
      unawaited(_load());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    widget.onEditingChanged(true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '操作未完成，请重试：$error';
          _busy = false;
        });
      }
    } finally {
      widget.onEditingChanged(false);
    }
  }

  Future<void> _edit(GoodDayTask? task) async {
    if (_busy) return;
    _editing = true;
    widget.onEditingChanged(true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TaskScheduleDialog(
          task: task,
          now: widget.clock(),
          onSave: (title, notes, date, repeat) async {
            await widget.repository.saveScheduledTask(
              task: task,
              title: title,
              notes: notes,
              date: date,
              repeat: repeat,
            );
          },
        ),
      );
      await _load();
    } finally {
      _editing = false;
      widget.onEditingChanged(false);
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date ?? widget.clock(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected != null && mounted) {
      setState(() {
        _date = selected;
        _view = TaskView.all;
      });
    }
  }

  Future<void> _stop(GoodDayTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('结束这组重复任务？'),
        content: const Text('以后不再生成。这组已生成的未来未完成任务会移到垃圾桶，今天和历史记录保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束重复'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => widget.repository.stopTaskSeries(task.seriesId!));
    }
  }

  Future<void> _delete(GoodDayTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这一次任务？'),
        content: const Text('仅删除这条记录，移到垃圾桶。重复规则继续运行；要停止以后的任务，请选择结束重复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(() => widget.repository.deleteTask(task));
  }

  List<GoodDayTask> get _visible {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final tasks = _tasks.where((task) {
      final recordDate =
          task.completedAt ?? task.occurrenceDate ?? task.originalScheduledDate;
      if (_date != null &&
          !isSameDay(recordDate, _date!) &&
          !isSameDay(task.scheduledDate, _date!)) {
        return false;
      }
      final match = switch (_view) {
        TaskView.today =>
          isSameDay(task.scheduledDate, today) ||
              (task.completedAt != null && isSameDay(task.completedAt!, today)),
        TaskView.tomorrow =>
          !task.isCompleted && isSameDay(task.scheduledDate, tomorrow),
        TaskView.upcoming =>
          !task.isCompleted && task.scheduledDate.isAfter(today),
        TaskView.history =>
          task.isCompleted || task.scheduledDate.isBefore(today),
        TaskView.all => true,
      };
      return match &&
          '${task.title} ${task.notes} ${task.subtasks.map((step) => step.title).join(' ')}'
              .toLowerCase()
              .contains(_query.toLowerCase());
    }).toList();
    tasks.sort((a, b) {
      if (_view == TaskView.history) {
        return (b.completedAt ?? b.scheduledDate).compareTo(
          a.completedAt ?? a.scheduledDate,
        );
      }
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return a.scheduledDate.compareTo(b.scheduledDate);
    });
    return tasks;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: const Text('任务日期与历史'),
        backgroundColor: const Color(0xFFF5F5F0),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    for (final view in TaskView.values)
                      ChoiceChip(
                        key: Key('task-filter-${view.name}'),
                        label: Text(view.label),
                        selected: _view == view && _date == null,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                _view = view;
                                _date = null;
                              }),
                      ),
                  ],
                ),
                TextField(
                  key: const Key('task-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索任务、备注或子任务',
                  ),
                  onChanged: (query) => setState(() => _query = query),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      key: const Key('task-browse-date'),
                      onPressed: _busy ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_date == null ? '选择日期' : dateKey(_date!)),
                    ),
                    if (_date != null)
                      IconButton(
                        onPressed: () => setState(() => _date = null),
                        icon: const Icon(Icons.clear, size: 16),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('create-scheduled-task'),
                      onPressed: _busy ? null : () => _edit(null),
                      icon: const Icon(Icons.add),
                      label: const Text('安排任务'),
                    ),
                  ],
                ),
                if (_error != null)
                  TextButton(onPressed: _load, child: Text('$_error · 点击重试')),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _visible.isEmpty
                ? const Center(child: Text('这个范围没有任务'))
                : ListView(
                    children: [
                      for (final task in _visible)
                        ExpansionTile(
                          key: ValueKey('browse-task-${task.id}'),
                          leading: Checkbox(
                            key: Key('browse-complete-${task.id}'),
                            value: task.isCompleted,
                            onChanged: _busy
                                ? null
                                : (value) => _run(() async {
                                    await widget.repository.setCompleted(
                                      task,
                                      value!,
                                    );
                                  }),
                          ),
                          title: Text(
                            task.title,
                            style: TextStyle(
                              fontSize: 15,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            task.isCompleted
                                ? '完成于 ${dateKey(task.completedAt ?? task.scheduledDate)}'
                                : '安排于 ${dateKey(task.scheduledDate)}${task.repeat == EventRepeat.once ? '' : ' · ${task.repeat.label}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: [
                            if (task.originalScheduledDate !=
                                task.scheduledDate)
                              Text(
                                '最初安排：${dateKey(task.originalScheduledDate)}',
                              ),
                            if (task.notes.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(task.notes),
                              ),
                            for (final step in task.subtasks)
                              CheckboxListTile(
                                dense: true,
                                title: Text(step.title),
                                value: step.isCompleted,
                                onChanged: _busy
                                    ? null
                                    : (value) => _run(() async {
                                        await widget.repository.updateSubtask(
                                          task,
                                          step.id,
                                          isCompleted: value,
                                        );
                                      }),
                              ),
                            Wrap(
                              spacing: 6,
                              children: [
                                TextButton(
                                  key: Key('browse-edit-${task.id}'),
                                  onPressed: _busy ? null : () => _edit(task),
                                  child: const Text('编辑 / 日期 / 重复'),
                                ),
                                if (_series.any(
                                  (series) =>
                                      series.id == task.seriesId &&
                                      series.enabled,
                                ))
                                  TextButton(
                                    key: Key('stop-series-${task.id}'),
                                    onPressed: _busy ? null : () => _stop(task),
                                    child: const Text('结束重复'),
                                  ),
                                TextButton(
                                  onPressed: _busy ? null : () => _delete(task),
                                  child: const Text('删除本次'),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

class TaskScheduleDialog extends StatefulWidget {
  const TaskScheduleDialog({
    super.key,
    this.task,
    required this.now,
    required this.onSave,
  });
  final GoodDayTask? task;
  final DateTime now;
  final Future<void> Function(
    String title,
    String notes,
    DateTime date,
    EventRepeat repeat,
  )
  onSave;
  @override
  State<TaskScheduleDialog> createState() => _TaskScheduleDialogState();
}

class _TaskScheduleDialogState extends State<TaskScheduleDialog> {
  late final TextEditingController _title, _notes;
  late DateTime _date;
  late EventRepeat _repeat;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task?.title ?? '');
    _notes = TextEditingController(text: widget.task?.notes ?? '');
    final start = widget.task?.scheduledDate ?? widget.now;
    _date = DateTime(start.year, start.month, start.day);
    _repeat = widget.task?.repeat ?? EventRepeat.once;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _offset(int days) => setState(
    () => _date = DateTime(
      widget.now.year,
      widget.now.month,
      widget.now.day + days,
    ),
  );
  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写任务名称');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_title.text.trim(), _notes.text, _date, _repeat);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，输入保留：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = widget.task?.isCompleted ?? false;
    final first = RepeatSchedule(
      _date,
      _repeat,
    ).nextOccurrenceAfter(_date.subtract(const Duration(microseconds: 1)))!;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(12),
        title: Text(widget.task == null ? '安排任务' : '任务日期与重复'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('schedule-task-title'),
                  controller: _title,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: '任务名称'),
                ),
                TextField(
                  key: const Key('schedule-task-notes'),
                  controller: _notes,
                  enabled: !_saving,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
                const SizedBox(height: 16),
                Text('安排日期：${dateKey(_date)}'),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: completed || _saving ? null : () => _offset(0),
                      child: const Text('今天'),
                    ),
                    TextButton(
                      onPressed: completed || _saving ? null : () => _offset(1),
                      child: const Text('明天'),
                    ),
                    TextButton(
                      key: const Key('pick-task-date'),
                      onPressed: completed || _saving ? null : _pickDate,
                      child: const Text('指定日期'),
                    ),
                  ],
                ),
                DropdownButtonFormField<EventRepeat>(
                  key: const Key('task-repeat'),
                  initialValue: _repeat,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '重复方式'),
                  items: [
                    for (final repeat in EventRepeat.values)
                      DropdownMenuItem(
                        value: repeat,
                        child: Text(
                          repeat == EventRepeat.once ? '不重复' : repeat.label,
                        ),
                      ),
                  ],
                  onChanged: completed || _saving
                      ? null
                      : (repeat) => setState(() => _repeat = repeat!),
                ),
                const SizedBox(height: 12),
                Text(
                  completed
                      ? '已完成记录的日期保留；下一次请新建任务。'
                      : '首次任务日期：${dateKey(first)}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (_repeat != EventRepeat.once)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '每次是独立记录，完成本次后安排下一次。未完成的重复记录保留原日期；重启后只补最近一次。改日期或规则会结束原来的重复安排并重新开始。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('save-task-schedule'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}
