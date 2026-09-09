import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import 'data/vault_repository.dart';
import 'models/good_day_goal.dart';
import 'models/good_day_plan.dart';
import 'models/good_day_task.dart';
import 'settings/app_settings.dart';
import 'settings/vault_location_store.dart';

const _ink = Color(0xFF202421);
const _muted = Color(0xFF707571);
const _line = Color(0x4D737873);
const _windowSize = Size(400, 720);
const _goalPalette = <Color>[
  Color(0xFFF2B544),
  Color(0xFFCF7D5E),
  Color(0xFF789A7A),
  Color(0xFF66899B),
  Color(0xFF8779A6),
  Color(0xFF9A8371),
];

enum _HomeView { today, plans, goals }

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
            fontFamilyFallback: const [
              'Microsoft YaHei UI',
              'Microsoft YaHei',
              'Segoe UI',
            ],
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
  List<GoodDayPlan> _plans = [];
  List<GoodDayGoal> _goals = [];
  late VaultRepository _repository;
  _HomeView _view = _HomeView.today;
  bool _loading = true;
  bool _isAdding = false;
  String? _expandedTaskId;
  String? _expandedPlanId;
  String? _expandedGoalId;
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
      final goals = await _repository.loadGoals();
      final plans = await _repository.loadPlans();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _goals = goals;
        _plans = plans;
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

  Future<void> _assignTaskGoal(String taskId, String? goalId) async {
    final updated = await _repository.assignTaskGoal(_taskById(taskId), goalId);
    if (mounted) setState(() => _replaceTask(updated));
  }

  Future<void> _addGoal(String name, String description, int colorValue) async {
    final goal = await _repository.addGoal(
      name: name,
      description: description,
      colorValue: colorValue,
    );
    if (mounted) setState(() => _goals = [..._goals, goal]);
  }

  Future<void> _addPlan(String title, DateTime deadline, String? goalId) async {
    final plan = await _repository.addPlan(
      title: title,
      deadline: deadline,
      goalId: goalId,
    );
    if (!mounted) return;
    setState(() {
      _plans = [..._plans, plan];
      _sortPlans();
    });
  }

  Future<void> _togglePlan(GoodDayPlan plan, bool? value) async {
    final updated = await _repository.setPlanCompleted(plan, value ?? false);
    if (!mounted) return;
    setState(() {
      final index = _plans.indexWhere((item) => item.id == plan.id);
      if (index >= 0) _plans[index] = updated;
      _sortPlans();
    });
  }

  Future<void> _updatePlan(
    GoodDayPlan plan,
    String title,
    DateTime deadline,
    String? goalId,
  ) async {
    final updated = await _repository.updatePlan(
      plan,
      title: title,
      deadline: deadline,
      goalId: goalId,
      clearGoal: goalId == null,
    );
    if (!mounted) return;
    setState(() {
      final index = _plans.indexWhere((item) => item.id == plan.id);
      if (index >= 0) _plans[index] = updated;
      _sortPlans();
    });
  }

  Future<void> _deletePlan(GoodDayPlan plan) async {
    if (!await _confirmDelete('计划“${plan.title}”')) return;
    await _repository.deletePlan(plan);
    if (!mounted) return;
    setState(() {
      _plans.removeWhere((item) => item.id == plan.id);
      if (_expandedPlanId == plan.id) _expandedPlanId = null;
    });
    _showMovedToTrash('计划');
  }

  Future<void> _updateGoal(
    GoodDayGoal goal,
    String name,
    String description,
    int colorValue,
  ) async {
    final updated = await _repository.updateGoal(
      goal,
      name: name,
      description: description,
      colorValue: colorValue,
    );
    if (!mounted) return;
    setState(() {
      final index = _goals.indexWhere((item) => item.id == goal.id);
      if (index >= 0) _goals[index] = updated;
    });
  }

  Future<void> _deleteGoal(GoodDayGoal goal) async {
    if (!await _confirmDelete('目标“${goal.name}”')) return;
    await _repository.deleteGoal(goal);
    if (!mounted) return;
    setState(() {
      _goals.removeWhere((item) => item.id == goal.id);
      if (_expandedGoalId == goal.id) _expandedGoalId = null;
    });
    _showMovedToTrash('目标');
  }

  Future<bool> _confirmDelete(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('确认删除？'),
        content: Text('$label 将移到垃圾桶。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-delete-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B3A32),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _showMovedToTrash(String type) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$type已移到垃圾桶')));
  }

  Future<List<TrashItem>> _loadTrash() => _repository.loadTrash();

  Future<void> _restoreTrashItem(TrashItem item) async {
    await _repository.restoreTrashItem(item);
    await _load();
  }

  Future<void> _emptyTrash() => _repository.emptyTrash();

  void _sortPlans() {
    _plans.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return a.deadline.compareTo(b.deadline);
    });
  }

  void _cycleView() {
    setState(() {
      _view = _HomeView.values[(_view.index + 1) % _HomeView.values.length];
      _expandedTaskId = null;
      _expandedPlanId = null;
      _expandedGoalId = null;
      _controller.clear();
      _isAdding = false;
    });
  }

  Future<void> _deleteTask(GoodDayTask task) async {
    if (!await _confirmDelete('任务“${task.title}”')) return;
    await _repository.deleteTask(task);
    if (!mounted) return;
    setState(() {
      _tasks.removeWhere((item) => item.id == task.id);
      if (_expandedTaskId == task.id) _expandedTaskId = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('任务已移到垃圾桶')));
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
    final task = _taskById(taskId);
    final subtask = task.subtasks.firstWhere((item) => item.id == subtaskId);
    if (!await _confirmDelete('子任务“${subtask.title}”')) return;
    final updated = await _repository.removeSubtask(task, subtaskId);
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
    final goals = await nextRepository.loadGoals();
    final plans = await nextRepository.loadPlans();
    await widget.settingsController.useVault(targetDirectory);
    await widget.vaultLocationStore?.save(targetDirectory);

    if (mounted) {
      setState(() {
        _repository = nextRepository;
        _tasks = tasks;
        _goals = goals;
        _plans = plans;
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
          onLoadTrash: _loadTrash,
          onRestoreTrashItem: _restoreTrashItem,
          onEmptyTrash: _emptyTrash,
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
                    _ModeHeader(
                      mode: _view,
                      date: DateTime.now(),
                      completed: completed,
                      total: _tasks.length,
                      planCount: _plans.length,
                      goalCount: _goals.length,
                      onTap: _cycleView,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(
                      label: switch (_view) {
                        _HomeView.today => '任务',
                        _HomeView.plans => '计划',
                        _HomeView.goals => '目标',
                      },
                      itemCount: switch (_view) {
                        _HomeView.today => _tasks.length,
                        _HomeView.plans => _plans.length,
                        _HomeView.goals => _goals.length,
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _buildCurrentArea()),
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

  Widget _buildCurrentArea() {
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: _ink),
        ),
      );
    }
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    return switch (_view) {
      _HomeView.today => _buildTaskArea(),
      _HomeView.plans => _buildPlanArea(),
      _HomeView.goals => _buildGoalArea(),
    };
  }

  Widget _buildTaskArea() {
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
              goals: _goals,
              expanded: _expandedTaskId == task.id,
              onToggleExpanded: () => setState(() {
                _expandedTaskId = _expandedTaskId == task.id ? null : task.id;
              }),
              onChanged: (value) => _toggleTask(task, value),
              onDetailsChanged: (title, notes) =>
                  _updateTaskDetails(task.id, title, notes),
              onGoalChanged: (goalId) => _assignTaskGoal(task.id, goalId),
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

  Widget _buildPlanArea() {
    return Scrollbar(
      thickness: 2,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _plans.length + 4,
        itemBuilder: (context, index) {
          if (index < _plans.length) {
            final plan = _plans[index];
            return _PlanTile(
              key: ValueKey(plan.id),
              number: index + 1,
              plan: plan,
              goal: _goalById(plan.goalId),
              goals: _goals,
              expanded: _expandedPlanId == plan.id,
              onToggleExpanded: () => setState(() {
                _expandedPlanId = _expandedPlanId == plan.id ? null : plan.id;
              }),
              onChanged: (value) => _togglePlan(plan, value),
              onDetailsChanged: (title, deadline, goalId) =>
                  _updatePlan(plan, title, deadline, goalId),
              onDelete: () => _deletePlan(plan),
            );
          }
          if (index == _plans.length) {
            return _PlanComposer(
              number: index + 1,
              goals: _goals,
              onCreate: _addPlan,
            );
          }
          return _BlankTaskRow(number: index + 1);
        },
      ),
    );
  }

  Widget _buildGoalArea() {
    return Scrollbar(
      thickness: 2,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _goals.length + 4,
        itemBuilder: (context, index) {
          if (index < _goals.length) {
            final goal = _goals[index];
            return _GoalTile(
              key: ValueKey(goal.id),
              number: index + 1,
              goal: goal,
              expanded: _expandedGoalId == goal.id,
              onToggleExpanded: () => setState(() {
                _expandedGoalId = _expandedGoalId == goal.id ? null : goal.id;
              }),
              onDetailsChanged: (name, description, colorValue) =>
                  _updateGoal(goal, name, description, colorValue),
              onDelete: () => _deleteGoal(goal),
            );
          }
          if (index == _goals.length) {
            return _GoalComposer(number: index + 1, onCreate: _addGoal);
          }
          return _BlankTaskRow(number: index + 1);
        },
      ),
    );
  }

  GoodDayGoal? _goalById(String? goalId) {
    if (goalId == null) return null;
    for (final goal in _goals) {
      if (goal.id == goalId) return goal;
    }
    return null;
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

class _ModeHeader extends StatelessWidget {
  const _ModeHeader({
    required this.mode,
    required this.date,
    required this.completed,
    required this.total,
    required this.planCount,
    required this.goalCount,
    required this.onTap,
  });

  final _HomeView mode;
  final DateTime date;
  final int completed;
  final int total;
  final int planCount;
  final int goalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final progress = total == 0 ? 0.0 : completed / total;
    final title = switch (mode) {
      _HomeView.today => '今天',
      _HomeView.plans => '计划',
      _HomeView.goals => '目标',
    };
    final count = switch (mode) {
      _HomeView.today => '$completed / $total 完成',
      _HomeView.plans => '$planCount 项',
      _HomeView.goals => '$goalCount 个',
    };
    final subtitle = switch (mode) {
      _HomeView.today =>
        '${date.year}年${date.month}月${date.day}日  ${weekdays[date.weekday - 1]}',
      _HomeView.plans => '每一项计划都有明确的截止时间',
      _HomeView.goals => '用名称、描述和颜色标记长期方向',
    };
    return InkWell(
      key: const Key('home-mode-switch'),
      onTap: onTap,
      hoverColor: const Color(0x0A000000),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(
                          Icons.chevron_right,
                          size: 17,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  count,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 16),
            if (mode == _HomeView.today)
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: const Color(0x33707571),
              )
            else
              const Divider(height: 2, thickness: 0.7, color: _line),
          ],
        ),
      ),
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
      child: editing
          ? Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '$number',
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          onCancel,
                    },
                    child: TextField(
                      key: const Key('new-task-field'),
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onAdd(),
                      onTapOutside: (_) {
                        if (controller.text.trim().isEmpty) {
                          onCancel();
                        } else {
                          onAdd();
                        }
                      },
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
                ),
              ],
            )
          : InkWell(
              key: const Key('add-task-button'),
              onTap: onStart,
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '$number',
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ),
                  const SizedBox(
                    width: 44,
                    height: 48,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(Icons.add, size: 17, color: _muted),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
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
  const _SectionLabel({required this.label, required this.itemCount});

  final String label;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '$itemCount 项',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _GoalBadge extends StatelessWidget {
  const _GoalBadge({required this.goal});

  final GoodDayGoal goal;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 82),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, color: Color(goal.colorValue)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              goal.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalPickerRow extends StatelessWidget {
  const _GoalPickerRow({
    super.key,
    required this.goals,
    required this.selectedGoalId,
    required this.onChanged,
  });

  final List<GoodDayGoal> goals;
  final String? selectedGoalId;
  final Future<void> Function(String? goalId) onChanged;

  @override
  Widget build(BuildContext context) {
    GoodDayGoal? selected;
    for (final goal in goals) {
      if (goal.id == selectedGoalId) selected = goal;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(60, 0, 38, 3),
      child: PopupMenuButton<String>(
        tooltip: '选择目标',
        onSelected: (value) => onChanged(value.isEmpty ? null : value),
        color: const Color(0xFFF1F2F0),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            value: '',
            child: Text('无目标', style: TextStyle(fontSize: 11)),
          ),
          for (final goal in goals)
            PopupMenuItem<String>(
              key: Key('goal-menu-${goal.id}'),
              value: goal.id,
              child: Row(
                children: [
                  Container(width: 8, height: 8, color: Color(goal.colorValue)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      goal.name,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              const Text('所属目标', style: TextStyle(color: _muted, fontSize: 10)),
              const Spacer(),
              if (selected == null)
                const Text('无', style: TextStyle(color: _muted, fontSize: 10))
              else
                _GoalBadge(goal: selected),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right, size: 13, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalTile extends StatefulWidget {
  const _GoalTile({
    super.key,
    required this.number,
    required this.goal,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onDetailsChanged,
    required this.onDelete,
  });

  final int number;
  final GoodDayGoal goal;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Future<void> Function(String name, String description, int colorValue)
  onDetailsChanged;
  final VoidCallback onDelete;

  @override
  State<_GoalTile> createState() => _GoalTileState();
}

class _GoalTileState extends State<_GoalTile> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final _nameFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  Timer? _saveTimer;
  late int _colorValue;
  bool _saving = false;
  bool _saved = false;
  bool _nameError = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.goal.name);
    _descriptionController = TextEditingController(
      text: widget.goal.description,
    );
    _colorValue = widget.goal.colorValue;
  }

  @override
  void didUpdateWidget(covariant _GoalTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_nameFocus.hasFocus && _nameController.text != widget.goal.name) {
      _nameController.text = widget.goal.name;
    }
    if (!_descriptionFocus.hasFocus &&
        _descriptionController.text != widget.goal.description) {
      _descriptionController.text = widget.goal.description;
    }
    if (!widget.expanded) _colorValue = widget.goal.colorValue;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    final valid = _nameController.text.trim().isNotEmpty;
    if (_nameError == valid) setState(() => _nameError = !valid);
    if (valid) {
      _saveTimer = Timer(const Duration(milliseconds: 650), _saveDetails);
    }
  }

  Future<bool> _saveDetails() async {
    _saveTimer?.cancel();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (mounted) setState(() => _nameError = true);
      return false;
    }
    final description = _descriptionController.text.trim();
    if (name == widget.goal.name &&
        description == widget.goal.description &&
        _colorValue == widget.goal.colorValue) {
      return true;
    }
    setState(() => _saving = true);
    try {
      await widget.onDetailsChanged(name, description, _colorValue);
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _saved = true;
        _nameError = false;
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
    if (mounted) widget.onToggleExpanded();
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    return TapRegion(
      onTapOutside: widget.expanded ? (_) => _toggleExpanded() : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: widget.expanded ? const Color(0x1AFFFFFF) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: _line, width: 0.7)),
        ),
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
                Container(
                  width: 9,
                  height: 9,
                  color: Color(widget.expanded ? _colorValue : goal.colorValue),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: widget.expanded
                      ? TextField(
                          key: Key('edit-goal-name-${goal.id}'),
                          controller: _nameController,
                          focusNode: _nameFocus,
                          autofocus: true,
                          onChanged: (_) => _scheduleSave(),
                          onSubmitted: (_) => _saveDetails(),
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: '目标名称不能为空',
                            hintStyle: TextStyle(
                              color: _nameError
                                  ? const Color(0xFF8B3A32)
                                  : _muted,
                            ),
                          ),
                        )
                      : InkWell(
                          key: Key('edit-goal-${goal.id}'),
                          onTap: _toggleExpanded,
                          child: SizedBox(
                            width: double.infinity,
                            child: Text(
                              goal.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                ),
                IconButton(
                  key: Key('goal-expand-${goal.id}'),
                  onPressed: _toggleExpanded,
                  tooltip: widget.expanded ? '收起' : '编辑目标',
                  iconSize: 15,
                  color: _muted,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ),
                IconButton(
                  key: Key('delete-goal-${goal.id}'),
                  onPressed: widget.onDelete,
                  tooltip: '删除目标',
                  iconSize: 14,
                  color: _muted,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (widget.expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(46, 2, 38, 7),
                child: TextField(
                  key: Key('edit-goal-description-${goal.id}'),
                  controller: _descriptionController,
                  focusNode: _descriptionFocus,
                  maxLines: 1,
                  onChanged: (_) => _scheduleSave(),
                  onSubmitted: (_) => _saveDetails(),
                  style: const TextStyle(color: _muted, fontSize: 10),
                  decoration: const InputDecoration(
                    hintText: '简短描述（可选）',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 7),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(46, 1, 38, 4),
                child: Row(
                  children: [
                    for (
                      var index = 0;
                      index < _goalPalette.length;
                      index++
                    ) ...[
                      InkWell(
                        key: Key('edit-goal-color-${goal.id}-$index'),
                        onTap: () {
                          setState(() {
                            _colorValue = _goalPalette[index].toARGB32();
                          });
                          _scheduleSave();
                        },
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _goalPalette[index],
                            border: Border.all(
                              color:
                                  _colorValue == _goalPalette[index].toARGB32()
                                  ? _ink
                                  : Colors.transparent,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                      if (index != _goalPalette.length - 1)
                        const SizedBox(width: 9),
                    ],
                    const Spacer(),
                    if (_saving || _saved || _nameError)
                      Text(
                        _nameError
                            ? '名称不能为空'
                            : _saving
                            ? '保存中…'
                            : '已保存',
                        style: TextStyle(
                          color: _nameError ? const Color(0xFF8B3A32) : _muted,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
            ] else if (goal.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(46, 0, 38, 3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    goal.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoalComposer extends StatefulWidget {
  const _GoalComposer({required this.number, required this.onCreate});

  final int number;
  final Future<void> Function(String name, String description, int colorValue)
  onCreate;

  @override
  State<_GoalComposer> createState() => _GoalComposerState();
}

class _GoalComposerState extends State<_GoalComposer> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _focusNode = FocusNode();
  bool _editing = false;
  bool _saving = false;
  int _colorValue = _goalPalette.first.toARGB32();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _cancel() {
    _nameController.clear();
    _descriptionController.clear();
    setState(() {
      _editing = false;
      _colorValue = _goalPalette.first.toARGB32();
    });
  }

  Future<void> _finish() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _cancel();
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onCreate(
        name,
        _descriptionController.text.trim(),
        _colorValue,
      );
      if (mounted) _cancel();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return _FullWidthAddRow(
        key: const Key('add-goal-button'),
        number: widget.number,
        onTap: _start,
      );
    }
    return TapRegion(
      onTapOutside: (_) => _finish(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line, width: 0.7)),
        ),
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
                Expanded(
                  child: TextField(
                    key: const Key('new-goal-name'),
                    controller: _nameController,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: _ink, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '目标名称',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 4, 0, 5),
              child: TextField(
                key: const Key('new-goal-description'),
                controller: _descriptionController,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _finish(),
                style: const TextStyle(color: _muted, fontSize: 10),
                decoration: const InputDecoration(
                  hintText: '简短描述（可选）',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Row(
                children: [
                  for (var index = 0; index < _goalPalette.length; index++) ...[
                    InkWell(
                      key: Key('goal-color-$index'),
                      onTap: () => setState(
                        () => _colorValue = _goalPalette[index].toARGB32(),
                      ),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _goalPalette[index],
                          border: Border.all(
                            color: _colorValue == _goalPalette[index].toARGB32()
                                ? _ink
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (index != _goalPalette.length - 1)
                      const SizedBox(width: 9),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatefulWidget {
  const _PlanTile({
    super.key,
    required this.number,
    required this.plan,
    required this.goal,
    required this.goals,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onDetailsChanged,
    required this.onDelete,
  });

  final int number;
  final GoodDayPlan plan;
  final GoodDayGoal? goal;
  final List<GoodDayGoal> goals;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<bool?> onChanged;
  final Future<void> Function(String title, DateTime deadline, String? goalId)
  onDetailsChanged;
  final VoidCallback onDelete;

  @override
  State<_PlanTile> createState() => _PlanTileState();
}

class _PlanTileState extends State<_PlanTile> {
  late final TextEditingController _titleController;
  final _titleFocus = FocusNode();
  Timer? _saveTimer;
  late DateTime _deadline;
  String? _goalId;
  bool _choosingDate = false;
  bool _saving = false;
  bool _saved = false;
  bool _titleError = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.plan.title);
    _deadline = widget.plan.deadline;
    _goalId = widget.plan.goalId;
  }

  @override
  void didUpdateWidget(covariant _PlanTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_titleFocus.hasFocus && _titleController.text != widget.plan.title) {
      _titleController.text = widget.plan.title;
    }
    if (!widget.expanded) {
      _deadline = widget.plan.deadline;
      _goalId = widget.plan.goalId;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    final valid = _titleController.text.trim().isNotEmpty;
    if (_titleError == valid) setState(() => _titleError = !valid);
    if (valid) {
      _saveTimer = Timer(const Duration(milliseconds: 650), _saveDetails);
    }
  }

  Future<bool> _saveDetails() async {
    _saveTimer?.cancel();
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (mounted) setState(() => _titleError = true);
      return false;
    }
    if (title == widget.plan.title &&
        _deadline == widget.plan.deadline &&
        _goalId == widget.plan.goalId) {
      return true;
    }
    setState(() => _saving = true);
    try {
      await widget.onDetailsChanged(title, _deadline, _goalId);
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _saved = true;
        _titleError = false;
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
    if (mounted) widget.onToggleExpanded();
  }

  void _setDeadline(int daysFromNow) {
    final now = DateTime.now();
    setState(() {
      _deadline = DateTime(now.year, now.month, now.day + daysFromNow);
    });
    _scheduleSave();
  }

  Future<void> _chooseDeadline() async {
    setState(() => _choosingDate = true);
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _deadline.isBefore(now) ? now : _deadline,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: '修改计划截止日期',
    );
    if (!mounted) return;
    setState(() {
      _choosingDate = false;
      if (selected != null) _deadline = selected;
    });
    if (selected != null) _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    GoodDayGoal? selectedGoal;
    for (final goal in widget.goals) {
      if (goal.id == _goalId) selectedGoal = goal;
    }
    final now = DateTime.now();
    final days = plan.remainingDays(now);
    final fraction = plan.remainingFraction(now);
    final percent = (fraction * 100).round();
    final timing = days < 0
        ? '已超期 ${days.abs()} 天'
        : days == 0
        ? '今天截止'
        : '剩余 $days 天';
    final accent = selectedGoal == null
        ? Theme.of(context).colorScheme.primary
        : Color(selectedGoal.colorValue);
    return TapRegion(
      onTapOutside: widget.expanded && !_choosingDate
          ? (_) => _toggleExpanded()
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: widget.expanded ? const Color(0x1AFFFFFF) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: _line, width: 0.7)),
        ),
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
                      key: Key('plan-checkbox-${plan.id}'),
                      value: plan.isCompleted,
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
                Expanded(
                  child: widget.expanded
                      ? TextField(
                          key: Key('edit-plan-title-${plan.id}'),
                          controller: _titleController,
                          focusNode: _titleFocus,
                          autofocus: true,
                          onChanged: (_) => _scheduleSave(),
                          onSubmitted: (_) => _saveDetails(),
                          style: TextStyle(
                            color: plan.isCompleted
                                ? const Color(0xFF858A86)
                                : _ink,
                            fontSize: 13,
                            decoration: plan.isCompleted
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: '计划名称不能为空',
                            hintStyle: TextStyle(
                              color: _titleError
                                  ? const Color(0xFF8B3A32)
                                  : _muted,
                            ),
                          ),
                        )
                      : InkWell(
                          key: Key('edit-plan-${plan.id}'),
                          onTap: _toggleExpanded,
                          child: SizedBox(
                            width: double.infinity,
                            child: Text(
                              plan.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: plan.isCompleted
                                    ? const Color(0xFF858A86)
                                    : _ink,
                                fontSize: 13,
                                decoration: plan.isCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                ),
                if (!widget.expanded && widget.goal != null)
                  _GoalBadge(goal: widget.goal!),
                IconButton(
                  key: Key('plan-expand-${plan.id}'),
                  onPressed: _toggleExpanded,
                  tooltip: widget.expanded ? '收起' : '编辑计划',
                  iconSize: 15,
                  color: _muted,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ),
                IconButton(
                  key: Key('delete-plan-${plan.id}'),
                  onPressed: widget.onDelete,
                  tooltip: '删除计划',
                  iconSize: 14,
                  color: _muted,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (widget.expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(60, 3, 38, 3),
                child: Row(
                  children: [
                    Text(
                      '${_deadline.year}.${_deadline.month}.${_deadline.day}',
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                    const Spacer(),
                    _ComposerChoice(label: '明天', onTap: () => _setDeadline(1)),
                    _ComposerChoice(label: '7天后', onTap: () => _setDeadline(7)),
                    _ComposerChoice(
                      key: Key('edit-plan-deadline-${plan.id}'),
                      label: '选择…',
                      onTap: _chooseDeadline,
                    ),
                  ],
                ),
              ),
              if (widget.goals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(60, 5, 38, 3),
                  child: Row(
                    children: [
                      const Text(
                        '所属目标',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        key: Key('edit-plan-no-goal-${plan.id}'),
                        onTap: () {
                          setState(() => _goalId = null);
                          _scheduleSave();
                        },
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _goalId == null ? _ink : _line,
                            ),
                          ),
                        ),
                      ),
                      for (final goal in widget.goals) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: goal.name,
                          child: InkWell(
                            key: Key('edit-plan-goal-${plan.id}-${goal.id}'),
                            onTap: () {
                              setState(() => _goalId = goal.id);
                              _scheduleSave();
                            },
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(goal.colorValue),
                                border: Border.all(
                                  color: _goalId == goal.id
                                      ? _ink
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (_saving || _saved || _titleError)
                        Text(
                          _titleError
                              ? '名称不能为空'
                              : _saving
                              ? '保存中…'
                              : '已保存',
                          style: TextStyle(
                            color: _titleError
                                ? const Color(0xFF8B3A32)
                                : _muted,
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(60, 1, 0, 0),
              child: Row(
                children: [
                  Text(
                    plan.isCompleted
                        ? '已完成'
                        : '截止 ${plan.deadline.month}月${plan.deadline.day}日 · $timing',
                    style: const TextStyle(color: _muted, fontSize: 9),
                  ),
                  const Spacer(),
                  if (!plan.isCompleted)
                    Text(
                      '$percent%',
                      style: const TextStyle(color: _muted, fontSize: 9),
                    ),
                ],
              ),
            ),
            if (!plan.isCompleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(60, 5, 0, 1),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 2,
                  color: accent,
                  backgroundColor: const Color(0x28707571),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanComposer extends StatefulWidget {
  const _PlanComposer({
    required this.number,
    required this.goals,
    required this.onCreate,
  });

  final int number;
  final List<GoodDayGoal> goals;
  final Future<void> Function(String title, DateTime deadline, String? goalId)
  onCreate;

  @override
  State<_PlanComposer> createState() => _PlanComposerState();
}

class _PlanComposerState extends State<_PlanComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _editing = false;
  bool _saving = false;
  bool _choosingDate = false;
  bool _needsDeadline = false;
  DateTime? _deadline;
  String? _goalId;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _cancel() {
    _controller.clear();
    setState(() {
      _editing = false;
      _deadline = null;
      _goalId = null;
      _needsDeadline = false;
    });
  }

  Future<void> _finish() async {
    if (_saving || _choosingDate) return;
    final title = _controller.text.trim();
    if (title.isEmpty && _deadline == null) {
      _cancel();
      return;
    }
    if (title.isEmpty || _deadline == null) {
      setState(() => _needsDeadline = _deadline == null);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onCreate(title, _deadline!, _goalId);
      if (mounted) _cancel();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setDeadline(int daysFromNow) {
    final now = DateTime.now();
    setState(() {
      _deadline = DateTime(now.year, now.month, now.day + daysFromNow);
      _needsDeadline = false;
    });
  }

  Future<void> _chooseDeadline() async {
    setState(() => _choosingDate = true);
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: '选择计划截止日期',
    );
    if (!mounted) return;
    setState(() {
      _choosingDate = false;
      if (selected != null) {
        _deadline = selected;
        _needsDeadline = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return _FullWidthAddRow(
        key: const Key('add-plan-button'),
        number: widget.number,
        onTap: _start,
      );
    }
    return TapRegion(
      onTapOutside: (_) => _finish(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line, width: 0.7)),
        ),
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
                Expanded(
                  child: TextField(
                    key: const Key('new-plan-title'),
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(color: _ink, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '计划名称',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 6, 0, 3),
              child: Row(
                children: [
                  Text(
                    _deadline == null
                        ? (_needsDeadline ? '请选择截止日期' : '截止日期')
                        : '${_deadline!.year}.${_deadline!.month}.${_deadline!.day}',
                    style: TextStyle(
                      color: _needsDeadline ? const Color(0xFF8B3A32) : _muted,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  _ComposerChoice(
                    key: const Key('plan-deadline-tomorrow'),
                    label: '明天',
                    onTap: () => _setDeadline(1),
                  ),
                  _ComposerChoice(
                    key: const Key('plan-deadline-week'),
                    label: '7天后',
                    onTap: () => _setDeadline(7),
                  ),
                  _ComposerChoice(label: '选择…', onTap: _chooseDeadline),
                ],
              ),
            ),
            if (widget.goals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 5, 0, 1),
                child: Row(
                  children: [
                    const Text(
                      '所属目标',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () => setState(() => _goalId = null),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _goalId == null ? _ink : _line,
                          ),
                        ),
                      ),
                    ),
                    for (final goal in widget.goals) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: goal.name,
                        child: InkWell(
                          key: Key('plan-goal-${goal.id}'),
                          onTap: () => setState(() => _goalId = goal.id),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Color(goal.colorValue),
                              border: Border.all(
                                color: _goalId == goal.id
                                    ? _ink
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComposerChoice extends StatelessWidget {
  const _ComposerChoice({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(label, style: const TextStyle(color: _muted, fontSize: 9)),
      ),
    );
  }
}

class _FullWidthAddRow extends StatelessWidget {
  const _FullWidthAddRow({
    super.key,
    required this.number,
    required this.onTap,
  });

  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line, width: 0.7)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$number',
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ),
            const Icon(Icons.add, size: 17, color: _muted),
          ],
        ),
      ),
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
    required this.goals,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onDetailsChanged,
    required this.onGoalChanged,
    required this.onAddSubtask,
    required this.onUpdateSubtask,
    required this.onRemoveSubtask,
    required this.onDelete,
  });

  final int number;
  final GoodDayTask task;
  final List<GoodDayGoal> goals;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<bool?> onChanged;
  final Future<void> Function(String title, String notes) onDetailsChanged;
  final Future<void> Function(String? goalId) onGoalChanged;
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
    if (!mounted) return;
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
    GoodDayGoal? selectedGoal;
    for (final goal in widget.goals) {
      if (goal.id == task.goalId) selectedGoal = goal;
    }
    return TapRegion(
      onTapOutside: widget.expanded ? (_) => _toggleExpanded() : null,
      child: MouseRegion(
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
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
                    if (!widget.expanded && selectedGoal != null)
                      _GoalBadge(goal: selectedGoal),
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
                          tooltip: '移到垃圾桶',
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
                  _GoalPickerRow(
                    key: Key('task-goal-${task.id}'),
                    goals: widget.goals,
                    selectedGoalId: task.goalId,
                    onChanged: widget.onGoalChanged,
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
                              onTapOutside: (_) {
                                if (_newSubtaskController.text.trim().isEmpty) {
                                  _cancelAddingSubtask();
                                } else {
                                  _submitSubtask();
                                }
                              },
                              style: const TextStyle(color: _ink, fontSize: 11),
                              decoration: const InputDecoration(
                                hintText: '输入子任务',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
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
                            child: const SizedBox(
                              width: double.infinity,
                              height: 30,
                              child: Row(
                                children: [
                                  Icon(Icons.add, size: 14, color: _muted),
                                  SizedBox(width: 7),
                                  Text(
                                    '添加子任务',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 10,
                                    ),
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
                            color: _titleError
                                ? const Color(0xFF8B3A32)
                                : _muted,
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
              onTapOutside: (_) => _save(),
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
typedef LoadTrashCallback = Future<List<TrashItem>> Function();
typedef RestoreTrashItemCallback = Future<void> Function(TrashItem item);
typedef EmptyTrashCallback = Future<void> Function();

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.initialVaultPath,
    required this.onVaultSelected,
    required this.onLoadTrash,
    required this.onRestoreTrashItem,
    required this.onEmptyTrash,
  });

  final AppSettingsController controller;
  final String initialVaultPath;
  final VaultSelectedCallback onVaultSelected;
  final LoadTrashCallback onLoadTrash;
  final RestoreTrashItemCallback onRestoreTrashItem;
  final EmptyTrashCallback onEmptyTrash;

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

  void _openTrash() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrashPage(
          onLoad: widget.onLoadTrash,
          onRestore: widget.onRestoreTrashItem,
          onEmpty: widget.onEmptyTrash,
        ),
      ),
    );
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
                              'Tasks、Plans、Goals、Daily 和 Archive 会保存在这里。选择空文件夹时会迁移现有数据，默认保留原位置。',
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
                      const _SettingsSectionTitle(label: '数据管理'),
                      const SizedBox(height: 8),
                      InkWell(
                        key: const Key('trash-button'),
                        onTap: _openTrash,
                        child: Container(
                          height: 58,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0x2BFFFFFF),
                            border: Border.all(color: _line),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 19,
                                color: settings.accent.color,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '垃圾桶',
                                      style: TextStyle(
                                        color: _ink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      '查看、恢复或永久清空已删除内容',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 17,
                                color: _muted,
                              ),
                            ],
                          ),
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

class TrashPage extends StatefulWidget {
  const TrashPage({
    super.key,
    required this.onLoad,
    required this.onRestore,
    required this.onEmpty,
  });

  final LoadTrashCallback onLoad;
  final RestoreTrashItemCallback onRestore;
  final EmptyTrashCallback onEmpty;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashItem> _items = [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.onLoad();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('无法读取垃圾桶：$error');
    }
  }

  Future<void> _restore(TrashItem item) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.onRestore(item);
      if (!mounted) return;
      setState(
        () => _items.removeWhere(
          (candidate) => candidate.type == item.type && candidate.id == item.id,
        ),
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${_typeLabel(item.type)}已恢复')));
    } catch (error) {
      if (mounted) _showError('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmEmpty() async {
    if (_items.isEmpty || _working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('清空垃圾桶？'),
        content: const Text('这里的内容将被永久删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-empty-trash'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B3A32),
            ),
            child: const Text('永久清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.onEmpty();
      if (!mounted) return;
      setState(() => _items = []);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('垃圾桶已清空')));
    } catch (error) {
      if (mounted) _showError('清空失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _typeLabel(TrashItemType type) => switch (type) {
    TrashItemType.task => '任务',
    TrashItemType.plan => '计划',
    TrashItemType.goal => '目标',
  };

  IconData _typeIcon(TrashItemType type) => switch (type) {
    TrashItemType.task => Icons.check_box_outlined,
    TrashItemType.plan => Icons.calendar_today_outlined,
    TrashItemType.goal => Icons.flag_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xE6F2F3F1),
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Column(
          children: [
            _WindowBar(title: '垃圾桶', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '已删除内容',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '删除后仍可在这里恢复。',
                                style: TextStyle(color: _muted, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('empty-trash-button'),
                          onPressed: _items.isEmpty || _working
                              ? null
                              : _confirmEmpty,
                          icon: const Icon(
                            Icons.delete_forever_outlined,
                            size: 16,
                          ),
                          label: const Text('清空'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF8B3A32),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          : _items.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 30,
                                    color: Color(0x66707571),
                                  ),
                                  SizedBox(height: 9),
                                  Text(
                                    '垃圾桶是空的',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, color: _line),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final date = item.deletedAt.toLocal();
                                return SizedBox(
                                  key: Key(
                                    'trash-${item.type.name}-${item.id}',
                                  ),
                                  height: 62,
                                  child: Row(
                                    children: [
                                      Icon(
                                        _typeIcon(item.type),
                                        size: 17,
                                        color: _muted,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: _ink,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${_typeLabel(item.type)} · '
                                              '${date.month}月${date.day}日删除',
                                              style: const TextStyle(
                                                color: _muted,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        key: Key(
                                          'restore-${item.type.name}-${item.id}',
                                        ),
                                        onPressed: _working
                                            ? null
                                            : () => _restore(item),
                                        child: const Text(
                                          '恢复',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
