import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models/good_day_task.dart';
import 'models/repeat_schedule.dart';

/// Options stay beside the task; a custom draft is committed explicitly.
class TaskInlineOptions extends StatefulWidget {
  const TaskInlineOptions({
    super.key,
    required this.task,
    required this.clock,
    required this.onSave,
    required this.onEditingChanged,
    this.enabled = true,
  });
  final GoodDayTask task;
  final DateTime Function() clock;
  final Future<void> Function(EventRepeat repeat, DateTime? reminderAt) onSave;
  final ValueChanged<bool> onEditingChanged;
  final bool enabled;

  @override
  State<TaskInlineOptions> createState() => _TaskInlineOptionsState();
}

class _TaskInlineOptionsState extends State<TaskInlineOptions> {
  bool _open = false;
  bool _custom = false;
  bool _busy = false;
  String? _error;
  late DateTime _selected;

  bool get _enabled => widget.task.reminder?.enabled == true;

  @override
  void initState() {
    super.initState();
    _resetTime();
  }

  void _resetTime() {
    final now = widget.clock();
    final value = now;
    _selected = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
  }

  void _cancel() {
    setState(() {
      _open = false;
      _custom = false;
      _error = null;
      _resetTime();
    });
    widget.onEditingChanged(false);
  }

  Future<void> _save(EventRepeat repeat, DateTime? time) async {
    if (_busy) return;
    // Keeping an acknowledged reminder while changing repetition is allowed.
    if (time != null &&
        time != widget.task.reminder?.startsAt &&
        !time.isAfter(widget.clock())) {
      setState(() => _error = '请选择未来的提醒时间，或使用几分钟后');
      return;
    }
    widget.onEditingChanged(true);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(repeat, time);
      if (!mounted) return;
      setState(() {
        _open = false;
        _custom = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '未保存，请重试：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onEditingChanged(_open);
      }
    }
  }

  void _openReminder() {
    setState(() {
      _resetTime();
      _open = true;
      _custom = false;
      _error = null;
    });
    widget.onEditingChanged(true);
  }

  String get _reminderLabel {
    final reminder = widget.task.reminder;
    if (_open) return '提醒我';
    if (reminder == null) return '不提醒我';
    if (!reminder.enabled) {
      return reminder.handledThrough == null ? '提醒已暂停' : '已提醒';
    }
    return '提醒我 · ${reminder.startsAt.month}/${reminder.startsAt.day} ${reminder.startsAt.hour.toString().padLeft(2, '0')}:${reminder.startsAt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || widget.task.isCompleted || !widget.enabled;
    final repeat = widget.task.repeat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopupMenuButton<EventRepeat>(
          key: Key('task-repeat-settings-${widget.task.id}'),
          enabled: !disabled && !_open,
          onOpened: () => widget.onEditingChanged(true),
          onCanceled: () => widget.onEditingChanged(false),
          onSelected: (value) => _save(value, widget.task.reminder?.startsAt),
          initialValue: repeat,
          itemBuilder: (_) => [
            for (final value in EventRepeat.values)
              PopupMenuItem(
                value: value,
                child: Text(value == EventRepeat.once ? '不重复' : value.label),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD7DFD2)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_repeat,
                  size: 16,
                  color: Color(0xFF626C64),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    repeat == EventRepeat.once ? '不重复' : repeat.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextButton(
                key: Key('task-reminder-settings-${widget.task.id}'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: disabled || _open ? null : _openReminder,
                child: Text(
                  _reminderLabel,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            Switch.adaptive(
              key: Key('task-options-remind-${widget.task.id}'),
              value: _open || _enabled,
              onChanged: disabled
                  ? null
                  : (value) {
                      if (value) {
                        _openReminder();
                      } else if (widget.task.reminder != null) {
                        _save(repeat, null);
                      } else {
                        _cancel();
                      }
                    },
            ),
          ],
        ),
        if (_open) ...[
          const Text(
            '多久以后提醒',
            style: TextStyle(fontSize: 12, color: Color(0xFF626C64)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final minutes in [5, 15, 30, 60, 120])
                OutlinedButton(
                  key: Key('remind-after-${widget.task.id}-$minutes'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 12),
                  ),
                  onPressed: disabled
                      ? null
                      : () => _save(
                          repeat,
                          widget.clock().add(Duration(minutes: minutes)),
                        ),
                  child: Text(
                    minutes < 60 ? '$minutes 分钟后' : '${minutes ~/ 60} 小时后',
                  ),
                ),
            ],
          ),
          TextButton(
            key: Key('custom-reminder-${widget.task.id}'),
            onPressed: disabled
                ? null
                : () => setState(() => _custom = !_custom),
            child: Text(_custom ? '收起自定义时间' : '自定义时间'),
          ),
          if (_custom) ...[
            InlineReminderWheels(
              key: ValueKey('reminder-wheels-${widget.task.id}'),
              value: _selected,
              enabled: !disabled,
              onChanged: (value) => setState(() {
                _selected = value;
                _error = null;
              }),
            ),
            const SizedBox(height: 6),
            FilledButton(
              key: Key('save-task-options-${widget.task.id}'),
              onPressed: disabled ? null : () => _save(repeat, _selected),
              child: const Text('设置提醒'),
            ),
          ],
          TextButton(
            onPressed: disabled ? null : _cancel,
            child: const Text('取消'),
          ),
        ],
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Text(
            _error!,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8B3A32)),
          ),
      ],
    );
  }
}

/// Separate wheels keep the date and 24-hour clock usable in narrow windows.
class InlineReminderWheels extends StatelessWidget {
  const InlineReminderWheels({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final DateTime value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  void _change({int? year, int? month, int? day, int? hour, int? minute}) {
    final y = year ?? value.year;
    final m = month ?? value.month;
    final last = DateTime(y, m + 1, 0).day;
    final d = (day ?? value.day).clamp(1, last);
    onChanged(DateTime(y, m, d, hour ?? value.hour, minute ?? value.minute));
  }

  Widget _wheel(
    String name,
    int count,
    int selected,
    String Function(int) label,
    ValueChanged<int> changed,
  ) => Expanded(
    child: _NumberWheel(
      key: ValueKey('wheel-$name-$count'),
      name: name,
      count: count,
      selected: selected,
      label: label,
      enabled: enabled,
      onChanged: changed,
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F5F0),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Row(
          children: [
            _wheel(
              '年',
              201,
              value.year - 2000,
              (i) => '${2000 + i}',
              (i) => _change(year: 2000 + i),
            ),
            _wheel(
              '月',
              12,
              value.month - 1,
              (i) => '${i + 1}',
              (i) => _change(month: i + 1),
            ),
            _wheel(
              '日',
              DateTime(value.year, value.month + 1, 0).day,
              value.day - 1,
              (i) => '${i + 1}',
              (i) => _change(day: i + 1),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _wheel(
              '时',
              24,
              value.hour,
              (i) => i.toString().padLeft(2, '0'),
              (i) => _change(hour: i),
            ),
            _wheel(
              '分',
              60,
              value.minute,
              (i) => i.toString().padLeft(2, '0'),
              (i) => _change(minute: i),
            ),
          ],
        ),
      ],
    ),
  );
}

class _NumberWheel extends StatefulWidget {
  const _NumberWheel({
    super.key,
    required this.name,
    required this.count,
    required this.selected,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });
  final String name;
  final int count;
  final int selected;
  final String Function(int) label;
  final bool enabled;
  final ValueChanged<int> onChanged;
  @override
  State<_NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<_NumberWheel> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.selected);
  @override
  void didUpdateWidget(covariant _NumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected &&
        _controller.hasClients &&
        _controller.selectedItem != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToItem(widget.selected);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        widget.name,
        style: const TextStyle(fontSize: 11, color: Color(0xFF626C64)),
      ),
      SizedBox(
        height: 84,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: CupertinoPicker.builder(
            scrollController: _controller,
            itemExtent: 28,
            useMagnifier: true,
            magnification: 1.08,
            onSelectedItemChanged: widget.onChanged,
            childCount: widget.count,
            itemBuilder: (_, index) => Center(
              child: Text(
                widget.label(index),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontSize: 15, color: const Color(0xFF242C27)),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
