import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'data/vault_repository.dart';
import 'edit_safety.dart';
import 'models/good_day_task.dart';
import 'models/reminder_item.dart';
import 'task_inline_options.dart';

String reminderTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String reminderDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';
const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

StrutStyle _reminderControlStrut(BuildContext context) =>
    StrutStyle.fromTextStyle(
      Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13, height: 1),
      forceStrutHeight: true,
    );

class ReminderAgendaPage extends StatefulWidget {
  const ReminderAgendaPage({
    super.key,
    required this.repository,
    required this.date,
    required this.clock,
    required this.scheduled,
    required this.onEditingChanged,
  });
  final VaultRepository repository;
  final DateTime date;
  final DateTime Function() clock;
  final bool scheduled;
  final ValueChanged<bool> onEditingChanged;
  @override
  State<ReminderAgendaPage> createState() => _ReminderAgendaPageState();
}

class _ReminderAgendaPageState extends State<ReminderAgendaPage> {
  List<ReminderItem> _items = [];
  StreamSubscription<void>? _subscription;
  ReminderItem? _editingItem;
  DateTime? _draftDate;
  String? _draftSection, _error;
  int _months = 12;
  bool _showCompleted = false;
  final _expandedMonths = <String>{};
  var _editor = GlobalKey<ReminderEditorState>();
  @override
  void initState() {
    super.initState();
    _subscription = widget.repository.reminderChanges.listen((_) => _load());
    _load();
  }

  @override
  void didUpdateWidget(covariant ReminderAgendaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.date, widget.date)) _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    widget.onEditingChanged(false);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.loadReminders(
        through: widget.scheduled
            ? DateTime(widget.date.year, widget.date.month + _months + 1, 0)
            : null,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '读取失败：$error');
    }
  }

  void _closeEditor() {
    if (!mounted) return;
    setState(() {
      _editingItem = null;
      _draftDate = null;
      _draftSection = null;
    });
    widget.onEditingChanged(false);
  }

  Future<void> _openEditor(
    String section,
    DateTime date, [
    ReminderItem? item,
  ]) async {
    if (!await (_editor.currentState?.flushPendingEdits() ??
        Future.value(true))) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _editor = GlobalKey<ReminderEditorState>();
      _draftSection = section;
      _draftDate = date;
      _editingItem = item;
    });
    widget.onEditingChanged(true);
  }

  Future<void> _complete(ReminderItem item, bool completed) async {
    if (!await (_editor.currentState?.flushPendingEdits() ??
        Future.value(true))) {
      return;
    }
    try {
      await widget.repository.completeReminder(item, completed);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '未保存，请重试：$error');
    }
  }

  Widget _edit(String section) => ReminderEditor(
    key: _editor,
    repository: widget.repository,
    item: _editingItem,
    initialDate: _draftDate!,
    onClosed: _closeEditor,
    onSaved: () async {
      _closeEditor();
      await _load();
    },
  );
  Future<void> _completeSubtask(
    ReminderItem item,
    GoodDaySubtask task,
    bool value,
  ) async {
    if (!await (_editor.currentState?.flushPendingEdits() ??
        Future.value(true))) {
      return;
    }
    try {
      await widget.repository.setReminderSubtaskCompleted(item, task.id, value);
    } catch (error) {
      if (mounted) setState(() => _error = '未保存，请重试：$error');
    }
  }

  Widget _row(ReminderItem item, String section) {
    final overdue = !item.isCompleted && item.dueAt.isBefore(widget.clock());
    return Column(
      children: [
        if (_editingItem?.id == item.id && _draftSection == section)
          _edit(section)
        else
          InkWell(
            key: Key('reminder-row-${item.id}'),
            onTap: () => _openEditor(section, item.dueAt, item),
            child: Padding(
              padding: EdgeInsets.only(
                top: 12,
                bottom: item.subtasks.isEmpty ? 12 : 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 30,
                        height: 28,
                        child: Checkbox(
                          key: Key('reminder-complete-${item.id}'),
                          value: item.isCompleted,
                          onChanged: (value) => _complete(item, value ?? false),
                          shape: const CircleBorder(),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.appColors.ink,
                            decoration: item.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.arrow_right,
                          key: Key('reminder-indicator-${item.id}'),
                          size: 22,
                          color: context.appColors.muted,
                        ),
                      ),
                    ],
                  ),
                  if (item.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 37, top: 4),
                      child: Text(
                        item.notes,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.muted,
                        ),
                      ),
                    ),
                  if (item.rule.unit != RepeatUnit.none)
                    Padding(
                      padding: const EdgeInsets.only(left: 37, top: 4),
                      child: Text(
                        '待办重复 · ${item.rule.label}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.appColors.muted,
                        ),
                      ),
                    ),
                  if (item.enabled)
                    Padding(
                      padding: const EdgeInsets.only(left: 37, top: 4),
                      child: Text(
                        '${isSameDay(item.dueAt, widget.date) ? '' : '${item.dueAt.month}月${item.dueAt.day}日 · '}${reminderTime(item.dueAt)}${item.early == null ? '' : ' · ${item.early!.label}'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: overdue
                              ? const Color(0xFFA65345)
                              : context.appColors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_editingItem?.id != item.id)
          for (final task in item.subtasks)
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: InkWell(
                key: Key('reminder-subtask-${task.id}'),
                canRequestFocus: false,
                onTap: item.isCompleted
                    ? null
                    : () => _completeSubtask(item, task, !task.isCompleted),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        height: 28,
                        child: Checkbox(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          value: task.isCompleted,
                          onChanged: item.isCompleted
                              ? null
                              : (value) => _completeSubtask(
                                  item,
                                  task,
                                  value ?? false,
                                ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appColors.muted,
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (_editingItem?.id != item.id && item.subtasks.isNotEmpty)
          const SizedBox(height: 8),
        Divider(
          height: 1,
          color: context.appColors.line.withValues(alpha: 0.65),
        ),
      ],
    );
  }

  Widget _section(
    String key,
    String label,
    DateTime date,
    Iterable<ReminderItem> items, {
    bool canAdd = true,
  }) {
    final records = items.toList();
    return Padding(
      key: Key('reminder-section-$key'),
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('add-reminder-$key'),
            onTap: canAdd ? () => _openEditor(key, date) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: context.appColors.muted.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: context.appColors.line.withValues(alpha: 0.65),
          ),
          for (final item in records) _row(item, key),
          if (_draftSection == key && _editingItem == null)
            _edit(key)
          else if (canAdd && records.isNotEmpty)
            Semantics(
              label: '添加下一条事项',
              button: true,
              child: InkWell(
                key: Key('next-reminder-$key'),
                onTap: () => _openEditor(key, date),
                child: SizedBox(
                  height: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: SizedBox.square(
                        dimension: 22,
                        child: CustomPaint(
                          painter: _DottedCirclePainter(
                            context.appColors.muted.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.date;
    final today = DateTime(now.year, now.month, now.day);
    final active = _items.where((item) => !item.isCompleted);
    final completed = _items
        .where((item) => item.isCompleted && isSameDay(item.completedAt!, now))
        .toList();
    final overdue = active.where((item) => item.dueAt.isBefore(today));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.scheduled ? '计划' : '今天',
          key: Key(widget.scheduled ? 'scheduled-heading' : 'today-heading'),
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w400,
            color: context.appColors.accent,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                '${reminderDate(today)} · ${_weekdays[today.weekday - 1]}',
                style: TextStyle(fontSize: 12, color: context.appColors.muted),
              ),
            ),
            if (widget.scheduled)
              IconButton(
                key: const Key('add-scheduled-date'),
                tooltip: '选择日期添加',
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    builder: (context, child) => Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: child,
                    ),
                    initialDate: today,
                    firstDate: DateTime(1970),
                    lastDate: DateTime(2126),
                  );
                  if (date != null) {
                    await _openEditor(
                      'chosen-date',
                      DateTime(date.year, date.month, date.day, 9),
                    );
                  }
                },
              ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFA65345), fontSize: 12),
          ),
        Expanded(
          child: ListView(
            key: Key(
              widget.scheduled ? 'scheduled-list' : 'today-reminder-list',
            ),
            padding: EdgeInsets.zero,
            children: [
              if (_draftSection == 'chosen-date') _edit('chosen-date'),
              if (overdue.isNotEmpty)
                _section('overdue', '已过期', today, overdue, canAdd: false),
              if (!widget.scheduled) ...[
                for (var section = 0; section < 3; section++)
                  _section(
                    ['morning', 'afternoon', 'tonight'][section],
                    ['上午', '下午', '今晚'][section],
                    DateTime(
                      today.year,
                      today.month,
                      today.day,
                      [9, 15, 20][section],
                    ),
                    active.where(
                      (item) =>
                          isSameDay(item.dueAt, today) &&
                          item.daySection == section,
                    ),
                  ),
              ] else
                ..._scheduled(today, active),
              if (completed.isNotEmpty) ...[
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () =>
                      setState(() => _showCompleted = !_showCompleted),
                  child: Text(
                    '${completed.length} 项已完成 · ${_showCompleted ? '隐藏' : '显示'}',
                  ),
                ),
                if (_showCompleted)
                  for (final item in completed) _row(item, 'completed'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _scheduled(DateTime today, Iterable<ReminderItem> active) {
    final result = <Widget>[];
    // Always include tomorrow and the day after, even at a week boundary.
    final visibleDays = (8 - today.weekday).clamp(3, 7);
    final end = DateTime(today.year, today.month, today.day + visibleDays);
    Widget daySection(DateTime day) => _section(
      'date-${dateKey(day)}',
      '${isSameDay(day, today)
          ? '今天'
          : isSameDay(day, DateTime(today.year, today.month, today.day + 1))
          ? '明天'
          : isSameDay(day, DateTime(today.year, today.month, today.day + 2))
          ? '后天'
          : _weekdays[day.weekday - 1]} · ${day.month}月${day.day}日',
      DateTime(day.year, day.month, day.day, 9),
      active.where((item) => isSameDay(item.dueAt, day)),
    );
    for (var offset = 0; offset < visibleDays; offset++) {
      result.add(
        daySection(DateTime(today.year, today.month, today.day + offset)),
      );
    }
    final nextMonth = DateTime(today.year, today.month + 1);
    if (end.isBefore(nextMonth)) {
      result.add(
        ExpansionTile(
          maintainState: true,
          onExpansionChanged: (expanded) => setState(() {
            final id = '${today.year}-${today.month}';
            expanded ? _expandedMonths.add(id) : _expandedMonths.remove(id);
          }),
          trailing: Icon(
            _expandedMonths.contains('${today.year}-${today.month}')
                ? Icons.arrow_drop_down
                : Icons.arrow_right,
          ),
          key: Key('schedule-month-${today.year}-${today.month}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 5),
          title: Text(
            '${today.month}月其他时间',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w500,
              color: context.appColors.muted,
            ),
          ),
          children: [
            for (
              var day = end.day;
              day <
                  nextMonth.day + DateTime(today.year, today.month + 1, 0).day;
              day++
            )
              daySection(DateTime(today.year, today.month, day)),
          ],
        ),
      );
    }
    final months = <DateTime>{
      for (var offset = 1; offset <= _months; offset++)
        DateTime(today.year, today.month + offset),
      for (final item in active)
        if (!item.dueAt.isBefore(nextMonth))
          DateTime(item.dueAt.year, item.dueAt.month),
    }.toList()..sort();
    for (final month in months) {
      final records = active
          .where(
            (item) =>
                item.dueAt.year == month.year &&
                item.dueAt.month == month.month,
          )
          .toList();
      // The preview may already include the first days of the next month.
      final days = records.map((item) => item.dueAt.day).toSet().toList()
        ..sort();
      final monthKey = 'month-${month.year}-${month.month}';
      result.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: Key('schedule-month-${month.year}-${month.month}'),
              onTap: () => _openEditor(
                monthKey,
                DateTime(month.year, month.month, 1, 9),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 17,
                  horizontal: 5,
                ),
                child: Text(
                  '${month.year}年${month.month}月',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: records.isEmpty
                        ? context.appColors.muted
                        : context.appColors.ink,
                  ),
                ),
              ),
            ),
            if (_draftSection == monthKey) _edit(monthKey),
            for (final day in days)
              if (!DateTime(month.year, month.month, day).isBefore(end))
                daySection(DateTime(month.year, month.month, day)),
            Divider(
              height: 1,
              color: context.appColors.line.withValues(alpha: 0.65),
            ),
          ],
        ),
      );
    }
    result.add(
      TextButton(
        onPressed: () {
          setState(() => _months += 3);
          _load();
        },
        child: const Text('更多月份'),
      ),
    );
    return result;
  }
}

class ReminderEditor extends StatefulWidget {
  const ReminderEditor({
    super.key,
    required this.repository,
    required this.initialDate,
    required this.onClosed,
    required this.onSaved,
    this.item,
  });
  final VaultRepository repository;
  final DateTime initialDate;
  final ReminderItem? item;
  final VoidCallback onClosed;
  final Future<void> Function() onSaved;
  @override
  State<ReminderEditor> createState() => ReminderEditorState();
}

class ReminderEditorState extends State<ReminderEditor>
    with
        AutomaticKeepAliveClientMixin<ReminderEditor>,
        ReliableEditor<ReminderEditor> {
  late final TextEditingController _title, _notes;
  late DateTime _due;
  late ReminderRule _rule;
  EarlyReminder? _early;
  String? _error;
  bool _busy = false,
      _customRepeat = false,
      _customLead = false,
      _showTime = false;
  late bool _enabled;
  late List<GoodDaySubtask> _subtasks;
  bool _subtasksChanged = false;
  int _subtaskSequence = 0;
  ReminderItem? _persistedItem;
  bool _emptyDiscarded = false;
  final _interval = TextEditingController(text: '1');
  final _leadAmount = TextEditingController(text: '5');
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item?.title ?? '');
    _persistedItem = widget.item;
    _notes = TextEditingController(text: widget.item?.notes ?? '');
    _due = widget.item?.dueAt ?? widget.initialDate;
    _rule = widget.item?.rule ?? const ReminderRule(RepeatUnit.none);
    _early = widget.item?.early;
    _enabled = widget.item?.enabled ?? false;
    _subtasks = [...?widget.item?.subtasks];
    _interval.text = '${_rule.interval}';
    _customRepeat = !ReminderRule.presets.containsKey(_rule.label);
    _customLead =
        _early != null &&
        !EarlyReminder.presets.values.any(
          (lead) => lead?.label == _early!.label,
        );
    _leadAmount.text = '${_early?.amount ?? 5}';
    _watchText(_title);
    _watchText(_notes);
    _watchText(_interval);
    _watchText(_leadAmount);
    // Closing to the tray must close even an untouched editor, otherwise it
    // would keep background reminder delivery suspended indefinitely.
    markPendingEdit();
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _interval.dispose();
    _leadAmount.dispose();
    super.dispose();
  }

  void _watchText(TextEditingController controller) {
    var text = controller.text;
    controller.addListener(() {
      if (text == controller.text) return;
      text = controller.text;
      markPendingEdit();
    });
  }

  @override
  Future<void> onEditsFlushed() async {
    if (!_emptyDiscarded) await widget.onSaved();
  }

  void _change(VoidCallback change) {
    markPendingEdit();
    setState(change);
  }

  Future<void> _save() async {
    markPendingEdit();
    await flushPendingEdits();
  }

  @override
  Future<bool> persistEdits() async {
    if (_persistedItem == null &&
        _title.text.trim().isEmpty &&
        _notes.text.trim().isEmpty &&
        !_detailsChanged) {
      _emptyDiscarded = true;
      widget.onClosed();
      return true;
    }
    _emptyDiscarded = false;
    final repeatInterval = int.tryParse(_interval.text);
    final leadAmount = int.tryParse(_leadAmount.text);
    if (_customRepeat &&
        (repeatInterval == null ||
            repeatInterval < 1 ||
            repeatInterval > 999)) {
      setState(() => _error = '重复间隔请输入 1～999');
      return false;
    }
    if (_enabled &&
        _customLead &&
        (leadAmount == null || leadAmount < 1 || leadAmount > 200)) {
      setState(() => _error = '提前提醒请输入 1～200');
      return false;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rule = _customRepeat
          ? ReminderRule(
              _rule.unit,
              interval: repeatInterval!,
              weekdays: _rule.weekdays,
            )
          : _rule;
      final early = _enabled && _customLead
          ? EarlyReminder(leadAmount!, _early?.unit ?? LeadUnit.minute)
          : _early;
      _persistedItem = await widget.repository.saveReminder(
        item: _persistedItem,
        title: _title.text,
        notes: _notes.text,
        dueAt: _due,
        rule: rule,
        calendarRepeat: rule.unit.index >= RepeatUnit.day.index,
        repeatReminderMinutes: null,
        early: early,
        goalId: widget.item?.goalId,
        enabled: _enabled,
        subtasks: _subtasksChanged
            ? [
                for (var i = 0; i < _subtasks.length; i++)
                  _subtasks[i].copyWith(
                    title: _subtasks[i].title.trim().isEmpty
                        ? '未命名${i + 1}'
                        : _subtasks[i].title.trim(),
                  ),
              ]
            : null,
      );
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = '未保存，请重试：$error');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _inlineReminderControls(BuildContext context) => _ReminderSettingCard(
    key: const Key('reminder-settings-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('reminder-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('设置提醒', style: TextStyle(fontSize: 13)),
          value: _enabled,
          onChanged: _busy
              ? null
              : (value) => _detail(() {
                  _enabled = value;
                  _error = null;
                }),
        ),
        if (_enabled) ...[
          const SizedBox(height: 8),
          _reminderControls(context),
        ],
      ],
    ),
  );

  Widget _reminderNumber(
    String name,
    TextEditingController controller,
    String label,
  ) => _ReminderNumberField(
    name: name,
    controller: controller,
    label: label,
    enabled: !_busy,
    onChanged: (_) => _detail(() => _error = null),
  );

  Widget _todoRepeatControls(BuildContext context) {
    final colors = context.appColors;
    final repeatPreset = ReminderRule.presets.entries
        .where((entry) => entry.value.label == _rule.label)
        .firstOrNull
        ?.key;
    return _ReminderSettingCard(
      key: const Key('todo-repeat-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('todo-repeat-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('待办重复', style: TextStyle(fontSize: 13)),
            value: _rule.unit != RepeatUnit.none,
            onChanged: (value) => _detail(() {
              _rule = value
                  ? ReminderRule.presets['每天']!
                  : ReminderRule.presets['不重复']!;
              _customRepeat = false;
            }),
          ),
          if (_rule.unit != RepeatUnit.none)
            Row(
              children: [
                Text('频率', style: TextStyle(fontSize: 13, color: colors.muted)),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReminderChoice<String>(
                    key: const Key('reminder-repeat'),
                    value:
                        _customRepeat || ['每分钟', '每小时'].contains(repeatPreset)
                        ? '自定义'
                        : repeatPreset ?? '自定义',
                    labels: {
                      for (final label in [
                        ...ReminderRule.presets.keys.where(
                          (label) => !['不重复', '每分钟', '每小时'].contains(label),
                        ),
                        '自定义',
                      ])
                        label: label,
                    },
                    onChanged: _busy
                        ? null
                        : (value) => _detail(() {
                            _customRepeat = value == '自定义';
                            _error = null;
                            if (!_customRepeat) {
                              _rule = ReminderRule.presets[value]!;
                            } else {
                              _rule = ReminderRule(
                                _rule.unit == RepeatUnit.none
                                    ? RepeatUnit.day
                                    : _rule.unit,
                                interval: _rule.interval,
                                weekdays: _rule.weekdays,
                              );
                              _interval.text = '${_rule.interval}';
                            }
                          }),
                  ),
                ),
              ],
            ),
          if (_customRepeat) ...[
            const SizedBox(height: 12),
            _ReminderIntervalRow(
              prefix: '每',
              suffix: '一次',
              number: _reminderNumber(
                'custom-repeat-interval',
                _interval,
                '重复间隔',
              ),
              unit: SizedBox(
                width: 68,
                child: _ReminderChoice<RepeatUnit>(
                  key: const Key('custom-repeat-unit'),
                  value: _rule.unit,
                  labels: {
                    if (_rule.unit == RepeatUnit.minute)
                      RepeatUnit.minute: '分钟',
                    if (_rule.unit == RepeatUnit.hour) RepeatUnit.hour: '小时',
                    RepeatUnit.day: '天',
                    RepeatUnit.week: '周',
                    RepeatUnit.month: '个月',
                    RepeatUnit.year: '年',
                  },
                  onChanged: _busy
                      ? null
                      : (unit) => _detail(
                          () => _rule = ReminderRule(
                            unit,
                            interval: _rule.interval,
                            weekdays: unit == RepeatUnit.week
                                ? _rule.weekdays
                                : const [],
                          ),
                        ),
                ),
              ),
            ),
            if (_rule.unit == RepeatUnit.week) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(
                        _weekdays[day - 1],
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _rule.weekdays.contains(day),
                      showCheckmark: false,
                      onSelected: _busy
                          ? null
                          : (selected) => _detail(() {
                              final days = _rule.weekdays.toSet();
                              selected ? days.add(day) : days.remove(day);
                              _rule = ReminderRule(
                                RepeatUnit.week,
                                interval: _rule.interval,
                                weekdays: days.toList()..sort(),
                              );
                            }),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _reminderControls(BuildContext context) {
    final leadPreset = EarlyReminder.presets.entries
        .where((entry) => entry.value?.label == _early?.label)
        .firstOrNull
        ?.key;
    final colors = context.appColors;
    final dateStyle = TextButton.styleFrom(
      backgroundColor: colors.controlFill,
      foregroundColor: colors.ink,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      side: BorderSide(color: colors.controlLine),
      minimumSize: Size.zero,
      textStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('日期与时间', style: TextStyle(fontSize: 13, color: colors.muted)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Tooltip(
                    message: reminderDate(_due),
                    child: TextButton.icon(
                      key: const Key('reminder-date'),
                      style: dateStyle,
                      onPressed: _busy
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                context: context,
                                builder: (context, child) => Padding(
                                  padding: const EdgeInsets.only(left: 56),
                                  child: child,
                                ),
                                initialDate: _due,
                                firstDate: DateTime(
                                  _due.year < 1970 ? _due.year : 1970,
                                ),
                                lastDate: DateTime(
                                  (_due.year > 2126 ? _due.year : 2126) + 1,
                                ),
                              );
                              if (date != null) {
                                _detail(
                                  () => _due = DateTime(
                                    date.year,
                                    date.month,
                                    date.day,
                                    _due.hour,
                                    _due.minute,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.calendar_today_outlined, size: 14),
                      label: Text(
                        '${_due.month}月${_due.day}日',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextButton.icon(
                    key: const Key('reminder-time'),
                    style: dateStyle,
                    onPressed: _busy
                        ? null
                        : () => _change(() => _showTime = !_showTime),
                    icon: const Icon(Icons.schedule, size: 14),
                    label: Text(reminderTime(_due), maxLines: 1),
                  ),
                ),
              ],
            ),
            if (_showTime) ...[
              const SizedBox(height: 8),
              ReminderClockWheels(
                value: _due,
                enabled: !_busy,
                onChanged: (date) => _detail(() => _due = date),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '提前提醒',
                  style: TextStyle(fontSize: 13, color: colors.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReminderChoice<String>(
                    key: const Key('early-reminder'),
                    value: _customLead ? '自定义' : leadPreset ?? '自定义',
                    labels: {
                      for (final label in [
                        ...EarlyReminder.presets.keys,
                        '自定义',
                      ])
                        label: label,
                    },
                    onChanged: _busy
                        ? null
                        : (value) => _detail(() {
                            _customLead = value == '自定义';
                            _error = null;
                            if (!_customLead) {
                              _early = EarlyReminder.presets[value];
                            }
                            if (_early != null) {
                              _leadAmount.text = '${_early!.amount}';
                            }
                          }),
                  ),
                ),
              ],
            ),
            if (_customLead) ...[
              const SizedBox(height: 12),
              _ReminderIntervalRow(
                prefix: '提前',
                suffix: '提醒',
                number: _reminderNumber(
                  'custom-lead-amount',
                  _leadAmount,
                  '提前时间',
                ),
                unit: SizedBox(
                  width: 68,
                  child: _ReminderChoice<LeadUnit>(
                    key: const Key('custom-lead-unit'),
                    value: _early?.unit ?? LeadUnit.minute,
                    labels: const {
                      LeadUnit.minute: '分钟',
                      LeadUnit.hour: '小时',
                      LeadUnit.day: '天',
                      LeadUnit.week: '周',
                      LeadUnit.month: '个月',
                    },
                    onChanged: _busy
                        ? null
                        : (unit) => _detail(
                            () => _early = EarlyReminder(
                              int.tryParse(_leadAmount.text) ?? 5,
                              unit,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFA65345), fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await widget.repository.deleteReminder(widget.item!);
      await widget.onSaved();
    } catch (error) {
      if (mounted) setState(() => _error = '未删除，请重试：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _editSubtask(int index, {String? title, bool? completed}) => _detail(() {
    _subtasksChanged = true;
    _subtasks[index] = _subtasks[index].copyWith(
      title: title,
      isCompleted: completed,
    );
  });

  bool _detailsChanged = false;
  void _detail(VoidCallback change) {
    _detailsChanged = true;
    _change(change);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      key: const Key('reminder-editor'),
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.radio_button_unchecked,
                    size: 22,
                    color: context.appColors.muted,
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('reminder-title'),
                    controller: _title,
                    autofocus: true,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      hintText: '添加待办事项名称',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.appColors.ink,
                    ),
                    onSubmitted: (_) {
                      _detailsChanged = true;
                      _save();
                    },
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.arrow_drop_down,
                    key: const Key('reminder-state-indicator'),
                    size: 19,
                    color: context.appColors.muted,
                  ),
                ),
                if (widget.item != null)
                  IconButton(
                    key: const Key('delete-reminder'),
                    tooltip: '移入垃圾桶',
                    onPressed: _busy ? null : _delete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: context.appColors.muted,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('reminder-notes'),
                    controller: _notes,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      hintText: '备注',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    maxLines: null,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...[
                    const SizedBox(height: 8),
                    for (var index = 0; index < _subtasks.length; index++)
                      Row(
                        key: Key('edit-subtask-${_subtasks[index].id}'),
                        children: [
                          Checkbox(
                            value: _subtasks[index].isCompleted,
                            onChanged: _busy
                                ? null
                                : (value) =>
                                      _editSubtask(index, completed: value),
                          ),
                          Expanded(
                            child: TextFormField(
                              key: Key('subtask-title-${_subtasks[index].id}'),
                              initialValue: _subtasks[index].title,
                              enabled: !_busy,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: '子任务',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (value) =>
                                  _editSubtask(index, title: value),
                            ),
                          ),
                          IconButton(
                            tooltip: '删除子任务',
                            icon: const Icon(Icons.close, size: 15),
                            onPressed: _busy
                                ? null
                                : () => _detail(() {
                                    _subtasksChanged = true;
                                    _subtasks.removeAt(index);
                                  }),
                          ),
                        ],
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                      key: const Key('add-reminder-subtask'),
                      onPressed: _busy
                          ? null
                          : () => _detail(() {
                              _subtasksChanged = true;
                              _subtasks.add(
                                GoodDaySubtask(
                                  id: 'sub_${DateTime.now().microsecondsSinceEpoch}_${_subtaskSequence++}',
                                  title: '',
                                ),
                              );
                            }),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加子任务'),
                    ),
                  ],
                  _todoRepeatControls(context),
                  const SizedBox(height: 8),
                  _inlineReminderControls(context),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFA65345),
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          key: const Key('save-reminder'),
                          onPressed: _busy
                              ? null
                              : () {
                                  _detailsChanged = true;
                                  _save();
                                },
                          child: Text(_busy ? '保存中…' : '完成'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton(
                          key: const Key('cancel-reminder'),
                          onPressed: _busy ? null : widget.onClosed,
                          child: const Text('取消'),
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
    );
  }
}

class _DottedCirclePainter extends CustomPainter {
  const _DottedCirclePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final circle = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 2,
    );
    for (var dash = 0; dash < 16; dash++) {
      canvas.drawArc(circle, dash * math.pi / 8, math.pi / 20, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ReminderSettingCard extends StatelessWidget {
  const _ReminderSettingCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Color.lerp(context.appColors.paper, context.appColors.panel, 0.65),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.appColors.line.withValues(alpha: 0.4)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// Keep every preset while bounding the menu to a compact, scrollable list.
class _ReminderChoice<T> extends StatelessWidget {
  const _ReminderChoice({
    super.key,
    required this.value,
    required this.labels,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T>? onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: context.appColors.controlFill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.appColors.controlLine),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        elevation: 3,
        menuMaxHeight: math.min(240, MediaQuery.sizeOf(context).height * 0.4),
        itemHeight: 48,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: context.appColors.paper.withValues(alpha: 1),
        focusColor: context.appColors.hover,
        style: Theme.of(context).textTheme.bodyMedium!
            .copyWith(fontSize: 13, height: 1, color: context.appColors.ink),
        icon: Icon(Icons.expand_more, size: 16, color: context.appColors.muted),
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem<T>(
              value: entry.key,
              child: Text(
                entry.value,
                strutStyle: _reminderControlStrut(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged!(next);
              },
      ),
    ),
  );
}

/// Shared columns align both interval sentences horizontally and vertically.
class _ReminderIntervalRow extends StatelessWidget {
  const _ReminderIntervalRow({
    required this.prefix,
    required this.suffix,
    required this.number,
    required this.unit,
  });
  final String prefix, suffix;
  final Widget number, unit;
  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 13, height: 1, color: context.appColors.ink),
    child: SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(prefix, strutStyle: _reminderControlStrut(context)),
          ),
          const SizedBox(width: 6),
          number,
          const SizedBox(width: 6),
          unit,
          const SizedBox(width: 6),
          Expanded(
            child: Text(suffix, strutStyle: _reminderControlStrut(context)),
          ),
        ],
      ),
    ),
  );
}

/// Draw the box outside InputDecorator so helper space cannot shrink its face.
class _ReminderNumberField extends StatefulWidget {
  const _ReminderNumberField({
    required this.name,
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });
  final String name, label;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  State<_ReminderNumberField> createState() => _ReminderNumberFieldState();
}

class _ReminderNumberFieldState extends State<_ReminderNumberField> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        key: Key('${widget.name}-box'),
        width: 44,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: context.appColors.paper,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused
                ? Theme.of(context).colorScheme.primary
                : context.appColors.line.withValues(alpha: 0.7),
          ),
        ),
        child: Center(
          child: TextField(
            key: Key(widget.name),
            enabled: widget.enabled,
            controller: widget.controller,
            strutStyle: _reminderControlStrut(context),
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontSize: 13,
              height: 1,
              color: context.appColors.ink,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            // The outer box owns its border and spacing. Bypass the decorator's
            // label/helper baseline so digits center exactly like the unit text.
            decoration: null,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    ),
  );
}
