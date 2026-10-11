import 'package:flutter/material.dart';

import 'models/good_day_event.dart';

class EventsArea extends StatelessWidget {
  const EventsArea({
    super.key,
    required this.events,
    required this.now,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final List<GoodDayEvent> events;
  final DateTime now;
  final void Function(GoodDayEvent? event) onEdit;
  final Future<void> Function(GoodDayEvent event, bool enabled) onToggle;
  final Future<void> Function(GoodDayEvent event) onDelete;

  @override
  Widget build(BuildContext context) {
    final sorted = List<GoodDayEvent>.of(events)
      ..sort((a, b) {
        if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
        return (a.nextReminderAt(now) ?? a.startsAt).compareTo(
          b.nextReminderAt(now) ?? b.startsAt,
        );
      });
    return ListView(
      key: const PageStorageKey('events-list'),
      padding: EdgeInsets.zero,
      children: [
        const Text(
          '到点弹窗提醒；隐藏到托盘后继续运行。',
          style: TextStyle(fontSize: 12, color: Color(0xFF626C64)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('add-event'),
          onPressed: () => onEdit(null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加待办事件'),
        ),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Text(
              '添加一次性或重复事件，例如开会、喝水、每周整理。',
              textAlign: TextAlign.center,
            ),
          ),
        for (final event in sorted)
          Container(
            key: ValueKey('event-${event.id}'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFDEE2DA), width: 0.7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: Key('edit-event-${event.id}'),
                        onTap: () => onEdit(event),
                        child: Text(
                          event.title,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      key: Key('enable-event-${event.id}'),
                      value: event.enabled,
                      onChanged: (value) => onToggle(event, value),
                    ),
                  ],
                ),
                Text(
                  '${event.repeat.label} · ${eventDateTimeLabel(event.startsAt)}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  event.snoozedUntil != null
                      ? '稍后提醒：${eventDateTimeLabel(event.snoozedUntil!)}'
                      : !event.enabled
                      ? (event.repeat == EventRepeat.once &&
                                event.handledThrough != null
                            ? '已提醒'
                            : '已暂停提醒')
                      : event.nextReminderAt(now) == null
                      ? '本次已提醒，请编辑时间以再次提醒'
                      : '下次提醒：${eventDateTimeLabel(event.nextReminderAt(now)!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF626C64),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => onEdit(event),
                      child: const Text('编辑'),
                    ),
                    TextButton(
                      key: Key('delete-event-${event.id}'),
                      onPressed: () => onDelete(event),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          '彻底退出或关机期间不会弹窗；启动或唤醒后补提醒。重复事件只补最近一次。可在设置中开启开机启动。',
          style: TextStyle(fontSize: 11, color: Color(0xFF626C64)),
        ),
      ],
    );
  }
}

class EventEditorDialog extends StatefulWidget {
  const EventEditorDialog({
    super.key,
    this.event,
    required this.now,
    required this.onSave,
  });
  final GoodDayEvent? event;
  final DateTime now;
  final Future<void> Function(GoodDayEvent event) onSave;
  @override
  State<EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<EventEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _notes, _minutes;
  late DateTime _startsAt;
  late EventRepeat _repeat;
  late bool _enabled;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _title = TextEditingController(text: event?.title ?? '');
    _notes = TextEditingController(text: event?.notes ?? '');
    _minutes = TextEditingController(text: '${event?.reminderMinutes ?? 0}');
    final initial = event?.startsAt ?? widget.now.add(const Duration(hours: 1));
    _startsAt = DateTime(
      initial.year,
      initial.month,
      initial.day,
      initial.hour,
      initial.minute,
    );
    _repeat = event?.repeat ?? EventRepeat.once;
    _enabled = event?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected != null && mounted) {
      setState(
        () => _startsAt = DateTime(
          selected.year,
          selected.month,
          selected.day,
          _startsAt.hour,
          _startsAt.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected != null && mounted) {
      setState(
        () => _startsAt = DateTime(
          _startsAt.year,
          _startsAt.month,
          _startsAt.day,
          selected.hour,
          selected.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        GoodDayEvent(
          id: widget.event?.id ?? '',
          title: _title.text,
          notes: _notes.text,
          startsAt: _startsAt,
          repeat: _repeat,
          reminderMinutes: int.parse(_minutes.text),
          enabled: _enabled,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，输入已保留：$error';
        });
      }
    }
  }

  DateTime _firstReminder(int minutes) {
    final event = GoodDayEvent(
      id: 'preview',
      title: '预览',
      startsAt: _startsAt,
      repeat: _repeat,
    );
    final first = event.nextOccurrenceAfter(
      _startsAt.subtract(const Duration(microseconds: 1)),
    )!;
    return first.subtract(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(12),
      title: Text(widget.event == null ? '添加待办事件' : '编辑待办事件'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('event-title'),
                  controller: _title,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: '要做什么',
                    hintText: '例如：参加会议',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写事件名称' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('event-notes'),
                  controller: _notes,
                  enabled: !_saving,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '备注（选填）'),
                ),
                const SizedBox(height: 12),
                Text(
                  '事件时间：${eventDateTimeLabel(_startsAt)}',
                  key: const Key('event-start-label'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: const Key('event-date'),
                      onPressed: _saving ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: const Text('选择日期'),
                    ),
                    TextButton.icon(
                      key: const Key('event-time'),
                      onPressed: _saving ? null : _pickTime,
                      icon: const Icon(Icons.schedule, size: 16),
                      label: const Text('选择时间'),
                    ),
                  ],
                ),
                DropdownButtonFormField<EventRepeat>(
                  key: const Key('event-repeat'),
                  initialValue: _repeat,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '重复方式'),
                  items: [
                    for (final repeat in EventRepeat.values)
                      DropdownMenuItem(
                        value: repeat,
                        child: Text(repeat.label),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _repeat = value!),
                ),
                if (_repeat == EventRepeat.weekly)
                  Text(
                    '每周在所选日期的星期${['一', '二', '三', '四', '五', '六', '日'][_startsAt.weekday - 1]}重复',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (_repeat == EventRepeat.monthly)
                  Text(
                    '每月 ${_startsAt.day} 日；当月没有这一天时，在月末提醒。',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (_repeat == EventRepeat.weekdays)
                  const Text(
                    '工作日指周一至周五，不按法定节假日调整。',
                    style: TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('event-reminder-minutes'),
                  controller: _minutes,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '提前多少分钟提醒',
                    helperText: '0 表示准时提醒，可设置 0～10080 分钟',
                  ),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 0 || number > 10080
                        ? '请输入 0～10080 的整数'
                        : null;
                  },
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final minutes in [0, 5, 10, 30, 60])
                      ActionChip(
                        label: Text(minutes == 0 ? '准时' : '$minutes 分钟'),
                        onPressed: _saving
                            ? null
                            : () => setState(() => _minutes.text = '$minutes'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (int.tryParse(_minutes.text) case final int minutes
                    when minutes >= 0 && minutes <= 10080)
                  Text(
                    '首次提醒：${eventDateTimeLabel(_firstReminder(minutes))}',
                    style: const TextStyle(fontSize: 12),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用提醒'),
                  value: _enabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    key: const Key('event-save-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('save-event'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}

class EventReminderDialog extends StatefulWidget {
  const EventReminderDialog({
    super.key,
    required this.event,
    required this.occurrence,
    required this.now,
    required this.onResolve,
  });
  final GoodDayEvent event;
  final DateTime occurrence, now;
  final Future<void> Function(Duration? snooze) onResolve;
  @override
  State<EventReminderDialog> createState() => _EventReminderDialogState();
}

class _EventReminderDialogState extends State<EventReminderDialog> {
  bool _saving = false;
  String? _error;
  Future<void> _resolve(Duration? snooze) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onResolve(snooze);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '未能保存提醒状态，请重试：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(12),
      title: const Text('待办事件提醒'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.event.title,
                key: const Key('reminder-event-title'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text('事件时间：${eventDateTimeLabel(widget.occurrence)}'),
              const SizedBox(height: 6),
              Text(
                widget.now.isAfter(widget.occurrence)
                    ? '这是错过的提醒，现在补提醒你。'
                    : widget.occurrence.isAfter(widget.now)
                    ? '这是提前提醒，请按上面的事件时间做好准备。'
                    : '现在该做这件事了。',
              ),
              if (widget.event.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(widget.event.notes),
                ),
              const SizedBox(height: 16),
              const Text('稍后提醒：'),
              Wrap(
                spacing: 6,
                children: [
                  for (final minutes in [5, 10, 30])
                    OutlinedButton(
                      key: Key('snooze-$minutes'),
                      onPressed: _saving
                          ? null
                          : () => _resolve(Duration(minutes: minutes)),
                      child: Text('$minutes 分钟后'),
                    ),
                ],
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('reminder-save-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('acknowledge-reminder'),
          onPressed: _saving ? null : () => _resolve(null),
          child: Text(_saving ? '保存中…' : '知道了'),
        ),
      ],
    ),
  );
}
