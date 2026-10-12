import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'data/vault_repository.dart';
import 'edit_safety.dart';
import 'models/good_day_goal.dart';
import 'models/good_day_task.dart';
import 'models/reminder_item.dart';
import 'task_inline_options.dart';

String reminderTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String reminderDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';
const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

class ReminderAgendaPage extends StatefulWidget {
  const ReminderAgendaPage({
    super.key,
    required this.repository,
    required this.date,
    required this.clock,
    required this.goals,
    required this.scheduled,
    required this.onEditingChanged,
  });
  final VaultRepository repository;
  final DateTime date;
  final DateTime Function() clock;
  final List<GoodDayGoal> goals;
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
  int _months = 3;
  bool _showCompleted = false;
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
      final items = await widget.repository.loadReminders();
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
    goals: widget.goals,
    onClosed: _closeEditor,
    onSaved: () async {
      _closeEditor();
      await _load();
    },
  );
  Widget _row(ReminderItem item, String section) {
    final goal = widget.goals
        .where((goal) => goal.id == item.goalId)
        .firstOrNull;
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    height: 26,
                    child: Checkbox(
                      key: Key('reminder-complete-${item.id}'),
                      value: item.isCompleted,
                      onChanged: (value) => _complete(item, value ?? false),
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 16,
                            color: goal == null
                                ? context.appColors.ink
                                : Color(goal.colorValue),
                            decoration: item.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (item.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              item.notes,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appColors.muted,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${isSameDay(item.dueAt, widget.date) ? '' : '${item.dueAt.month}月${item.dueAt.day}日 · '}${reminderTime(item.dueAt)}${item.rule.unit == RepeatUnit.none ? '' : ' · ${item.rule.label}'}',
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
                  Icon(
                    Icons.info_outline,
                    size: 17,
                    color: context.appColors.muted,
                  ),
                ],
              ),
            ),
          ),
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
  }) => Padding(
    key: Key('reminder-section-$key'),
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.appColors.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: context.appColors.line)),
          ],
        ),
        for (final item in items) _row(item, key),
        if (_draftSection == key && _editingItem == null)
          _edit(key)
        else if (canAdd)
          InkWell(
            key: Key('add-reminder-$key'),
            onTap: () => _openEditor(key, date),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 7),
              child: Row(
                children: [
                  Icon(Icons.add, size: 18, color: context.appColors.muted),
                  const SizedBox(width: 13),
                  Text(
                    '添加提醒事项',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
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
                icon: const Icon(Icons.add, size: 20),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
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
    for (var offset = 0; offset < 3; offset++) {
      final day = DateTime(today.year, today.month, today.day + offset);
      result.add(
        _section(
          'date-${dateKey(day)}',
          '${['今天', '明天', '后天'][offset]} · ${day.month}月${day.day}日',
          DateTime(day.year, day.month, day.day, 9),
          active.where((item) => isSameDay(item.dueAt, day)),
        ),
      );
    }
    final remaining = active.where(
      (item) => item.dueAt.isAfter(
        DateTime(today.year, today.month, today.day + 2, 23, 59),
      ),
    );
    final months = <DateTime>{
      if (DateTime(
        today.year,
        today.month + 1,
        0,
      ).isAfter(DateTime(today.year, today.month, today.day + 2)))
        DateTime(today.year, today.month),
      for (var offset = 1; offset <= _months; offset++)
        DateTime(today.year, today.month + offset),
      for (final item in remaining) DateTime(item.dueAt.year, item.dueAt.month),
    }.toList()..sort();
    for (final month in months) {
      final records = remaining
          .where(
            (item) =>
                item.dueAt.year == month.year &&
                item.dueAt.month == month.month,
          )
          .toList();
      result.add(
        ExpansionTile(
          maintainState: true,
          key: Key('schedule-month-${month.year}-${month.month}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 5),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            '${month.year}年${month.month}月',
            style: const TextStyle(fontSize: 16),
          ),
          subtitle: records.isEmpty
              ? const Text('暂无安排', style: TextStyle(fontSize: 11))
              : Text(
                  '${records.length} 项提醒',
                  style: const TextStyle(fontSize: 11),
                ),
          children: [
            for (
              var day = 1;
              day <= DateTime(month.year, month.month + 1, 0).day;
              day++
            )
              if (DateTime(
                month.year,
                month.month,
                day,
              ).isAfter(DateTime(today.year, today.month, today.day + 2)))
                _section(
                  'date-${dateKey(DateTime(month.year, month.month, day))}',
                  '$day日 · ${_weekdays[DateTime(month.year, month.month, day).weekday - 1]}',
                  DateTime(month.year, month.month, day, 9),
                  records.where((item) => item.dueAt.day == day),
                ),
          ],
        ),
      );
    }
    result.add(
      TextButton(
        onPressed: () => setState(() => _months += 3),
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
    required this.goals,
    required this.onClosed,
    required this.onSaved,
    this.item,
  });
  final VaultRepository repository;
  final DateTime initialDate;
  final List<GoodDayGoal> goals;
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
  String? _goal, _error;
  bool _busy = false,
      _customRepeat = false,
      _customLead = false,
      _showTime = false;
  late bool _enabled;
  final _interval = TextEditingController(text: '1');
  final _leadAmount = TextEditingController(text: '5');
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item?.title ?? '');
    _notes = TextEditingController(text: widget.item?.notes ?? '');
    _due = widget.item?.dueAt ?? widget.initialDate;
    _rule = widget.item?.rule ?? const ReminderRule(RepeatUnit.none);
    _early = widget.item?.early;
    _goal = widget.item?.goalId;
    _enabled = widget.item?.enabled ?? true;
    _interval.text = '${_rule.interval}';
    _customRepeat = !ReminderRule.presets.containsKey(_rule.label);
    _customLead =
        _early != null &&
        !EarlyReminder.presets.values.any(
          (lead) => lead?.label == _early!.label,
        );
    _leadAmount.text = '${_early?.amount ?? 5}';
    _title.addListener(markPendingEdit);
    _notes.addListener(markPendingEdit);
    _interval.addListener(markPendingEdit);
    _leadAmount.addListener(markPendingEdit);
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
    if (widget.item == null &&
        _title.text.trim().isEmpty &&
        _notes.text.trim().isEmpty &&
        !_detailsChanged) {
      widget.onClosed();
      return true;
    }
    final repeatInterval = int.tryParse(_interval.text);
    final leadAmount = int.tryParse(_leadAmount.text);
    if (_customRepeat &&
        (repeatInterval == null ||
            repeatInterval < 1 ||
            repeatInterval > 999)) {
      setState(() => _error = '重复间隔请输入 1～999');
      return false;
    }
    if (_customLead &&
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
      final early = _customLead
          ? EarlyReminder(leadAmount!, _early?.unit ?? LeadUnit.minute)
          : _early;
      await widget.repository.saveReminder(
        item: widget.item,
        title: _title.text,
        notes: _notes.text,
        dueAt: _due,
        rule: rule,
        early: early,
        goalId: _goal,
        enabled: _enabled,
      );
      await widget.onSaved();
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = '未保存，请重试：$error');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _detailsChanged = false;
  void _detail(VoidCallback change) {
    _detailsChanged = true;
    _change(change);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final repeatPreset = ReminderRule.presets.entries
        .where((entry) => entry.value.label == _rule.label)
        .firstOrNull
        ?.key;
    final leadPreset = EarlyReminder.presets.entries
        .where((entry) => entry.value?.label == _early?.label)
        .firstOrNull
        ?.key;
    return Container(
      key: const Key('reminder-editor'),
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('reminder-title'),
              controller: _title,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText: '提醒事项',
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 16),
              onSubmitted: (_) {
                _detailsChanged = true;
                _save();
              },
            ),
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
            TextButton.icon(
              key: const Key('reminder-date'),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: _busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
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
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(reminderDate(_due)),
            ),
            TextButton.icon(
              key: const Key('reminder-time'),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: _busy
                  ? null
                  : () => setState(() => _showTime = !_showTime),
              icon: const Icon(Icons.schedule, size: 17),
              label: Text(reminderTime(_due)),
            ),
            if (_showTime)
              ReminderClockWheels(
                value: _due,
                enabled: !_busy,
                onChanged: (date) => _detail(() => _due = date),
              ),
            DropdownButtonFormField<String>(
              key: const Key('reminder-repeat'),
              initialValue: _customRepeat ? '自定义' : repeatPreset ?? '自定义',
              isExpanded: true,
              decoration: const InputDecoration(labelText: '重复'),
              items: [
                for (final label in [...ReminderRule.presets.keys, '自定义'])
                  DropdownMenuItem(
                    value: label,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _detail(() {
                      _customRepeat = value == '自定义';
                      if (!_customRepeat) {
                        _rule = ReminderRule.presets[value]!;
                      } else {
                        _rule = ReminderRule(
                          _rule.unit == RepeatUnit.none
                              ? RepeatUnit.day
                              : _rule.unit,
                          weekdays: _rule.weekdays,
                        );
                        _interval.text = '${_rule.interval}';
                      }
                    }),
            ),
            if (_customRepeat) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('每 '),
                  Expanded(
                    child: TextField(
                      key: const Key('custom-repeat-interval'),
                      enabled: !_busy,
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<RepeatUnit>(
                    value: _rule.unit,
                    items: [
                      for (final unit in RepeatUnit.values.where(
                        (unit) => unit != RepeatUnit.none,
                      ))
                        DropdownMenuItem(
                          value: unit,
                          child: Text(switch (unit) {
                            RepeatUnit.hour => '小时',
                            RepeatUnit.day => '天',
                            RepeatUnit.week => '周',
                            RepeatUnit.month => '月',
                            RepeatUnit.year => '年',
                            RepeatUnit.none => '',
                          }),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (unit) => _detail(() => _rule = ReminderRule(unit!)),
                  ),
                ],
              ),
              if (_rule.unit == RepeatUnit.week)
                Wrap(
                  spacing: 4,
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
                                  weekdays: days.toList()..sort(),
                                );
                              }),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('early-reminder'),
              initialValue: _customLead ? '自定义' : leadPreset ?? '自定义',
              isExpanded: true,
              decoration: const InputDecoration(labelText: '提前提醒'),
              items: [
                for (final label in [...EarlyReminder.presets.keys, '自定义'])
                  DropdownMenuItem(
                    value: label,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _detail(() {
                      _customLead = value == '自定义';
                      if (!_customLead) _early = EarlyReminder.presets[value];
                    }),
            ),
            if (_customLead)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('custom-lead-amount'),
                      enabled: !_busy,
                      controller: _leadAmount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<LeadUnit>(
                    value: _early?.unit ?? LeadUnit.minute,
                    items: [
                      for (final unit in LeadUnit.values)
                        DropdownMenuItem(
                          value: unit,
                          child: Text(switch (unit) {
                            LeadUnit.minute => '分钟前',
                            LeadUnit.hour => '小时前',
                            LeadUnit.day => '天前',
                            LeadUnit.week => '周前',
                            LeadUnit.month => '个月前',
                          }),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (unit) => _detail(
                            () => _early = EarlyReminder(
                              int.tryParse(_leadAmount.text) ?? 5,
                              unit!,
                            ),
                          ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('提醒我', style: TextStyle(fontSize: 13)),
              value: _enabled,
              onChanged: _busy
                  ? null
                  : (value) => _detail(() => _enabled = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: widget.goals.any((goal) => goal.id == _goal)
                  ? _goal
                  : '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: '所属目标'),
              items: [
                const DropdownMenuItem(value: '', child: Text('无')),
                for (final goal in widget.goals)
                  DropdownMenuItem(
                    value: goal.id,
                    child: Text(
                      goal.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(goal.colorValue),
                      ),
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (goal) => _detail(() => _goal = goal == '' ? null : goal),
            ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFA65345), fontSize: 12),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
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
                TextButton(
                  key: const Key('cancel-reminder'),
                  onPressed: _busy ? null : widget.onClosed,
                  child: const Text('取消'),
                ),
              ],
            ),
            if (widget.item != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('删除这条提醒？'),
                            content: const Text('删除后可以从垃圾桶恢复。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          setState(() => _busy = true);
                          try {
                            await widget.repository.deleteReminder(
                              widget.item!,
                            );
                            await widget.onSaved();
                          } catch (error) {
                            if (mounted) {
                              setState(() => _error = '未删除，请重试：$error');
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        }
                      },
                child: const Text('删除提醒事项'),
              ),
          ],
        ),
      ),
    );
  }
}
