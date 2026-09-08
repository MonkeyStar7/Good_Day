import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import 'data/vault_repository.dart';
import 'models/good_day_task.dart';
import 'settings/app_settings.dart';
import 'settings/vault_location_store.dart';

const _ink = Color(0xFF202421);
const _muted = Color(0xFF707571);
const _line = Color(0x4D737873);
const _windowSize = Size(400, 720);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final vaultLocationStore = await VaultLocationStore.create();
  final savedVault = await vaultLocationStore.load();
  final repository = savedVault == null
      ? await VaultRepository.createDefault()
      : VaultRepository(savedVault);
  await repository.initialize();
  await vaultLocationStore.save(repository.vaultDirectory);
  final settingsController = await AppSettingsController.load(
    repository.vaultDirectory,
  );

  await acrylic.Window.initialize();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: _windowSize,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setMinimumSize(const Size(340, 500));
    await windowManager.setResizable(true);
    await windowManager.setHasShadow(true);
    await acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.transparent,
      color: Colors.transparent,
    );
    await windowManager.setAlignment(Alignment.topRight);
    final aligned = await windowManager.getPosition();
    await windowManager.setPosition(Offset(aligned.dx - 16, aligned.dy + 16));
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    GoodDayApp(
      repository: repository,
      settingsController: settingsController,
      vaultLocationStore: vaultLocationStore,
    ),
  );
}

class GoodDayApp extends StatelessWidget {
  const GoodDayApp({
    super.key,
    required this.repository,
    required this.settingsController,
    this.vaultLocationStore,
  });

  final VaultRepository repository;
  final AppSettingsController settingsController;
  final VaultLocationStore? vaultLocationStore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final settings = settingsController.settings;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Good Day',
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.transparent,
            fontFamily: settings.font.family,
            colorScheme: ColorScheme.fromSeed(
              seedColor: settings.accent.color,
              primary: settings.accent.color,
              surface: const Color(0xFFF1F2F0),
            ),
            checkboxTheme: CheckboxThemeData(
              shape: const CircleBorder(),
              side: const BorderSide(color: Color(0xFF858B86), width: 1.3),
              fillColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? settings.accent.color
                    : Colors.transparent,
              ),
              checkColor: const WidgetStatePropertyAll(Colors.white),
            ),
            snackBarTheme: const SnackBarThemeData(
              backgroundColor: Color(0xEE2B302D),
              contentTextStyle: TextStyle(color: Colors.white),
              behavior: SnackBarBehavior.floating,
            ),
          ),
          home: HomePage(
            repository: repository,
            settingsController: settingsController,
            vaultLocationStore: vaultLocationStore,
          ),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.settingsController,
    this.vaultLocationStore,
  });

  final VaultRepository repository;
  final AppSettingsController settingsController;
  final VaultLocationStore? vaultLocationStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<GoodDayTask> _tasks = [];
  late VaultRepository _repository;
  bool _loading = true;
  bool _isAdding = false;
  String? _expandedTaskId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tasks = await _repository.loadTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _addTask() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final task = await _repository.addTask(title);
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _isAdding = false;
      _tasks = [task, ..._tasks];
    });
  }

  void _startAdding() {
    setState(() => _isAdding = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _cancelAdding() {
    _controller.clear();
    setState(() => _isAdding = false);
  }

  Future<void> _toggleTask(GoodDayTask task, bool? value) async {
    final updated = await _repository.setCompleted(task, value ?? false);
    if (!mounted) return;
    setState(() {
      final index = _tasks.indexWhere((item) => item.id == task.id);
      if (index >= 0) _tasks[index] = updated;
      _sortTasks();
    });
  }

  Future<void> _deleteTask(GoodDayTask task) async {
    await _repository.deleteTask(task);
    if (!mounted) return;
    setState(() {
      _tasks.removeWhere((item) => item.id == task.id);
      if (_expandedTaskId == task.id) _expandedTaskId = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('任务已移到 Archive')));
  }

  GoodDayTask _taskById(String taskId) =>
      _tasks.firstWhere((task) => task.id == taskId);

  void _replaceTask(GoodDayTask updated, {bool sort = false}) {
    final index = _tasks.indexWhere((task) => task.id == updated.id);
    if (index >= 0) _tasks[index] = updated;
    if (sort) _sortTasks();
  }

  Future<void> _updateTaskDetails(
    String taskId,
    String title,
    String notes,
  ) async {
    final updated = await _repository.updateTaskDetails(
      _taskById(taskId),
      title: title,
      notes: notes,
    );
    if (mounted) setState(() => _replaceTask(updated));
  }

  Future<void> _addSubtask(String taskId, String title) async {
    final updated = await _repository.addSubtask(_taskById(taskId), title);
    if (mounted) setState(() => _replaceTask(updated));
  }

  Future<void> _updateSubtask(
    String taskId,
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) async {
    final updated = await _repository.updateSubtask(
      _taskById(taskId),
      subtaskId,
      title: title,
      isCompleted: isCompleted,
    );
    if (mounted) setState(() => _replaceTask(updated));
  }

  Future<void> _removeSubtask(String taskId, String subtaskId) async {
    final updated = await _repository.removeSubtask(
      _taskById(taskId),
      subtaskId,
    );
    if (mounted) setState(() => _replaceTask(updated));
  }

  void _sortTasks() {
    _tasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<String> _changeVault(
    String selectedPath, {
    required bool deleteSourceAfterMigration,
  }) async {
    final previousRepository = _repository;
    final targetDirectory = Directory(selectedPath);
    await targetDirectory.create(recursive: true);

    final currentPath =
        (await previousRepository.vaultDirectory.resolveSymbolicLinks())
            .toLowerCase();
    final targetPath = (await targetDirectory.resolveSymbolicLinks())
        .toLowerCase();
    if (currentPath == targetPath) return '已经在使用这个文件夹';

    final nextRepository = VaultRepository(targetDirectory);
    final containsExistingData = await nextRepository.hasVaultData();
    if (!containsExistingData) {
      await previousRepository.copyDataTo(targetDirectory);
    }

    await nextRepository.initialize();
    final tasks = await nextRepository.loadTasks();
    await widget.settingsController.useVault(targetDirectory);
    await widget.vaultLocationStore?.save(targetDirectory);

    if (mounted) {
      setState(() {
        _repository = nextRepository;
        _tasks = tasks;
        _loading = false;
        _error = null;
      });
    }
    if (containsExistingData) return '已切换到这个 Good Day Vault，没有删除原数据';
    if (!deleteSourceAfterMigration) return '已复制数据并切换，原文件仍保留';

    try {
      await previousRepository.deleteManagedData();
      return '迁移完成，原位置中的 Good Day 数据已删除';
    } on FileSystemException catch (error) {
      return '迁移已完成，但原数据删除失败：${error.message}';
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (context, animation, secondaryAnimation) => SettingsPage(
          controller: widget.settingsController,
          initialVaultPath: _repository.vaultDirectory.path,
          onVaultSelected: _changeVault,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completed = _tasks.where((task) => task.isCompleted).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xE6F2F3F1),
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Column(
          children: [
            _WindowBar(onSettings: _openSettings),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TodayHeader(
                      date: DateTime.now(),
                      completed: completed,
                      total: _tasks.length,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(taskCount: _tasks.length),
                    const SizedBox(height: 8),
                    Expanded(child: _buildTaskArea()),
                    const Divider(height: 1, thickness: 0.7, color: _line),
                    const SizedBox(height: 12),
                    _VaultStatus(path: _repository.vaultDirectory.path),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskArea() {
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: _ink),
        ),
      );
    }
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    return Scrollbar(
      thickness: 2,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _tasks.length + 5,
        itemBuilder: (context, index) {
          if (index < _tasks.length) {
            final task = _tasks[index];
            return _TaskTile(
              key: ValueKey(task.id),
              number: index + 1,
              task: task,
              expanded: _expandedTaskId == task.id,
              onToggleExpanded: () => setState(() {
                _expandedTaskId = _expandedTaskId == task.id ? null : task.id;
              }),
              onChanged: (value) => _toggleTask(task, value),
              onDetailsChanged: (title, notes) =>
                  _updateTaskDetails(task.id, title, notes),
              onAddSubtask: (title) => _addSubtask(task.id, title),
              onUpdateSubtask: (subtaskId, {title, isCompleted}) =>
                  _updateSubtask(
                    task.id,
                    subtaskId,
                    title: title,
                    isCompleted: isCompleted,
                  ),
              onRemoveSubtask: (subtaskId) =>
                  _removeSubtask(task.id, subtaskId),
              onDelete: () => _deleteTask(task),
            );
          }
          if (index == _tasks.length) {
            return _AddTaskRow(
              number: index + 1,
              editing: _isAdding,
              controller: _controller,
              focusNode: _focusNode,
              onStart: _startAdding,
              onAdd: _addTask,
              onCancel: _cancelAdding,
            );
          }
          return _BlankTaskRow(number: index + 1);
        },
      ),
    );
  }
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({this.title = 'GOOD DAY', this.onBack, this.onSettings});

  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0x14000000),
        border: Border(bottom: BorderSide(color: _line, width: 0.7)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            _WindowButton(
              icon: Icons.arrow_back,
              tooltip: '返回',
              onPressed: onBack!,
            ),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF555A56),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onSettings != null)
            _SettingsButton(
              key: const Key('settings-button'),
              onPressed: onSettings!,
            ),
          _WindowButton(
            icon: Icons.remove,
            tooltip: '最小化',
            onPressed: windowManager.minimize,
          ),
          _WindowButton(
            icon: Icons.close,
            tooltip: '关闭',
            onPressed: windowManager.close,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: 16,
        color: const Color(0xFF444945),
        hoverColor: const Color(0x16000000),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '设置',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: const Color(0x16000000),
          child: const SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: CustomPaint(
                size: Size.square(18),
                painter: _GearPainter(Color(0xFF444945)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GearPainter extends CustomPainter {
  const _GearPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (var index = 0; index < 8; index++) {
      canvas.save();
      canvas.rotate(index * math.pi / 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: const Offset(0, -6.6),
            width: 3.1,
            height: 4.2,
          ),
          const Radius.circular(0.6),
        ),
        paint,
      );
      canvas.restore();
    }

    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: 5.8))
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: 2.25));
    canvas.drawPath(ring, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GearPainter oldDelegate) => oldDelegate.color != color;
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.date,
    required this.completed,
    required this.total,
  });

  final DateTime date;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final progress = total == 0 ? 0.0 : completed / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Text(
                '今天',
                style: TextStyle(
                  color: _ink,
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                ),
              ),
            ),
            Text(
              '$completed / $total 完成',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${date.year}年${date.month}月${date.day}日  ${weekdays[date.weekday - 1]}',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: progress,
          minHeight: 2,
          color: Theme.of(context).colorScheme.primary,
          backgroundColor: const Color(0x33707571),
        ),
      ],
    );
  }
}

class _AddTaskRow extends StatelessWidget {
  const _AddTaskRow({
    required this.number,
    required this.editing,
    required this.controller,
    required this.focusNode,
    required this.onStart,
    required this.onAdd,
    required this.onCancel,
  });

  final int number;
  final bool editing;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onStart;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line, width: 0.7)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$number',
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ),
          if (editing)
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): onCancel,
                },
                child: TextField(
                  key: const Key('new-task-field'),
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  style: const TextStyle(color: _ink, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '输入任务内容',
                    hintStyle: TextStyle(color: Color(0xFF929692)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            )
          else
            InkWell(
              key: const Key('add-task-button'),
              onTap: onStart,
              child: const SizedBox(
                width: 44,
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(Icons.add, size: 17, color: _muted),
                ),
              ),
            ),
          if (!editing) const Spacer(),
        ],
      ),
    );
  }
}

class _BlankTaskRow extends StatelessWidget {
  const _BlankTaskRow({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x26737873), width: 0.7),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 26,
        child: Text(
          '$number',
          style: const TextStyle(color: Color(0x66707571), fontSize: 10),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.taskCount});

  final int taskCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          '任务',
          style: TextStyle(
            color: _ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '$taskCount 项',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    );
  }
}

typedef SubtaskUpdateCallback = Future<void> Function(
  String subtaskId, {
  String? title,
  bool? isCompleted,
});

class _TaskTile extends StatefulWidget {
  const _TaskTile({
    super.key,
    required this.number,
    required this.task,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onDetailsChanged,
    required this.onAddSubtask,
    required this.onUpdateSubtask,
    required this.onRemoveSubtask,
    required this.onDelete,
  });

  final int number;
  final GoodDayTask task;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<bool?> onChanged;
  final Future<void> Function(String title, String notes) onDetailsChanged;
  final Future<void> Function(String title) onAddSubtask;
  final SubtaskUpdateCallback onUpdateSubtask;
  final Future<void> Function(String subtaskId) onRemoveSubtask;
  final VoidCallback onDelete;

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  final _titleFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _newSubtaskController = TextEditingController();
  final _newSubtaskFocus = FocusNode();
  Timer? _saveTimer;
  Timer? _savedTimer;
  bool _hovering = false;
  bool _addingSubtask = false;
  bool _saving = false;
  bool _saved = false;
  bool _titleError = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _noteController = TextEditingController(text: widget.task.notes);
  }

  @override
  void didUpdateWidget(covariant _TaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_titleFocus.hasFocus && _titleController.text != widget.task.title) {
      _titleController.text = widget.task.title;
    }
    if (!_noteFocus.hasFocus && _noteController.text != widget.task.notes) {
      _noteController.text = widget.task.notes;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savedTimer?.cancel();
    _titleController.dispose();
    _noteController.dispose();
    _newSubtaskController.dispose();
    _titleFocus.dispose();
    _noteFocus.dispose();
    _newSubtaskFocus.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    final valid = _titleController.text.trim().isNotEmpty;
    if (_titleError == valid) setState(() => _titleError = !valid);
    if (!valid) return;
    _saveTimer = Timer(const Duration(milliseconds: 650), _saveDetails);
  }

  Future<bool> _saveDetails() async {
    _saveTimer?.cancel();
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (mounted) setState(() => _titleError = true);
      return false;
    }
    final notes = _noteController.text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (title == widget.task.title && notes.trimRight() == widget.task.notes) {
      return true;
    }

    if (mounted) setState(() => _saving = true);
    try {
      await widget.onDetailsChanged(title, notes);
      if (!mounted) return true;
      _savedTimer?.cancel();
      setState(() {
        _saving = false;
        _saved = true;
        _titleError = false;
      });
      _savedTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _saved = false);
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return false;
    }
  }

  Future<void> _toggleExpanded() async {
    if (widget.expanded && !await _saveDetails()) return;
    widget.onToggleExpanded();
  }

  void _startAddingSubtask() {
    setState(() => _addingSubtask = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _newSubtaskFocus.requestFocus();
    });
  }

  void _cancelAddingSubtask() {
    _newSubtaskController.clear();
    setState(() => _addingSubtask = false);
  }

  Future<void> _submitSubtask() async {
    final title = _newSubtaskController.text.trim();
    if (title.isEmpty) return;
    try {
      await widget.onAddSubtask(title);
      if (!mounted) return;
      _newSubtaskController.clear();
      setState(() => _addingSubtask = false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法添加子任务：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hovering || widget.expanded
              ? const Color(0x1AFFFFFF)
              : Colors.transparent,
          border: const Border(bottom: BorderSide(color: _line, width: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${widget.number}',
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Transform.scale(
                      scale: 0.78,
                      child: Checkbox(
                        key: Key('task-checkbox-${task.id}'),
                        value: task.isCompleted,
                        onChanged: widget.onChanged,
                      ),
                    ),
                  ),
                  Expanded(
                    child: widget.expanded
                        ? TextField(
                            key: Key('task-title-${task.id}'),
                            controller: _titleController,
                            focusNode: _titleFocus,
                            autofocus: true,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => _scheduleSave(),
                            onSubmitted: (_) => _saveDetails(),
                            style: TextStyle(
                              color: task.isCompleted
                                  ? const Color(0xFF858A86)
                                  : _ink,
                              fontSize: 13,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: '任务内容不能为空',
                              hintStyle: TextStyle(
                                color: _titleError
                                    ? const Color(0xFF8B3A32)
                                    : _muted,
                              ),
                            ),
                          )
                        : InkWell(
                            key: Key('task-content-${task.id}'),
                            onTap: _toggleExpanded,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  task.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: task.isCompleted
                                        ? const Color(0xFF858A86)
                                        : _ink,
                                    fontSize: 13,
                                    height: 1.25,
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  IconButton(
                    key: Key('task-expand-${task.id}'),
                    onPressed: _toggleExpanded,
                    tooltip: widget.expanded ? '收起' : '编辑任务',
                    iconSize: 15,
                    color: _muted,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ),
                  if (!widget.expanded)
                    Opacity(
                      opacity: _hovering ? 1 : 0.2,
                      child: IconButton(
                        key: Key('delete-task-${task.id}'),
                        onPressed: widget.onDelete,
                        tooltip: '移到 Archive',
                        iconSize: 14,
                        color: _muted,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                ],
              ),
              if (widget.expanded) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(60, 2, 38, 7),
                  child: TextField(
                    key: Key('task-note-${task.id}'),
                    controller: _noteController,
                    focusNode: _noteFocus,
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _scheduleSave(),
                    onSubmitted: (_) => _saveDetails(),
                    style: const TextStyle(color: _muted, fontSize: 11),
                    decoration: const InputDecoration(
                      hintText: '添加一行备注',
                      hintStyle: TextStyle(color: Color(0xFF929692)),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 7),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0x26737873)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _muted),
                      ),
                    ),
                  ),
                ),
                for (final subtask in task.subtasks)
                  _EditableSubtaskRow(
                    key: ValueKey(subtask.id),
                    taskId: task.id,
                    subtask: subtask,
                    onUpdate: widget.onUpdateSubtask,
                    onRemove: widget.onRemoveSubtask,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(60, 1, 38, 6),
                  child: _addingSubtask
                      ? CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.escape):
                                _cancelAddingSubtask,
                          },
                          child: TextField(
                            key: Key('new-subtask-field-${task.id}'),
                            controller: _newSubtaskController,
                            focusNode: _newSubtaskFocus,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submitSubtask(),
                            style: const TextStyle(color: _ink, fontSize: 11),
                            decoration: const InputDecoration(
                              hintText: '输入子任务',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 6),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0x26737873),
                                ),
                              ),
                            ),
                          ),
                        )
                      : InkWell(
                          key: Key('add-subtask-${task.id}'),
                          onTap: _startAddingSubtask,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 14, color: _muted),
                                SizedBox(width: 7),
                                Text(
                                  '添加子任务',
                                  style: TextStyle(color: _muted, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                if (_saving || _saved || _titleError)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(60, 0, 38, 5),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _titleError
                            ? '任务内容不能为空'
                            : _saving
                            ? '保存中…'
                            : '已保存',
                        style: TextStyle(
                          color: _titleError ? const Color(0xFF8B3A32) : _muted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
              ] else
                for (final subtask in task.subtasks)
                  _CompactSubtaskRow(
                    taskId: task.id,
                    subtask: subtask,
                    onUpdate: widget.onUpdateSubtask,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactSubtaskRow extends StatelessWidget {
  const _CompactSubtaskRow({
    required this.taskId,
    required this.subtask,
    required this.onUpdate,
  });

  final String taskId;
  final GoodDaySubtask subtask;
  final SubtaskUpdateCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 0, 38, 3),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 22,
            child: Transform.scale(
              scale: 0.62,
              child: Checkbox(
                key: Key('subtask-checkbox-$taskId-${subtask.id}'),
                value: subtask.isCompleted,
                onChanged: (value) =>
                    onUpdate(subtask.id, isCompleted: value ?? false),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              subtask.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subtask.isCompleted ? const Color(0xFF969A96) : _muted,
                fontSize: 10,
                decoration: subtask.isCompleted
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableSubtaskRow extends StatefulWidget {
  const _EditableSubtaskRow({
    super.key,
    required this.taskId,
    required this.subtask,
    required this.onUpdate,
    required this.onRemove,
  });

  final String taskId;
  final GoodDaySubtask subtask;
  final SubtaskUpdateCallback onUpdate;
  final Future<void> Function(String subtaskId) onRemove;

  @override
  State<_EditableSubtaskRow> createState() => _EditableSubtaskRowState();
}

class _EditableSubtaskRowState extends State<_EditableSubtaskRow> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  Timer? _timer;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.subtask.title);
  }

  @override
  void didUpdateWidget(covariant _EditableSubtaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.subtask.title) {
      _controller.text = widget.subtask.title;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _timer?.cancel();
    final valid = _controller.text.trim().isNotEmpty;
    if (_error == valid) setState(() => _error = !valid);
    if (!valid) return;
    _timer = Timer(const Duration(milliseconds: 650), _save);
  }

  Future<void> _save() async {
    _timer?.cancel();
    final title = _controller.text.trim();
    if (title.isEmpty) {
      if (mounted) setState(() => _error = true);
      return;
    }
    if (title == widget.subtask.title) return;
    await widget.onUpdate(widget.subtask.id, title: title);
    if (mounted) setState(() => _error = false);
  }

  @override
  Widget build(BuildContext context) {
    final subtask = widget.subtask;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 0, 28, 1),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 28,
            child: Transform.scale(
              scale: 0.62,
              child: Checkbox(
                key: Key('subtask-checkbox-${widget.taskId}-${subtask.id}'),
                value: subtask.isCompleted,
                onChanged: (value) =>
                    widget.onUpdate(subtask.id, isCompleted: value ?? false),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: TextField(
              key: Key('subtask-title-${widget.taskId}-${subtask.id}'),
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (_) => _scheduleSave(),
              onSubmitted: (_) => _save(),
              textInputAction: TextInputAction.done,
              style: TextStyle(
                color: subtask.isCompleted ? const Color(0xFF969A96) : _ink,
                fontSize: 10,
                decoration: subtask.isCompleted
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
              decoration: InputDecoration(
                hintText: _error ? '子任务不能为空' : null,
                hintStyle: const TextStyle(
                  color: Color(0xFF8B3A32),
                  fontSize: 10,
                ),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          IconButton(
            onPressed: () => widget.onRemove(subtask.id),
            tooltip: '移除子任务',
            iconSize: 13,
            color: _muted,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

typedef VaultSelectedCallback = Future<String> Function(
  String path, {
  required bool deleteSourceAfterMigration,
});

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.initialVaultPath,
    required this.onVaultSelected,
  });

  final AppSettingsController controller;
  final String initialVaultPath;
  final VaultSelectedCallback onVaultSelected;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _vaultPath;
  bool _switchingVault = false;
  bool _deleteSourceAfterMigration = false;

  @override
  void initState() {
    super.initState();
    _vaultPath = widget.initialVaultPath;
  }

  Future<void> _chooseVault() async {
    final selectedPath = await getDirectoryPath(
      initialDirectory: _vaultPath,
      confirmButtonText: '选择此文件夹',
      canCreateDirectories: true,
    );
    if (selectedPath == null || !mounted) return;

    if (_deleteSourceAfterMigration) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('删除原位置数据？'),
          content: Text(
            '迁移成功后，Good Day 将删除原位置中的 Tasks、Daily、Archive 和设置文件。\n\n'
            '原位置：$_vaultPath\n\n新位置：$selectedPath',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('confirm-delete-source-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B3A32),
              ),
              child: const Text('迁移并删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _switchingVault = true);
    try {
      final message = await widget.onVaultSelected(
        selectedPath,
        deleteSourceAfterMigration: _deleteSourceAfterMigration,
      );
      if (!mounted) return;
      setState(() => _vaultPath = selectedPath);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法切换文件夹：$error')));
    } finally {
      if (mounted) setState(() => _switchingVault = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final settings = widget.controller.settings;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              color: const Color(0xE6F2F3F1),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Column(
              children: [
                _WindowBar(
                  title: '设置',
                  onBack: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    children: [
                      const Text(
                        '设置',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '管理数据位置和界面外观。',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                      const SizedBox(height: 28),
                      const _SettingsSectionTitle(label: '数据存放位置'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0x2BFFFFFF),
                          border: Border.all(color: _line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 18,
                                  color: settings.accent.color,
                                ),
                                const SizedBox(width: 9),
                                const Expanded(
                                  child: Text(
                                    'Good Day Vault',
                                    style: TextStyle(
                                      color: _ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Tooltip(
                              message: _vaultPath,
                              child: Text(
                                _vaultPath,
                                key: const Key('vault-path'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            const SizedBox(height: 13),
                            SizedBox(
                              height: 38,
                              child: OutlinedButton.icon(
                                key: const Key('choose-vault-button'),
                                onPressed: _switchingVault
                                    ? null
                                    : _chooseVault,
                                icon: _switchingVault
                                    ? const SizedBox.square(
                                        dimension: 13,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.4,
                                        ),
                                      )
                                    : const Icon(Icons.folder_open, size: 16),
                                label: Text(
                                  _switchingVault ? '正在切换…' : '选择文件夹',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: settings.accent.color,
                                  side: BorderSide(
                                    color: settings.accent.color,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Tasks、Daily 和 Archive 会保存在这里。选择空文件夹时会迁移现有数据，默认保留原位置。',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 10,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              key: const Key('delete-source-option'),
                              onTap: _switchingVault
                                  ? null
                                  : () => setState(
                                      () => _deleteSourceAfterMigration =
                                          !_deleteSourceAfterMigration,
                                    ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        key: const Key(
                                          'delete-source-checkbox',
                                        ),
                                        value: _deleteSourceAfterMigration,
                                        onChanged: _switchingVault
                                            ? null
                                            : (value) => setState(
                                                () =>
                                                    _deleteSourceAfterMigration =
                                                        value ?? false,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '迁移成功后删除原位置数据',
                                            style: TextStyle(
                                              color: _ink,
                                              fontSize: 11,
                                            ),
                                          ),
                                          SizedBox(height: 3),
                                          Text(
                                            '默认关闭；删除前会再次确认。已有数据的目标文件夹不会触发删除。',
                                            style: TextStyle(
                                              color: _muted,
                                              fontSize: 9,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const _SettingsSectionTitle(label: '字体'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0x2BFFFFFF),
                          border: Border.all(color: _line),
                        ),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < AppFont.values.length;
                              index++
                            ) ...[
                              _FontOption(
                                option: AppFont.values[index],
                                selected:
                                    settings.font == AppFont.values[index],
                                accent: settings.accent.color,
                                onTap: () => widget.controller.setFont(
                                  AppFont.values[index],
                                ),
                              ),
                              if (index != AppFont.values.length - 1)
                                const Divider(
                                  height: 1,
                                  thickness: 0.6,
                                  color: Color(0x33737873),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const _SettingsSectionTitle(label: '主题颜色'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0x2BFFFFFF),
                          border: Border.all(color: _line),
                        ),
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          children: [
                            for (final accent in AppAccent.values)
                              _AccentOption(
                                option: accent,
                                selected: settings.accent == accent,
                                onTap: () =>
                                    widget.controller.setAccent(accent),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),
                      const Divider(height: 1, color: _line),
                      const SizedBox(height: 16),
                      const Text(
                        '更多设置将在这里继续扩展',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _FontOption extends StatelessWidget {
  const _FontOption({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AppFont option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('font-${option.key}'),
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: _ink,
                    fontFamily: option.family,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentOption extends StatelessWidget {
  const _AccentOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppAccent option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('accent-${option.key}'),
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: option.color,
                border: Border.all(
                  color: selected ? _ink : const Color(0x33707571),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(height: 7),
            Text(
              option.label,
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultStatus extends StatelessWidget {
  const _VaultStatus({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: path,
      child: const Row(
        children: [
          Icon(Icons.check, size: 12, color: _muted),
          SizedBox(width: 6),
          Text('Markdown 已同步', style: TextStyle(color: _muted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('无法读取 Vault', style: TextStyle(color: _ink, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
