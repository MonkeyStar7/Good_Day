import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'models/good_day_task.dart';
import 'models/good_day_event.dart';

class ReminderClockWheels extends StatelessWidget {
  const ReminderClockWheels({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _NumberWheel(
          name: '时',
          count: 24,
          selected: value.hour,
          enabled: enabled,
          label: (hour) => hour.toString().padLeft(2, '0'),
          onChanged: (hour) => onChanged(
            DateTime(value.year, value.month, value.day, hour, value.minute),
          ),
        ),
      ),
      Expanded(
        child: _NumberWheel(
          name: '分',
          count: 60,
          selected: value.minute,
          enabled: enabled,
          label: (minute) => minute.toString().padLeft(2, '0'),
          onChanged: (minute) => onChanged(
            DateTime(value.year, value.month, value.day, value.hour, minute),
          ),
        ),
      ),
    ],
  );
}

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
  final Future<void> Function(
    EventRepeat repeat,
    DateTime? reminderAt,
    int intervalMinutes,
  )
  onSave;
  final ValueChanged<bool> onEditingChanged;
  final bool enabled;
  @override
  State<TaskInlineOptions> createState() => _TaskInlineOptionsState();
}

class _TaskInlineOptionsState extends State<TaskInlineOptions> {
  bool _open = false, _custom = false, _busy = false, _repeating = false;
  String? _error;
  late DateTime _selected;
  Duration _delay = const Duration(minutes: 5);
  final _intervalController = TextEditingController(text: '30');
  int _unit = 1;
  bool get _enabled =>
      widget.task.reminder?.enabled == true &&
      (widget.task.reminder?.expiresAt == null ||
          widget.clock().isBefore(widget.task.reminder!.expiresAt!));
  int get _periodMinutes => widget.task.period
      .end(widget.task.scheduledDate)
      .difference(widget.task.period.start(widget.task.scheduledDate))
      .inMinutes;
  int get _maxAmount => (_periodMinutes - 1) ~/ _unit;
  @override
  void initState() {
    super.initState();
    _resetTime();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  void _resetTime() {
    final now = widget.clock();
    _selected = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _delay = const Duration(minutes: 5);
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

  void _openReminder() {
    setState(() {
      _resetTime();
      _open = true;
      _custom = widget.task.period != TaskPeriod.day;
      _error = null;
      final interval = widget.task.reminder?.intervalMinutes ?? 0;
      _repeating = interval > 0;
      _unit =
          interval > 0 &&
              interval % 1440 == 0 &&
              widget.task.period != TaskPeriod.day
          ? 1440
          : interval > 0 && interval % 60 == 0
          ? 60
          : 1;
      _intervalController.text = '${interval > 0 ? interval ~/ _unit : 30}';
    });
    widget.onEditingChanged(true);
  }

  int? _interval() {
    if (!_repeating) return 0;
    final amount = int.tryParse(_intervalController.text);
    if (amount == null || amount < 1 || amount > _maxAmount) {
      setState(
        () => _error =
            '重复提醒间隔请输入 1～$_maxAmount ${_unit == 1
                ? '分钟'
                : _unit == 60
                ? '小时'
                : '天'}，且不能跨越任务周期',
      );
      return null;
    }
    return amount * _unit;
  }

  Future<void> _save(
    EventRepeat repeat,
    DateTime? time, {
    int? keptInterval,
  }) async {
    if (_busy) return;
    final interval = time == null ? 0 : keptInterval ?? _interval();
    if (interval == null) return;
    final keeping =
        time == widget.task.reminder?.startsAt &&
        interval == (widget.task.reminder?.intervalMinutes ?? 0);
    if (time != null &&
        !keeping &&
        (!time.isAfter(widget.clock()) ||
            !widget.task.period.contains(time, widget.task.scheduledDate))) {
      setState(() => _error = '请选择未来且在${widget.task.period.label}内的提醒时间');
      return;
    }
    widget.onEditingChanged(true);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(repeat, time, interval);
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

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || widget.task.isCompleted || !widget.enabled;
    final expired = widget.task.isWaitingForSchedule(widget.clock());
    final repeat = widget.task.repeat;
    final candidate = widget.task.period == TaskPeriod.day
        ? widget.clock().add(_delay)
        : _selected;
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopupMenuButton<EventRepeat>(
          key: Key('task-repeat-settings-${widget.task.id}'),
          enabled: !disabled && !_open,
          onOpened: () => widget.onEditingChanged(true),
          onCanceled: () => widget.onEditingChanged(false),
          onSelected: (value) => _save(
            value,
            widget.task.reminder?.startsAt,
            keptInterval: widget.task.reminder?.intervalMinutes ?? 0,
          ),
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
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                Icon(Icons.event_repeat, size: 16, color: colors.muted),
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
                onPressed: disabled || expired
                    ? null
                    : () {
                        if (!_open) _openReminder();
                      },
                child: const Text('提醒我', style: TextStyle(fontSize: 12)),
              ),
            ),
            Switch.adaptive(
              key: Key('task-options-remind-${widget.task.id}'),
              value: _open || _enabled,
              onChanged: disabled || (expired && !_enabled)
                  ? null
                  : (value) {
                      if (value && !expired) {
                        _openReminder();
                      } else if (!value && widget.task.reminder != null) {
                        _save(repeat, null);
                      } else if (!value) {
                        _cancel();
                      }
                    },
            ),
          ],
        ),
        if (expired)
          Text(
            '先重新安排任务，再设置当前周期的提醒',
            style: TextStyle(fontSize: 11, color: colors.muted),
          ),
        if (!_open && widget.task.reminder != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '${eventDateTimeLabel(widget.task.reminder!.startsAt)} · ${widget.task.reminder!.intervalMinutes > 0 ? '每 ${widget.task.reminder!.intervalMinutes} 分钟' : '只提醒一次'} · ${_enabled ? '已开启' : '已停止'}',
              style: TextStyle(fontSize: 11, color: colors.muted),
            ),
          ),
        if (_open) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final recurring in [false, true])
                ChoiceChip(
                  key: Key(
                    'reminder-${recurring ? 'repeat' : 'once'}-${widget.task.id}',
                  ),
                  label: Text(
                    recurring ? '重复提醒' : '只提醒一次',
                    style: const TextStyle(fontSize: 12),
                  ),
                  showCheckmark: false,
                  selected: _repeating == recurring,
                  onSelected: disabled
                      ? null
                      : (_) => setState(() {
                          _repeating = recurring;
                          _error = null;
                        }),
                ),
            ],
          ),
          if (_repeating) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('每 ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: TextField(
                    key: Key('reminder-interval-${widget.task.id}'),
                    controller: _intervalController,
                    enabled: !disabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '间隔',
                      contentPadding: EdgeInsets.all(8),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 6),
                DropdownButton<int>(
                  key: Key('reminder-interval-unit-${widget.task.id}'),
                  value: _unit,
                  items: [
                    const DropdownMenuItem(value: 1, child: Text('分钟')),
                    const DropdownMenuItem(value: 60, child: Text('小时')),
                    if (widget.task.period != TaskPeriod.day)
                      const DropdownMenuItem(value: 1440, child: Text('天')),
                  ],
                  onChanged: disabled
                      ? null
                      : (value) => setState(() {
                          _unit = value!;
                          _error = null;
                        }),
                ),
                const Text('提醒', style: TextStyle(fontSize: 12)),
              ],
            ),
            Text(
              '未完成时继续提醒，${widget.task.period.label}结束后停止',
              style: TextStyle(fontSize: 11, color: colors.muted),
            ),
          ],
          const SizedBox(height: 10),
          if (widget.task.period == TaskPeriod.day) ...[
            Text('多久以后提醒', style: TextStyle(fontSize: 12, color: colors.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final minutes in [5, 30, 60])
                  OutlinedButton(
                    key: Key('remind-after-${widget.task.id}-$minutes'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 34),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: disabled
                        ? null
                        : () => _save(
                            repeat,
                            widget.clock().add(Duration(minutes: minutes)),
                          ),
                    child: Text(
                      minutes == 5
                          ? '5 分钟后'
                          : minutes == 30
                          ? '半小时后'
                          : '1 小时后',
                    ),
                  ),
              ],
            ),
            TextButton(
              key: Key('custom-reminder-${widget.task.id}'),
              onPressed: disabled
                  ? null
                  : () => setState(() {
                      if (!_custom) {
                        _resetTime();
                        _error = null;
                      }
                      _custom = !_custom;
                    }),
              child: Text(_custom ? '收起自定义时间' : '自定义时间'),
            ),
          ],
          if (_custom) ...[
            if (widget.task.period == TaskPeriod.day)
              DelayReminderWheels(
                key: ValueKey('reminder-wheels-${widget.task.id}'),
                value: _delay,
                enabled: !disabled,
                onChanged: (value) => setState(() {
                  _delay = value;
                  _error = null;
                }),
              )
            else
              InlineReminderWheels(
                key: ValueKey('reminder-wheels-${widget.task.id}'),
                period: widget.task.period,
                anchor: widget.task.scheduledDate,
                value: _selected,
                now: widget.clock(),
                enabled: !disabled,
                onChanged: (value) => setState(() {
                  _selected = value;
                  _error = null;
                }),
              ),
            const SizedBox(height: 8),
            Text(
              '预计提醒：${eventDateTimeLabel(candidate)}',
              style: TextStyle(fontSize: 11, color: colors.muted),
            ),
            const SizedBox(height: 6),
            FilledButton(
              key: Key('save-task-options-${widget.task.id}'),
              onPressed: disabled ? null : () => _save(repeat, candidate),
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

Widget _wheel(
  String name,
  int count,
  int selected,
  String Function(int) label,
  bool enabled,
  ValueChanged<int> change,
) => Expanded(
  child: _NumberWheel(
    key: ValueKey('wheel-$name-$count'),
    name: name,
    count: count,
    selected: selected.clamp(0, count - 1),
    label: label,
    enabled: enabled,
    onChanged: change,
  ),
);

class DelayReminderWheels extends StatelessWidget {
  const DelayReminderWheels({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final Duration value;
  final bool enabled;
  final ValueChanged<Duration> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: context.appColors.paper,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        _wheel(
          '小时后',
          24,
          value.inHours,
          (i) => '$i',
          enabled,
          (i) => onChanged(Duration(hours: i, minutes: value.inMinutes % 60)),
        ),
        _wheel(
          '分钟后',
          60,
          value.inMinutes % 60,
          (i) => '$i',
          enabled,
          (i) => onChanged(Duration(hours: value.inHours, minutes: i)),
        ),
      ],
    ),
  );
}

class InlineReminderWheels extends StatelessWidget {
  const InlineReminderWheels({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.period,
    required this.anchor,
    required this.now,
  });
  final DateTime value, anchor, now;
  final TaskPeriod period;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;
  void _change({int? month, int? day, int? hour, int? minute}) {
    final year = period == TaskPeriod.year ? anchor.year : value.year;
    final m = month ?? value.month;
    final d = (day ?? value.day).clamp(1, DateTime(year, m + 1, 0).day);
    onChanged(DateTime(year, m, d, hour ?? value.hour, minute ?? value.minute));
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: context.appColors.paper,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        if (period == TaskPeriod.week)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < 7; i++)
                ChoiceChip(
                  key: Key('reminder-weekday-${i + 1}'),
                  label: Text(
                    '周${['一', '二', '三', '四', '五', '六', '日'][i]}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: value.weekday == i + 1,
                  showCheckmark: false,
                  onSelected:
                      !enabled ||
                          !period
                              .start(anchor)
                              .add(Duration(days: i + 1))
                              .isAfter(now)
                      ? null
                      : (_) {
                          final d = period.start(anchor).add(Duration(days: i));
                          onChanged(
                            DateTime(
                              d.year,
                              d.month,
                              d.day,
                              value.hour,
                              value.minute,
                            ),
                          );
                        },
                ),
            ],
          ),
        if (period == TaskPeriod.month || period == TaskPeriod.year)
          Row(
            children: [
              if (period == TaskPeriod.year)
                _wheel(
                  '月',
                  12,
                  value.month - 1,
                  (i) => '${i + 1}',
                  enabled,
                  (i) => _change(month: i + 1),
                ),
              _wheel(
                '日',
                DateTime(value.year, value.month + 1, 0).day,
                value.day - 1,
                (i) => '${i + 1}',
                enabled,
                (i) => _change(day: i + 1),
              ),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            _wheel(
              '时',
              24,
              value.hour,
              (i) => i.toString().padLeft(2, '0'),
              enabled,
              (i) => _change(hour: i),
            ),
            _wheel(
              '分',
              60,
              value.minute,
              (i) => i.toString().padLeft(2, '0'),
              enabled,
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
  late final FixedExtentScrollController _controller;
  double _dragDistance = 0;
  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: widget.selected,
      keepScrollOffset: false,
    );
  }

  void _step(int delta) {
    if (!widget.enabled || !_controller.hasClients) return;
    final next = (_controller.selectedItem + delta).clamp(0, widget.count - 1);
    _controller.jumpToItem(next);
  }

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
        style: TextStyle(fontSize: 11, color: context.appColors.muted),
      ),
      SizedBox(
        height: 84,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
                GestureBinding.instance.pointerSignalResolver.register(event, (
                  signal,
                ) {
                  _step(event.scrollDelta.dy > 0 ? 1 : -1);
                  event.respond(allowPlatformDefault: false);
                });
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => _dragDistance = 0,
              onVerticalDragUpdate: (details) {
                _dragDistance += details.delta.dy;
                if (_dragDistance.abs() >= 28) {
                  _step(_dragDistance < 0 ? 1 : -1);
                  _dragDistance = 0;
                }
              },
              onTapUp: (details) {
                if (details.localPosition.dy < 28) _step(-1);
                if (details.localPosition.dy > 56) _step(1);
              },
              child: IgnorePointer(
                child: CupertinoPicker.builder(
                  selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                    background: context.appColors.hover,
                  ),
                  scrollController: _controller,
                  itemExtent: 28,
                  useMagnifier: true,
                  magnification: 1.08,
                  onSelectedItemChanged: widget.onChanged,
                  childCount: widget.count,
                  itemBuilder: (_, index) => Center(
                    child: Text(
                      widget.label(index),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        color: context.appColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
