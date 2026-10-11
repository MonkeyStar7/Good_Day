import 'package:flutter/material.dart';

import 'models/good_day_task.dart';
import 'models/repeat_schedule.dart';

class TaskOptionsDialog extends StatefulWidget {
  const TaskOptionsDialog({
    super.key,
    required this.task,
    required this.now,
    required this.onSave,
  });
  final GoodDayTask task;
  final DateTime now;
  final Future<void> Function(EventRepeat repeat, DateTime? reminderAt) onSave;

  @override
  State<TaskOptionsDialog> createState() => _TaskOptionsDialogState();
}

class _TaskOptionsDialogState extends State<TaskOptionsDialog> {
  late EventRepeat _repeat;
  late bool _remind;
  late DateTime _reminderAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repeat = widget.task.repeat;
    _remind = widget.task.reminder != null;
    final nextHour = widget.now.add(const Duration(hours: 1));
    _reminderAt =
        widget.task.reminder?.startsAt ??
        DateTime(
          nextHour.year,
          nextHour.month,
          nextHour.day,
          nextHour.hour,
          nextHour.minute,
        );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderAt,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: '选择提醒日期',
    );
    if (date != null && mounted) {
      setState(
        () => _reminderAt = DateTime(
          date.year,
          date.month,
          date.day,
          _reminderAt.hour,
          _reminderAt.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderAt),
      helpText: '选择提醒时间',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null && mounted) {
      setState(
        () => _reminderAt = DateTime(
          _reminderAt.year,
          _reminderAt.month,
          _reminderAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_remind &&
        _reminderAt != widget.task.reminder?.startsAt &&
        !_reminderAt.isAfter(widget.now)) {
      setState(() => _error = '请选择未来的提醒时间');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_repeat, _remind ? _reminderAt : null);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '未保存，请重试：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      backgroundColor: const Color(0xFFF5F5F0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('重复与提醒'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<EventRepeat>(
                key: const Key('task-options-repeat'),
                initialValue: _repeat,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '重复',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final repeat in EventRepeat.values)
                    DropdownMenuItem(
                      value: repeat,
                      child: Text(
                        repeat == EventRepeat.once ? '不重复' : repeat.label,
                      ),
                    ),
                ],
                onChanged: _saving || widget.task.isCompleted
                    ? null
                    : (value) => setState(() => _repeat = value!),
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                key: const Key('task-options-remind'),
                contentPadding: EdgeInsets.zero,
                title: const Text('提醒我'),
                value: _remind,
                onChanged: _saving || widget.task.isCompleted
                    ? null
                    : (value) => setState(() => _remind = value),
              ),
              if (_remind) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('task-options-reminder-date'),
                      onPressed: _saving || widget.task.isCompleted
                          ? null
                          : _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(dateKey(_reminderAt)),
                    ),
                    OutlinedButton.icon(
                      key: const Key('task-options-reminder-time'),
                      onPressed: _saving || widget.task.isCompleted
                          ? null
                          : _pickTime,
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(
                        '${_reminderAt.hour.toString().padLeft(2, '0')}:${_reminderAt.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _repeat == EventRepeat.once
                      ? '在这个时间弹窗提醒。确认提醒不会自动完成待办。'
                      : '后续每次待办沿用这个提醒时刻。确认提醒不会自动完成待办。',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF626C64),
                    height: 1.5,
                  ),
                ),
              ],
              if (widget.task.isCompleted)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '已完成的待办不会弹出提醒；需要新的安排请添加待办。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFF8B3A32),
                      fontSize: 12,
                    ),
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
          key: const Key('save-task-options'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
