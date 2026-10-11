import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import 'backup_page.dart';
import 'data/safe_file.dart';
import 'edit_safety.dart';
import 'events_page.dart';
import 'task_browser_page.dart';
import 'task_inline_options.dart';
import 'event_reminder_service.dart';
import 'data/vault_repository.dart';
import 'desktop_experience.dart';
import 'models/good_day_goal.dart';
import 'models/good_day_plan.dart';
import 'models/good_day_task.dart';
import 'models/good_day_event.dart';
import 'settings/app_settings.dart';
import 'settings/vault_location_store.dart';

const _ink = Color(0xFF242C27);
const _muted = Color(0xFF626C64);
const _line = Color(0xFFDEE2DA);
const _paper = Color(0xF5F5F5F0);
const _expandedPaper = Color(0xFFEDF1EB);
const _windowSize = Size(456, 720);
const _goalPalette = <Color>[
  Color(0xFFF2B544),
  Color(0xFFCF7D5E),
  Color(0xFF789A7A),
  Color(0xFF66899B),
  Color(0xFF8779A6),
  Color(0xFF9A8371),
];

enum _HomeView { today, plans, goals, history }

Future<void> main(List<String> arguments) async {
  try {
    await _startApplication(arguments);
  } catch (error) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setSize(_windowSize);
    await windowManager.show();
    runApp(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'Microsoft YaHei UI'),
        home: Scaffold(
          backgroundColor: const Color(0xFFF5F5F0),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('暂时无法打开数据', style: TextStyle(fontSize: 22)),
                  const SizedBox(height: 16),
                  SelectableText('$error'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => main(arguments),
                    child: const Text('重试'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final selected = await getDirectoryPath(
                        confirmButtonText: '使用这个数据文件夹',
                      );
                      if (selected != null) {
                        await main([
                          ...arguments.where(
                            (argument) =>
                                !argument.startsWith('--recovery-vault='),
                          ),
                          '--recovery-vault=$selected',
                        ]);
                      }
                    },
                    child: const Text('选择其他数据文件夹'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _startApplication(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  const internalReview = bool.fromEnvironment('INTERNAL_REVIEW');
  final reviewHomeArgument = arguments
      .where((argument) => argument.startsWith('--review-home='))
      .firstOrNull;
  final reviewHome = Directory(
    reviewHomeArgument?.substring('--review-home='.length) ??
        '${File(Platform.resolvedExecutable).parent.parent.path}${Platform.pathSeparator}review-data',
  );
  final vaultLocationStore = internalReview
      ? VaultLocationStore(
          Directory('${reviewHome.path}${Platform.pathSeparator}config'),
        )
      : await VaultLocationStore.create();
  final recoveryPath = arguments
      .where((argument) => argument.startsWith('--recovery-vault='))
      .firstOrNull;
  final savedVault = recoveryPath == null
      ? await vaultLocationStore.load()
      : Directory(recoveryPath.substring('--recovery-vault='.length));
  final repository = savedVault == null
      ? (internalReview
            ? VaultRepository(
                Directory('${reviewHome.path}${Platform.pathSeparator}Vault'),
              )
            : await VaultRepository.createDefault())
      : VaultRepository(savedVault);
  await repository.initialize();
  late AppSettingsController settingsController;
  try {
    await repository.acquireSession();
    await vaultLocationStore.save(repository.vaultDirectory);
    settingsController = await AppSettingsController.load(
      repository.vaultDirectory,
    );
  } catch (_) {
    await repository.releaseSession();
    rethrow;
  }

  await acrylic.Window.initialize();
  await windowManager.ensureInitialized();
  final desktopExperience = SystemDesktopExperience();
  await desktopExperience.initialize(internalReview: internalReview);
  const options = WindowOptions(
    size: _windowSize,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitle(internalReview ? 'Good Day 内部试用' : 'Good Day');
    await windowManager.setMinimumSize(const Size(396, 500));
    await windowManager.setResizable(true);
    // Hidden title bars still reserve a native resize frame around the notes.
    // Frameless keeps resizing while making the transparent gaps border-free.
    await windowManager.setAsFrameless();
    await acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.transparent,
      color: Colors.transparent,
    );
    await windowManager.setHasShadow(false);
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
      desktopExperience: desktopExperience,
    ),
  );
}

class GoodDayApp extends StatelessWidget {
  const GoodDayApp({
    super.key,
    required this.repository,
    required this.settingsController,
    this.vaultLocationStore,
    this.desktopExperience,
    this.clock,
  });

  final VaultRepository repository;
  final AppSettingsController settingsController;
  final VaultLocationStore? vaultLocationStore;
  final DesktopExperience? desktopExperience;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final settings = settingsController.settings;
        return MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
              surface: const Color(0xFFF5F5F0),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                minimumSize: const Size(32, 36),
                shape: const RoundedRectangleBorder(),
                textStyle: TextStyle(
                  fontSize: 12,
                  fontFamily: settings.font.family,
                  fontFamilyFallback: const [
                    'Microsoft YaHei UI',
                    'Microsoft YaHei',
                    'Segoe UI',
                  ],
                ),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: const RoundedRectangleBorder(),
                minimumSize: const Size(72, 36),
                textStyle: TextStyle(
                  fontSize: 12,
                  fontFamily: settings.font.family,
                  fontFamilyFallback: const [
                    'Microsoft YaHei UI',
                    'Microsoft YaHei',
                  ],
                ),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFFF5F5F0),
              surfaceTintColor: Colors.transparent,
              shape: const RoundedRectangleBorder(),
              titleTextStyle: TextStyle(
                fontFamily: settings.font.family,
                fontFamilyFallback: const [
                  'Microsoft YaHei UI',
                  'Microsoft YaHei',
                ],
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              contentTextStyle: TextStyle(
                fontFamily: settings.font.family,
                fontFamilyFallback: const [
                  'Microsoft YaHei UI',
                  'Microsoft YaHei',
                ],
                color: _muted,
                fontSize: 14,
                height: 1.6,
              ),
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
            desktopExperience: desktopExperience,
            clock: clock,
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
    this.desktopExperience,
    this.clock,
  });

  final VaultRepository repository;
  final AppSettingsController settingsController;
  final VaultLocationStore? vaultLocationStore;
  final DesktopExperience? desktopExperience;
  final DateTime Function()? clock;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _taskScrollController = ScrollController();
  List<GoodDayTask> _tasks = [];
  List<GoodDayPlan> _plans = [];
  List<GoodDayGoal> _goals = [];
  List<GoodDayEvent> _events = [];
  late final EventReminderService _reminders;
  Timer? _reminderTimer;
  bool _eventEditorOpen = false;
  bool _taskEditorOpen = false;
  bool _reminderOpen = false;
  late VaultRepository _repository;
  _HomeView _view = _HomeView.today;
  TaskPeriod _taskPeriod = TaskPeriod.day;
  bool _loading = true;
  bool _isAdding = false;
  bool _settingsOpen = false;
  String? _expandedTaskId;
  String? _expandedPlanId;
  String? _expandedGoalId;
  String? _error;
  final EditCoordinator _edits = EditCoordinator();
  final OperationQueue _actions = OperationQueue();
  final OperationQueue _navigation = OperationQueue();
  Timer? _dateTimer;
  late DateTime _displayDate;
  bool _refreshing = false;
  bool _transitioning = false;
  Future<void>? _addingTask;
  Future<bool>? _leaving;
  DateTime _now() => widget.clock?.call() ?? _repository.now;

  Future<bool> _saveBeforeLeave() {
    if (_leaving != null) return _leaving!;
    final future = _flushBeforeLeave();
    _leaving = future;
    return future.whenComplete(() => _leaving = null);
  }

  Future<bool> _flushBeforeLeave() async {
    if (_eventEditorOpen || _taskEditorOpen || _reminderOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先保存或取消当前编辑，或处理当前提醒')));
      }
      return false;
    }
    try {
      if (!await _edits.flush()) return false;
      if (_isAdding && _controller.text.trim().isNotEmpty) await _addTask();
      await _actions.idle;
      await _repository.idle;
      await widget.settingsController.idle;
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，已保留输入，请重试：$error')));
      }
      return false;
    }
  }

  void _requestRefresh() {
    unawaited(_refreshDate(force: true));
    unawaited(_reminders.check());
  }

  Future<void> _refreshDate({bool force = false}) async {
    if (!mounted ||
        _loading ||
        _refreshing ||
        _transitioning ||
        _eventEditorOpen ||
        _taskEditorOpen ||
        _reminderOpen) {
      return;
    }
    final now = _now();
    if (!force && isSameDay(now, _displayDate)) return;
    _refreshing = true;
    try {
      if (!await _saveBeforeLeave() || !mounted) return;
      await _load();
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _requestRefresh();
  }

  Future<void> _showUnreadableFiles() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('有文件无法读取'),
      content: SingleChildScrollView(
        child: SelectableText(
          '这些文件已保留，没有删除或覆盖。请检查文件内容，或在设置 → 数据备份中恢复。\n\n${_repository.unreadableFiles.join('\n')}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _displayDate = _now();
    _reminders = EventReminderService(
      repository: () => _repository,
      clock: _now,
      canPresent: () =>
          mounted &&
          !_loading &&
          !_settingsOpen &&
          !_transitioning &&
          !_eventEditorOpen &&
          !_taskEditorOpen &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      present: _presentReminder,
      onChanged: _refreshReminderState,
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('提醒暂时无法读取或保存，将自动重试：$error')));
        }
      },
    );
    _reminderTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_reminders.check()),
    );
    WidgetsBinding.instance.addObserver(this);
    widget.desktopExperience?.setSaveGuard(_saveBeforeLeave);
    widget.desktopExperience?.refreshRequests.addListener(_requestRefresh);
    _dateTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshDate()),
    );
    widget.desktopExperience?.openSettingsRequests.addListener(
      _handleOpenSettingsRequest,
    );
    _load();
  }

  @override
  void dispose() {
    widget.desktopExperience?.openSettingsRequests.removeListener(
      _handleOpenSettingsRequest,
    );
    _dateTimer?.cancel();
    _reminderTimer?.cancel();
    _reminders.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.desktopExperience?.setSaveGuard(null);
    widget.desktopExperience?.refreshRequests.removeListener(_requestRefresh);
    _taskScrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tasks = await _repository.loadTasks();
      final goals = await _repository.loadGoals();
      final plans = await _repository.loadPlans();
      final events = await _repository.loadEvents();
      if (!mounted) return;
      setState(() {
        _displayDate = _now();
        _tasks = tasks;
        _goals = goals;
        _plans = plans;
        _events = events;
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_reminders.check()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadEvents() async {
    final events = await _repository.loadEvents();
    if (mounted) setState(() => _events = events);
  }

  Future<void> _refreshReminderState() async {
    await _loadEvents();
    final tasks = await _repository.loadTaskReminders();
    if (mounted) {
      setState(() {
        _tasks = [
          for (final task in _tasks)
            tasks.where((current) => current.id == task.id).firstOrNull ?? task,
        ];
      });
    }
  }

  Future<void> _openLegacyReminders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, rebuild) {
            Future<void> refresh(Future<void> action) async {
              await action;
              if (routeContext.mounted) rebuild(() {});
            }

            return Scaffold(
              backgroundColor: _paper,
              body: Column(
                children: [
                  _WindowBar(
                    title: '已有独立提醒',
                    onBack: () => Navigator.pop(routeContext),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '这里保留旧版创建的独立提醒。新的提醒可以直接在待办中设置。',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: EventsArea(
                        events: _events,
                        now: _now(),
                        onEdit: (event) => refresh(_editEvent(event)),
                        onToggle: (event, enabled) =>
                            refresh(_toggleEvent(event, enabled)),
                        onDelete: (event) => refresh(_deleteEvent(event)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _presentReminder(
    GoodDayEvent event,
    DateTime occurrence,
    Future<void> Function(Duration? snooze) resolve,
  ) async {
    if (!mounted) return;
    _reminderOpen = true;
    var fallback = false;
    try {
      final native = await widget.desktopExperience?.showEventReminder(
        event,
        occurrence,
        _now(),
        resolve,
      );
      if (native == true || !mounted) return;
      fallback = true;
      await widget.desktopExperience?.setReminderOnTop(true);
      await widget.desktopExperience?.showWindow();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EventReminderDialog(
          event: event,
          occurrence: occurrence,
          now: _now(),
          onResolve: resolve,
        ),
      );
    } finally {
      _reminderOpen = false;
      if (fallback) await widget.desktopExperience?.setReminderOnTop(false);
    }
  }

  Future<void> _editEvent(GoodDayEvent? event) async {
    if (_eventEditorOpen || _reminderOpen) return;
    _transitioning = true;
    final saved = await _saveBeforeLeave();
    _transitioning = false;
    if (!saved || !mounted) return;
    _eventEditorOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EventEditorDialog(
          event: event,
          now: _now(),
          onSave: (draft) async {
            final saved = await _repository.saveEvent(draft);
            if (mounted) {
              setState(() {
                _events = [
                  ..._events.where((event) => event.id != saved.id),
                  saved,
                ];
              });
            }
          },
        ),
      );
    } finally {
      _eventEditorOpen = false;
      unawaited(_reminders.check());
    }
  }

  Future<void> _toggleEvent(GoodDayEvent event, bool enabled) =>
      _actions.run(() async {
        try {
          final saved = await _repository.saveEvent(
            event.edit(
              title: event.title,
              notes: event.notes,
              startsAt: event.startsAt,
              repeat: event.repeat,
              reminderMinutes: event.reminderMinutes,
              enabled: enabled,
            ),
          );
          if (mounted) {
            setState(() {
              _events = [
                ..._events.where((event) => event.id != saved.id),
                saved,
              ];
            });
          }
          unawaited(_reminders.check());
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('提醒状态未修改，请重试：$error')));
          }
        }
      });

  Future<void> _deleteEvent(GoodDayEvent event) async {
    if (!await _confirmDelete('待办事件“${event.title}”')) return;
    try {
      await _repository.deleteEvent(event);
      if (mounted) {
        setState(() => _events.removeWhere((item) => item.id == event.id));
      }
      if (mounted) _showMovedToTrash('待办事件');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('事件未删除，请重试：$error')));
      }
    }
  }

  Future<void> _addTask() {
    if (_addingTask != null) return _addingTask!;
    final future = _actions.run(_persistNewTask);
    _addingTask = future;
    return future.whenComplete(() => _addingTask = null);
  }

  Future<void> _attemptAddTask() async {
    try {
      await _addTask();
    } catch (error) {
      _showOperationFailure(error);
    }
  }

  void _showOperationFailure(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作未保存，已保留原数据或输入，请重试：$error')));
    }
  }

  Future<void> _persistNewTask() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final task = _taskPeriod == TaskPeriod.day
        ? await _repository.addTask(title)
        : await _repository.addPeriodTask(title, _taskPeriod);
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

  Future<void> _toggleTask(GoodDayTask task, bool? value) => _actions
      .run(() async {
        final updated = await _repository.setCompleted(task, value ?? false);
        if (!mounted) return;
        setState(() {
          final index = _tasks.indexWhere((item) => item.id == task.id);
          if (index >= 0) _tasks[index] = updated;
          _sortTasks();
        });
      })
      .catchError(_showOperationFailure);

  Future<void> _assignTaskGoal(String taskId, String? goalId) => _actions
      .run(() async {
        final updated = await _repository.assignTaskGoal(
          _taskById(taskId),
          goalId,
        );
        if (mounted) setState(() => _replaceTask(updated));
      })
      .catchError(_showOperationFailure);

  Future<void> _addGoal(String name, String description, int colorValue) =>
      _actions.run(() async {
        final goal = await _repository.addGoal(
          name: name,
          description: description,
          colorValue: colorValue,
        );
        if (mounted) setState(() => _goals = [..._goals, goal]);
      });

  Future<void> _addPlan(String title, DateTime deadline, String? goalId) =>
      _actions.run(() async {
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
      });

  Future<void> _togglePlan(GoodDayPlan plan, bool? value) => _actions
      .run(() async {
        final updated = await _repository.setPlanCompleted(
          plan,
          value ?? false,
        );
        if (!mounted) return;
        setState(() {
          final index = _plans.indexWhere((item) => item.id == plan.id);
          if (index >= 0) _plans[index] = updated;
          _sortPlans();
        });
      })
      .catchError(_showOperationFailure);

  Future<void> _updatePlan(
    GoodDayPlan plan,
    String title,
    DateTime deadline,
    String? goalId,
  ) => _actions.run(() async {
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
  });

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
  ) => _actions.run(() async {
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
  });

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

  Future<void> _selectView(_HomeView view) => _navigation.run(() async {
    if (_view == view) return;
    _transitioning = true;
    final saved = await _saveBeforeLeave();
    _transitioning = false;
    if (!saved || !mounted) return;
    setState(() {
      _view = view;
      _expandedTaskId = null;
      _expandedPlanId = null;
      _expandedGoalId = null;
      _controller.clear();
      _isAdding = false;
    });
    await _load();
  });

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

  Future<void> _updateTaskDetails(String taskId, String title, String notes) =>
      _actions.run(() async {
        final updated = await _repository.updateTaskDetails(
          _taskById(taskId),
          title: title,
          notes: notes,
        );
        if (mounted) setState(() => _replaceTask(updated));
      });

  Future<void> _addSubtask(String taskId, String title) =>
      _actions.run(() async {
        final updated = await _repository.addSubtask(_taskById(taskId), title);
        if (mounted) setState(() => _replaceTask(updated));
      });

  Future<void> _updateSubtask(
    String taskId,
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) => _actions.run(() async {
    final updated = await _repository.updateSubtask(
      _taskById(taskId),
      subtaskId,
      title: title,
      isCompleted: isCompleted,
    );
    if (mounted) setState(() => _replaceTask(updated));
  });

  Future<void> _removeSubtask(String taskId, String subtaskId) => _actions.run(
    () async {
      final task = _taskById(taskId);
      final subtask = task.subtasks.firstWhere((item) => item.id == subtaskId);
      if (!await _confirmDelete('子任务“${subtask.title}”')) return;
      final updated = await _repository.removeSubtask(task, subtaskId);
      if (mounted) setState(() => _replaceTask(updated));
    },
  );

  void _sortTasks() {
    _tasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _toggleEditor(_HomeView type, String id) =>
      _navigation.run(() async {
        if (_view != type) return;
        _transitioning = true;
        final saved = await _saveBeforeLeave();
        _transitioning = false;
        if (!saved || !mounted) return;
        setState(() {
          switch (type) {
            case _HomeView.today:
              _expandedTaskId = _expandedTaskId == id ? null : id;
            case _HomeView.plans:
              _expandedPlanId = _expandedPlanId == id ? null : id;
            case _HomeView.goals:
              _expandedGoalId = _expandedGoalId == id ? null : id;
            case _HomeView.history:
              break;
          }
        });
      });

  Future<String> _changeVault(
    String selectedPath, {
    required bool deleteSourceAfterMigration,
  }) async {
    if (!await _saveBeforeLeave()) throw const FileSystemException('请先保存当前编辑');
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
    await nextRepository.acquireSession();
    late bool containsExistingData;
    final previousSettingsStore = widget.settingsController.store;
    try {
      containsExistingData = await nextRepository.hasVaultData();
      if (!containsExistingData) {
        await previousRepository.copyDataTo(targetDirectory);
      }

      await nextRepository.initialize();
      final tasks = await nextRepository.loadTasks();
      final goals = await nextRepository.loadGoals();
      final plans = await nextRepository.loadPlans();
      final events = await nextRepository.loadEvents();
      await widget.settingsController.useVault(targetDirectory);
      await widget.vaultLocationStore?.save(targetDirectory);

      if (mounted) {
        setState(() {
          _repository = nextRepository;
          _displayDate = _now();
          _tasks = tasks;
          _goals = goals;
          _plans = plans;
          _events = events;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      widget.settingsController.store = previousSettingsStore;
      await nextRepository.releaseSession();
      rethrow;
    }
    await previousRepository.releaseSession();
    if (containsExistingData) return '已切换到这个 Good Day Vault，没有删除原数据';
    if (!deleteSourceAfterMigration) return '已复制数据并切换，原文件仍保留';

    try {
      await previousRepository.deleteManagedData();
      return '迁移完成，原位置中的 Good Day 数据已删除';
    } on FileSystemException catch (error) {
      return '迁移已完成，但原数据删除失败：${error.message}';
    }
  }

  void _handleOpenSettingsRequest() => _openSettings();

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;
    if (!await _saveBeforeLeave() || !mounted) {
      _settingsOpen = false;
      return;
    }
    await Navigator.of(context).push(
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
          onOpenBackups: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BackupPage(
                path: _repository.backups.directory.path,
                onList: _repository.backups.list,
                onCreate: () async {
                  await _repository.createBackup();
                },
                onRestore: (id) async {
                  await _repository.restoreBackup(id);
                  await widget.settingsController.reload();
                  await _load();
                },
              ),
            ),
          ),
          isLaunchAtStartupEnabled:
              widget.desktopExperience?.isLaunchAtStartupEnabled,
          onLaunchAtStartupChanged:
              widget.desktopExperience?.setLaunchAtStartupEnabled,
          onOpenLegacyReminders: _events.isEmpty ? null : _openLegacyReminders,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    _settingsOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final completed = _visibleTasks.where((task) => task.isCompleted).length;
    return EditScope(
      coordinator: _edits,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NoteNavigation(mode: _view, onSelect: _selectView),
            Expanded(
              child: Container(
                key: const Key('main-paper'),
                decoration: BoxDecoration(
                  color: _paper,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                  border: Border.all(color: const Color(0x66FFFFFF)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _WindowBar(
                      onSettings: _openSettings,
                      onClose: widget.desktopExperience == null
                          ? null
                          : () => unawaited(
                              widget.desktopExperience!.hideWindow(),
                            ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final inset = constraints.maxWidth < 320
                              ? 14.0
                              : 24.0;
                          return Padding(
                            padding: EdgeInsets.fromLTRB(inset, 24, inset, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ModeHeader(
                                  mode: _view,
                                  date: _displayDate,
                                  period: _taskPeriod,
                                  completed: completed,
                                  total: _visibleTasks.length,
                                  planCount: _plans.length,
                                  goalCount: _goals.length,
                                ),
                                const SizedBox(height: 24),
                                if (_repository.unreadableFiles.isNotEmpty)
                                  TextButton(
                                    key: const Key('unreadable-files-warning'),
                                    onPressed: _showUnreadableFiles,
                                    child: Text(
                                      '${_repository.unreadableFiles.length} 个文件无法读取，点击查看',
                                    ),
                                  ),
                                Expanded(child: _buildCurrentArea()),
                                const Divider(
                                  height: 1,
                                  thickness: 0.7,
                                  color: _line,
                                ),
                                const SizedBox(height: 12),
                                _VaultStatus(
                                  path: _repository.vaultDirectory.path,
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
      _HomeView.history => TaskBrowserPage(
        key: ValueKey(_repository.vaultDirectory.path),
        repository: _repository,
        clock: _now,
        initialView: TaskView.completed,
        goals: _goals,
        embedded: true,
        onEditingChanged: (editing) => _taskEditorOpen = editing,
      ),
    };
  }

  Future<void> _saveTaskOptions(
    String taskId,
    EventRepeat repeat,
    DateTime? reminderAt,
  ) => _actions.run(() async {
    await _repository.saveTaskOptions(
      task: _taskById(taskId),
      repeat: repeat,
      reminderAt: reminderAt,
    );
    await _load();
  });

  List<GoodDayTask> get _visibleTasks => _tasks
      .where((task) => task.appearsIn(_taskPeriod, _displayDate))
      .toList();

  Future<void> _changeTaskPeriod(TaskPeriod period) async {
    if (!await _saveBeforeLeave() || !mounted) return;
    setState(() {
      _taskPeriod = period;
      _expandedTaskId = null;
      _isAdding = false;
    });
    if (_taskScrollController.hasClients) _taskScrollController.jumpTo(0);
  }

  Future<void> _reassignTask(GoodDayTask task, TaskPeriod period) async {
    try {
      await _repository.rescheduleTaskPeriod(_taskById(task.id), period);
      await _load();
    } finally {
      _taskEditorOpen = false;
    }
  }

  Widget _taskTile(GoodDayTask task, int number) {
    return _TaskTile(
      key: ValueKey(task.id),
      number: number,
      task: task,
      goals: _goals,
      expanded: _expandedTaskId == task.id,
      onToggleExpanded: () => _toggleEditor(_HomeView.today, task.id),
      onChanged: (value) => _toggleTask(task, value),
      onDetailsChanged: (title, notes) =>
          _updateTaskDetails(task.id, title, notes),
      onGoalChanged: (goalId) => _assignTaskGoal(task.id, goalId),
      onAddSubtask: (title) => _addSubtask(task.id, title),
      onUpdateSubtask: (subtaskId, {title, isCompleted}) => _updateSubtask(
        task.id,
        subtaskId,
        title: title,
        isCompleted: isCompleted,
      ),
      onRemoveSubtask: (subtaskId) => _removeSubtask(task.id, subtaskId),
      onDelete: () => _deleteTask(task),
      onReassign: _taskPeriod == TaskPeriod.backlog
          ? (period) => _reassignTask(task, period)
          : null,
      clock: _now,
      onOptionsChanged: (repeat, time) =>
          _saveTaskOptions(task.id, repeat, time),
      onOptionsEditingChanged: (editing) => _taskEditorOpen = editing,
    );
  }

  Widget _taskSection(String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      '$label · $count',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _muted,
      ),
    ),
  );

  Widget _buildTaskArea() {
    final tasks = _visibleTasks;
    final ongoing = tasks.where((task) => !task.isCompleted).toList();
    final completed = tasks.where((task) => task.isCompleted).toList()
      ..sort(
        (a, b) => (b.completedAt ?? b.scheduledDate).compareTo(
          a.completedAt ?? a.scheduledDate,
        ),
      );
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final period in TaskPeriod.values)
                ChoiceChip(
                  key: Key('task-period-${period.name}'),
                  label: Text(
                    period == TaskPeriod.backlog &&
                            _tasks.any(
                              (task) => task.isWaitingForSchedule(_displayDate),
                            )
                        ? '${period.label} ${_tasks.where((task) => task.isWaitingForSchedule(_displayDate)).length}'
                        : period.label,
                  ),
                  showCheckmark: false,
                  selected: _taskPeriod == period,
                  visualDensity: VisualDensity.compact,
                  labelStyle: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontSize: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  onSelected: (_) => _changeTaskPeriod(period),
                ),
            ],
          ),
        ),
        if (_taskPeriod == TaskPeriod.backlog)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '保留原记录，展开后可重新安排',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _taskScrollController,
            thickness: 2,
            child: ListView(
              controller: _taskScrollController,
              key: const PageStorageKey('today-list'),
              padding: EdgeInsets.zero,
              children: [
                _taskSection('进行中', ongoing.length),
                for (var index = 0; index < ongoing.length; index++)
                  _taskTile(ongoing[index], index + 1),
                if (_taskPeriod != TaskPeriod.backlog)
                  _AddTaskRow(
                    number: ongoing.length + 1,
                    editing: _isAdding,
                    controller: _controller,
                    focusNode: _focusNode,
                    onStart: _startAdding,
                    onAdd: _attemptAddTask,
                    onCancel: _cancelAdding,
                  ),
                if (ongoing.isEmpty && _taskPeriod == TaskPeriod.backlog)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '没有等待安排的任务',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ),
                if (_taskPeriod != TaskPeriod.backlog) ...[
                  _taskSection('已完成', completed.length),
                  for (var index = 0; index < completed.length; index++)
                    _taskTile(completed[index], index + 1),
                  if (completed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '这个周期还没有已完成记录',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanArea() {
    return Scrollbar(
      thickness: 2,
      child: ListView.builder(
        key: const PageStorageKey('plans-list'),
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
              onToggleExpanded: () => _toggleEditor(_HomeView.plans, plan.id),
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
        key: const PageStorageKey('goals-list'),
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
              onToggleExpanded: () => _toggleEditor(_HomeView.goals, goal.id),
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
  const _WindowBar({
    this.title = 'GOOD DAY',
    this.onBack,
    this.onSettings,
    this.onClose,
  });

  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Colors.transparent,
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/branding/good_day_mark.png',
                          key: const Key('good-day-brand-mark'),
                          width: 26,
                          height: 26,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF555A56),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                      ],
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
            onPressed: onClose ?? windowManager.close,
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
      width: 40,
      height: 44,
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
            width: 40,
            height: 44,
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
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final outline = Path();
    for (var i = 0; i < 32; i++) {
      final angle = i * math.pi / 16 - math.pi / 2;
      final radius = (i % 4 == 1 || i % 4 == 2) ? 8.0 : 6.4;
      final p = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        outline.moveTo(p.dx, p.dy);
      } else {
        outline.lineTo(p.dx, p.dy);
      }
    }
    outline.close();
    canvas.drawPath(outline, paint);
    canvas.drawCircle(center, 2.5, paint);
  }

  @override
  bool shouldRepaint(_GearPainter oldDelegate) => oldDelegate.color != color;
}

class _NoteNavigation extends StatelessWidget {
  const _NoteNavigation({required this.mode, required this.onSelect});
  final _HomeView mode;
  final ValueChanged<_HomeView> onSelect;
  static const _colors = [
    Color(0xFFE2EBDD),
    Color(0xFFF2E9CB),
    Color(0xFFE7E1F0),
    Color(0xFFF0DFD5),
  ];
  static const _icons = [
    Icons.checklist_outlined,
    Icons.event_note_outlined,
    Icons.flag_outlined,
    Icons.history,
  ];
  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('note-navigation'),
    width: 56,
    child: Padding(
      padding: const EdgeInsets.only(top: 88),
      child: Column(
        children: [
          for (final view in _HomeView.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                selected: mode == view,
                button: true,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: EdgeInsets.only(left: mode == view ? 0 : 6),
                  height: 58,
                  decoration: BoxDecoration(
                    color: _colors[view.index],
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x1C29382B),
                        blurRadius: mode == view ? 10 : 4,
                        offset: const Offset(-1, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: Key('nav-${view.name}'),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(8),
                      ),
                      onTap: () => onSelect(view),
                      child: Stack(
                        children: [
                          if (mode == view)
                            Positioned(
                              left: 0,
                              top: 18,
                              bottom: 18,
                              child: Container(
                                width: 3,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF3E624D),
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _icons[view.index],
                                  size: 18,
                                  color: mode == view ? _ink : _muted,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _ModeHeader.label(view),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: mode == view ? _ink : _muted,
                                    fontWeight: mode == view
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ModeHeader extends StatelessWidget {
  const _ModeHeader({
    required this.mode,
    required this.date,
    required this.completed,
    required this.total,
    required this.planCount,
    required this.goalCount,
    this.period = TaskPeriod.day,
  });
  final _HomeView mode;
  final DateTime date;
  final TaskPeriod period;
  final int completed, total, planCount, goalCount;
  static String label(_HomeView view) => switch (view) {
    _HomeView.today => '待办',
    _HomeView.plans => '计划',
    _HomeView.goals => '目标',
    _HomeView.history => '历史',
  };
  @override
  Widget build(BuildContext context) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final taskDateLabel = switch (period) {
      TaskPeriod.day =>
        '${date.month}月${date.day}日  ${weekdays[date.weekday - 1]}',
      TaskPeriod.week =>
        '${dateKey(period.start(date))} — ${dateKey(DateTime(period.end(date).year, period.end(date).month, period.end(date).day - 1))}',
      TaskPeriod.month => '${date.year}年${date.month}月',
      TaskPeriod.year => '${date.year}年',
      TaskPeriod.backlog => '过期未完成，等待重新安排',
    };
    final count = switch (mode) {
      _HomeView.today => '$completed / $total 完成',
      _HomeView.plans => '$planCount 项计划',
      _HomeView.goals => '$goalCount 个目标',
      _HomeView.history => '记录与回顾',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label(mode),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 30,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            Text(count, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          mode == _HomeView.today
              ? taskDateLabel
              : switch (mode) {
                  _HomeView.plans => '给下一步留一个位置',
                  _HomeView.goals => '让每天的行动有方向',
                  _HomeView.history => '查看已完成与未完成的记录',
                  _HomeView.today => '',
                },
          style: const TextStyle(color: _muted, fontSize: 12),
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
      child: editing
          ? Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '$number',
                    style: const TextStyle(color: _muted, fontSize: 12),
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
                      style: const TextStyle(color: _ink, fontSize: 14),
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
                      style: const TextStyle(color: _muted, fontSize: 12),
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
  Widget build(BuildContext context) => const SizedBox(
    height: 56,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Divider(height: 1, thickness: 0.5, color: _line),
    ),
  );
}

class _GoalBadge extends StatelessWidget {
  const _GoalBadge({required this.goal});

  final GoodDayGoal goal;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(goal.colorValue),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              goal.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 11),
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
        color: const Color(0xFFF5F5F0),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            value: '',
            child: Text('无目标', style: TextStyle(fontSize: 12)),
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
                      style: const TextStyle(fontSize: 12),
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
              const Text('所属目标', style: TextStyle(color: _muted, fontSize: 12)),
              const Spacer(),
              if (selected == null)
                const Text('无', style: TextStyle(color: _muted, fontSize: 12))
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

class _GoalTileState extends State<_GoalTile>
    with AutomaticKeepAliveClientMixin<_GoalTile>, ReliableEditor<_GoalTile> {
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
    _nameController.addListener(markPendingEdit);
    _descriptionController.addListener(markPendingEdit);
  }

  @override
  void didUpdateWidget(covariant _GoalTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!hasPendingEdits &&
        !_nameFocus.hasFocus &&
        _nameController.text != widget.goal.name) {
      _nameController.text = widget.goal.name;
    }
    if (!hasPendingEdits &&
        !_descriptionFocus.hasFocus &&
        _descriptionController.text != widget.goal.description) {
      _descriptionController.text = widget.goal.description;
    }
    if (!hasPendingEdits && !widget.expanded) {
      _colorValue = widget.goal.colorValue;
    }
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
    markPendingEdit();
    _saveTimer?.cancel();
    final valid = _nameController.text.trim().isNotEmpty;
    if (_nameError == valid) setState(() => _nameError = !valid);
    if (valid) {
      _saveTimer = Timer(const Duration(milliseconds: 650), _saveDetails);
    }
  }

  Future<bool> _saveDetails() async {
    _saveTimer?.cancel();
    markPendingEdit();
    return flushPendingEdits();
  }

  @override
  Future<bool> persistEdits() async {
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
    super.build(context);
    final goal = widget.goal;
    return TapRegion(
      onTapOutside: widget.expanded ? (_) => _toggleExpanded() : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: widget.expanded ? _expandedPaper : Colors.transparent,
          border: const Border(bottom: BorderSide(color: _line, width: 0.7)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 28,
                  color: Color(widget.expanded ? _colorValue : goal.colorValue),
                ),
                const SizedBox(width: 16),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
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
                                fontSize: 14,
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
                        : Icons.chevron_right,
                  ),
                ),
                if (widget.expanded)
                  IconButton(
                    key: Key('delete-goal-${goal.id}'),
                    onPressed: widget.onDelete,
                    tooltip: '删除目标',
                    iconSize: 14,
                    color: _muted,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            if (widget.expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(19, 2, 38, 7),
                child: TextField(
                  key: Key('edit-goal-description-${goal.id}'),
                  controller: _descriptionController,
                  focusNode: _descriptionFocus,
                  maxLines: 1,
                  onChanged: (_) => _scheduleSave(),
                  onSubmitted: (_) => _saveDetails(),
                  style: const TextStyle(color: _muted, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '简短描述（可选）',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 7),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(19, 1, 0, 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 8,
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
                    const SizedBox(width: 8),
                    if (_saving || _saved || _nameError)
                      Text(
                        _nameError
                            ? '名称不能为空'
                            : _saving
                            ? '保存中…'
                            : '已保存',
                        style: TextStyle(
                          color: _nameError ? const Color(0xFF8B3A32) : _muted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ] else if (goal.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(19, 0, 38, 3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    goal.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
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

class _GoalComposerState extends State<_GoalComposer>
    with
        AutomaticKeepAliveClientMixin<_GoalComposer>,
        ReliableEditor<_GoalComposer> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _focusNode = FocusNode();
  bool _editing = false;
  bool _saving = false;
  int _colorValue = _goalPalette.first.toARGB32();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(markPendingEdit);
    _descriptionController.addListener(markPendingEdit);
  }

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
    markPendingEdit();
    await flushPendingEdits();
  }

  @override
  Future<bool> persistEdits() async {
    if (_saving) return false;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (_descriptionController.text.trim().isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请填写目标名称，或取消添加')));
        return false;
      }
      _cancel();
      return true;
    }
    setState(() => _saving = true);
    try {
      await widget.onCreate(
        name,
        _descriptionController.text.trim(),
        _colorValue,
      );
      if (mounted) _cancel();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，已保留输入：$error')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: TextField(
                    enabled: !_saving,
                    key: const Key('new-goal-name'),
                    controller: _nameController,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: _ink, fontSize: 14),
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
                enabled: !_saving,
                key: const Key('new-goal-description'),
                controller: _descriptionController,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _finish(),
                style: const TextStyle(color: _muted, fontSize: 12),
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

class _PlanTileState extends State<_PlanTile>
    with AutomaticKeepAliveClientMixin<_PlanTile>, ReliableEditor<_PlanTile> {
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
    _titleController.addListener(markPendingEdit);
  }

  @override
  void didUpdateWidget(covariant _PlanTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!hasPendingEdits &&
        !_titleFocus.hasFocus &&
        _titleController.text != widget.plan.title) {
      _titleController.text = widget.plan.title;
    }
    if (!hasPendingEdits && !widget.expanded) {
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
    markPendingEdit();
    _saveTimer?.cancel();
    final valid = _titleController.text.trim().isNotEmpty;
    if (_titleError == valid) setState(() => _titleError = !valid);
    if (valid) {
      _saveTimer = Timer(const Duration(milliseconds: 650), _saveDetails);
    }
  }

  Future<bool> _saveDetails() async {
    _saveTimer?.cancel();
    markPendingEdit();
    return flushPendingEdits();
  }

  @override
  Future<bool> persistEdits() async {
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
    super.build(context);
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: widget.expanded ? _expandedPaper : Colors.transparent,
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
                    style: const TextStyle(color: _muted, fontSize: 12),
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
                            color: plan.isCompleted ? _muted : _ink,
                            fontSize: 14,
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
                                color: plan.isCompleted ? _muted : _ink,
                                fontSize: 14,
                                decoration: plan.isCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                ),

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
                        : Icons.chevron_right,
                  ),
                ),
                if (widget.expanded)
                  IconButton(
                    key: Key('delete-plan-${plan.id}'),
                    onPressed: widget.onDelete,
                    tooltip: '删除计划',
                    iconSize: 14,
                    color: _muted,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            if (!widget.expanded && widget.goal != null)
              Padding(
                padding: const EdgeInsets.only(left: 60, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _GoalBadge(goal: widget.goal!),
                ),
              ),
            if (widget.expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(60, 3, 0, 3),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${_deadline.year}.${_deadline.month}.${_deadline.day}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
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
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 6,
                    children: [
                      const Text(
                        '所属目标',
                        style: TextStyle(color: _muted, fontSize: 12),
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
                      const SizedBox(width: 8),
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
                            fontSize: 12,
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
                  Expanded(
                    child: Text(
                      plan.isCompleted
                          ? '已完成'
                          : '截止 ${plan.deadline.month}月${plan.deadline.day}日 · $timing',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!plan.isCompleted)
                    Text(
                      '$percent%',
                      style: const TextStyle(color: _muted, fontSize: 11),
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

class _PlanComposerState extends State<_PlanComposer>
    with
        AutomaticKeepAliveClientMixin<_PlanComposer>,
        ReliableEditor<_PlanComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _editing = false;
  bool _saving = false;
  bool _choosingDate = false;
  bool _needsDeadline = false;
  DateTime? _deadline;
  String? _goalId;

  @override
  void initState() {
    super.initState();
    _controller.addListener(markPendingEdit);
  }

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
    markPendingEdit();
    await flushPendingEdits();
  }

  @override
  Future<bool> persistEdits() async {
    if (_saving || _choosingDate) return false;
    final title = _controller.text.trim();
    if (title.isEmpty && _deadline == null) {
      _cancel();
      return true;
    }
    if (title.isEmpty || _deadline == null) {
      setState(() => _needsDeadline = _deadline == null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写计划名称并选择截止日期，或取消添加')));
      return false;
    }
    setState(() => _saving = true);
    try {
      await widget.onCreate(title, _deadline!, _goalId);
      if (mounted) _cancel();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，已保留输入：$error')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setDeadline(int daysFromNow) {
    markPendingEdit();
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
    super.build(context);
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
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: TextField(
                    enabled: !_saving,
                    key: const Key('new-plan-title'),
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(color: _ink, fontSize: 14),
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
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 6,
                children: [
                  Text(
                    _deadline == null
                        ? (_needsDeadline ? '请选择截止日期' : '截止日期')
                        : '${_deadline!.year}.${_deadline!.month}.${_deadline!.day}',
                    style: TextStyle(
                      color: _needsDeadline ? const Color(0xFF8B3A32) : _muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
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
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 6,
                  children: [
                    const Text(
                      '所属目标',
                      style: TextStyle(color: _muted, fontSize: 12),
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
        child: Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
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
                style: const TextStyle(color: _muted, fontSize: 12),
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
    required this.clock,
    required this.onOptionsChanged,
    required this.onOptionsEditingChanged,
    this.onReassign,
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
  final DateTime Function() clock;
  final Future<void> Function(EventRepeat repeat, DateTime? time)
  onOptionsChanged;
  final ValueChanged<bool> onOptionsEditingChanged;
  final Future<void> Function(TaskPeriod period)? onReassign;

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile>
    with AutomaticKeepAliveClientMixin<_TaskTile>, ReliableEditor<_TaskTile> {
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
  bool _optionsEditing = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _noteController = TextEditingController(text: widget.task.notes);
    _titleController.addListener(markPendingEdit);
    _noteController.addListener(markPendingEdit);
    _newSubtaskController.addListener(markPendingEdit);
  }

  @override
  void didUpdateWidget(covariant _TaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!hasPendingEdits &&
        !_titleFocus.hasFocus &&
        _titleController.text != widget.task.title) {
      _titleController.text = widget.task.title;
    }
    if (!hasPendingEdits &&
        !_noteFocus.hasFocus &&
        _noteController.text != widget.task.notes) {
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
    markPendingEdit();
    _saveTimer?.cancel();
    final valid = _titleController.text.trim().isNotEmpty;
    if (_titleError == valid) setState(() => _titleError = !valid);
    if (!valid) return;
    _saveTimer = Timer(const Duration(milliseconds: 650), _saveDetails);
  }

  Future<bool> _saveDetails() async {
    _saveTimer?.cancel();
    markPendingEdit();
    return flushPendingEdits();
  }

  @override
  Future<bool> persistEdits() async {
    if (!await _persistTaskDetails()) return false;
    if (_newSubtaskController.text.trim().isNotEmpty) {
      return _persistNewSubtask();
    }
    return true;
  }

  Future<bool> _persistTaskDetails() async {
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
    if (_optionsEditing) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先设置提醒或取消')));
      return;
    }
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
    markPendingEdit();
    await flushPendingEdits();
  }

  Future<bool> _persistNewSubtask() async {
    final title = _newSubtaskController.text.trim();
    if (title.isEmpty) return true;
    try {
      await widget.onAddSubtask(title);
      if (!mounted) return true;
      _newSubtaskController.clear();
      setState(() => _addingSubtask = false);
      return true;
    } catch (error) {
      if (!mounted) return true;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法添加子任务：$error')));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final task = widget.task;
    GoodDayGoal? selectedGoal;
    for (final goal in widget.goals) {
      if (goal.id == task.goalId) selectedGoal = goal;
    }
    final titleColor = selectedGoal == null
        ? (task.isCompleted ? _muted : _ink)
        : Color(selectedGoal.colorValue);
    return TapRegion(
      onTapOutside: widget.expanded && !_optionsEditing
          ? (_) => _toggleExpanded()
          : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hovering || widget.expanded
                ? _expandedPaper
                : Colors.transparent,
            border: const Border(bottom: BorderSide(color: _line, width: 0.7)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${widget.number}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Transform.scale(
                        scale: 0.78,
                        child: Checkbox(
                          key: Key('task-checkbox-${task.id}'),
                          value: task.isCompleted,
                          onChanged: _optionsEditing ? null : widget.onChanged,
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
                                color: titleColor,
                                fontSize: 14,
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
                                      color: titleColor,
                                      fontSize: 14,
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
                            : Icons.chevron_right,
                      ),
                    ),
                    if (widget.expanded)
                      Opacity(
                        opacity: 1,
                        child: IconButton(
                          key: Key('delete-task-${task.id}'),
                          onPressed: _optionsEditing ? null : widget.onDelete,
                          tooltip: '移到垃圾桶',
                          iconSize: 14,
                          color: _muted,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
                if (!widget.expanded && task.notes.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 60,
                      right: 16,
                      bottom: 6,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        task.notes,
                        key: Key('task-note-preview-${task.id}'),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                if (widget.expanded) ...[
                  if (widget.onReassign != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(60, 0, 16, 4),
                      child: PopupMenuButton<TaskPeriod>(
                        key: Key('reassign-task-${task.id}'),
                        onOpened: () {
                          setState(() => _optionsEditing = true);
                          widget.onOptionsEditingChanged(true);
                        },
                        onCanceled: () {
                          setState(() => _optionsEditing = false);
                          widget.onOptionsEditingChanged(false);
                        },
                        onSelected: (period) async {
                          try {
                            if (!await _persistTaskDetails()) return;
                            await widget.onReassign!(period);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('重新安排失败：$error')),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _optionsEditing = false);
                            }
                            widget.onOptionsEditingChanged(false);
                          }
                        },
                        itemBuilder: (_) => [
                          for (final period in TaskPeriod.values.where(
                            (p) => p != TaskPeriod.backlog,
                          ))
                            PopupMenuItem(
                              value: period,
                              child: Text('安排到${period.label}'),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            '重新安排 · ${task.period.label} ${dateKey(task.scheduledDate)} ▾',
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(60, 2, 16, 7),
                    child: TaskInlineOptions(
                      task: task,
                      clock: widget.clock,
                      onEditingChanged: (editing) {
                        setState(() => _optionsEditing = editing);
                        widget.onOptionsEditingChanged(editing);
                      },
                      onSave: (repeat, time) async {
                        if (!await _persistTaskDetails() ||
                            !await _persistNewSubtask()) {
                          throw const FileSystemException('请先填写任务名称并保存');
                        }
                        await widget.onOptionsChanged(repeat, time);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(60, 2, 16, 7),
                    child: TextField(
                      key: Key('task-note-${task.id}'),
                      controller: _noteController,
                      focusNode: _noteFocus,
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => _scheduleSave(),
                      onSubmitted: (_) => _saveDetails(),
                      style: const TextStyle(color: _muted, fontSize: 12),
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
                              style: const TextStyle(color: _ink, fontSize: 12),
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
                                      fontSize: 12,
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
                            fontSize: 12,
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
                fontSize: 12,
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

class _EditableSubtaskRowState extends State<_EditableSubtaskRow>
    with
        AutomaticKeepAliveClientMixin<_EditableSubtaskRow>,
        ReliableEditor<_EditableSubtaskRow> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  Timer? _timer;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.subtask.title);
    _controller.addListener(markPendingEdit);
  }

  @override
  void didUpdateWidget(covariant _EditableSubtaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!hasPendingEdits &&
        !_focusNode.hasFocus &&
        _controller.text != widget.subtask.title) {
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
    markPendingEdit();
    _timer?.cancel();
    final valid = _controller.text.trim().isNotEmpty;
    if (_error == valid) setState(() => _error = !valid);
    if (!valid) return;
    _timer = Timer(const Duration(milliseconds: 650), _save);
  }

  Future<void> _save() async {
    _timer?.cancel();
    markPendingEdit();
    await flushPendingEdits();
  }

  @override
  Future<bool> persistEdits() async {
    _timer?.cancel();
    final title = _controller.text.trim();
    if (title.isEmpty) {
      if (mounted) setState(() => _error = true);
      return false;
    }
    if (title == widget.subtask.title) return true;
    try {
      await widget.onUpdate(widget.subtask.id, title: title);
      if (mounted) setState(() => _error = false);
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('子任务保存失败，已保留输入：$error')));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                fontSize: 12,
                decoration: subtask.isCompleted
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
              decoration: InputDecoration(
                hintText: _error ? '子任务不能为空' : null,
                hintStyle: const TextStyle(
                  color: Color(0xFF8B3A32),
                  fontSize: 12,
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
typedef IsLaunchAtStartupEnabledCallback = Future<bool> Function();
typedef LaunchAtStartupChangedCallback = Future<void> Function(bool enabled);

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.initialVaultPath,
    required this.onVaultSelected,
    required this.onLoadTrash,
    required this.onRestoreTrashItem,
    required this.onEmptyTrash,
    this.onOpenBackups,
    this.isLaunchAtStartupEnabled,
    this.onLaunchAtStartupChanged,
    this.onOpenLegacyReminders,
  });

  final AppSettingsController controller;
  final String initialVaultPath;
  final VaultSelectedCallback onVaultSelected;
  final LoadTrashCallback onLoadTrash;
  final RestoreTrashItemCallback onRestoreTrashItem;
  final EmptyTrashCallback onEmptyTrash;
  final VoidCallback? onOpenBackups;
  final IsLaunchAtStartupEnabledCallback? isLaunchAtStartupEnabled;
  final LaunchAtStartupChangedCallback? onLaunchAtStartupChanged;
  final VoidCallback? onOpenLegacyReminders;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _vaultPath;
  bool _switchingVault = false;
  bool _deleteSourceAfterMigration = false;
  bool _fontsExpanded = false;
  bool _launchAtStartup = false;
  bool _loadingLaunchAtStartup = true;
  bool _changingLaunchAtStartup = false;

  @override
  void initState() {
    super.initState();
    _vaultPath = widget.initialVaultPath;
    _loadLaunchAtStartup();
  }

  Future<void> _loadLaunchAtStartup() async {
    final load = widget.isLaunchAtStartupEnabled;
    if (load == null) {
      if (mounted) setState(() => _loadingLaunchAtStartup = false);
      return;
    }
    try {
      final enabled = await load();
      if (mounted) {
        setState(() {
          _launchAtStartup = enabled;
          _loadingLaunchAtStartup = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingLaunchAtStartup = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法读取开机启动状态：$error')));
    }
  }

  Future<void> _changeLaunchAtStartup(bool enabled) async {
    final change = widget.onLaunchAtStartupChanged;
    if (change == null || _changingLaunchAtStartup) return;
    setState(() => _changingLaunchAtStartup = true);
    try {
      await change(enabled);
      if (mounted) setState(() => _launchAtStartup = enabled);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法修改开机启动：$error')));
    } finally {
      if (mounted) setState(() => _changingLaunchAtStartup = false);
    }
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
            '迁移成功后，Good Day 将删除原位置中的任务、计划、目标、待办事件、每日记录、垃圾桶和设置文件。\n\n'
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final settings = widget.controller.settings;
      final busy = _loadingLaunchAtStartup || _changingLaunchAtStartup;
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            color: _paper,
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  children: [
                    const Text(
                      '设置',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 30,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _SettingsSectionTitle(label: '外观'),
                    const SizedBox(height: 8),
                    _PreferenceRow(
                      key: const Key('font-picker-button'),
                      label: '字体',
                      value: settings.font.label,
                      onTap: () =>
                          setState(() => _fontsExpanded = !_fontsExpanded),
                      trailing: Icon(
                        _fontsExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.chevron_right,
                        size: 16,
                        color: _muted,
                      ),
                    ),
                    if (_fontsExpanded)
                      Container(
                        color: _expandedPaper,
                        child: Column(
                          children: [
                            for (final font in AppFont.values)
                              _FontOption(
                                option: font,
                                selected: settings.font == font,
                                accent: settings.accent.color,
                                onTap: () async {
                                  await widget.controller.setFont(font);
                                  if (mounted) {
                                    setState(() => _fontsExpanded = false);
                                  }
                                },
                              ),
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                '专注当下，慢慢完成。\nGood day, one thing at a time.',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  height: 1.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _PreferenceRow(
                      label: '主题颜色',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final accent in AppAccent.values)
                            _AccentOption(
                              option: accent,
                              selected: settings.accent == accent,
                              onTap: () => widget.controller.setAccent(accent),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: _line),
                    const SizedBox(height: 20),
                    const _SettingsSectionTitle(label: '桌面'),
                    const SizedBox(height: 8),
                    if (widget.onOpenLegacyReminders != null)
                      _PreferenceRow(
                        key: const Key('legacy-reminders-button'),
                        label: '已有独立提醒',
                        subtitle: '管理旧版创建的提醒',
                        onTap: widget.onOpenLegacyReminders,
                        trailing: const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: _muted,
                        ),
                      ),
                    _PreferenceRow(
                      key: const Key('launch-at-startup-option'),
                      label: '开机启动',
                      subtitle: '登录 Windows 后自动打开',
                      onTap: busy || widget.onLaunchAtStartupChanged == null
                          ? null
                          : () => _changeLaunchAtStartup(!_launchAtStartup),
                      trailing: busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          : Switch(
                              key: const Key('launch-at-startup-checkbox'),
                              value: _launchAtStartup,
                              onChanged: widget.onLaunchAtStartupChanged == null
                                  ? null
                                  : _changeLaunchAtStartup,
                            ),
                    ),
                    const _PreferenceRow(label: '关闭窗口', value: '隐藏到托盘'),
                    const Divider(height: 1, color: _line),
                    const SizedBox(height: 20),
                    const _SettingsSectionTitle(label: '数据'),
                    if (widget.onOpenBackups != null)
                      _PreferenceRow(
                        key: const Key('backups-button'),
                        label: '数据备份',
                        subtitle: '自动备份、手动备份与恢复',
                        onTap: widget.onOpenBackups,
                        trailing: const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: _muted,
                        ),
                      ),
                    const SizedBox(height: 8),
                    _PreferenceRow(
                      label: '存放文件夹',
                      trailing: TextButton(
                        key: const Key('choose-vault-button'),
                        onPressed: _switchingVault ? null : _chooseVault,
                        child: Text(_switchingVault ? '切换中…' : '更改'),
                      ),
                    ),
                    Tooltip(
                      message: _vaultPath,
                      child: Text(
                        _vaultPath,
                        key: const Key('vault-path'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      key: const Key('delete-source-option'),
                      onTap: _switchingVault
                          ? null
                          : () => setState(
                              () => _deleteSourceAfterMigration =
                                  !_deleteSourceAfterMigration,
                            ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            height: 40,
                            child: Checkbox(
                              key: const Key('delete-source-checkbox'),
                              value: _deleteSourceAfterMigration,
                              onChanged: _switchingVault
                                  ? null
                                  : (value) => setState(
                                      () => _deleteSourceAfterMigration =
                                          value ?? false,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '迁移后删除原数据',
                              style: TextStyle(color: _ink, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      '选择空文件夹会迁移数据，默认保留原位置。删除前会再次确认。',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PreferenceRow(
                      key: const Key('trash-button'),
                      label: '垃圾桶',
                      subtitle: '查看或恢复已删除内容',
                      onTap: _openTrash,
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: _muted,
                      ),
                    ),
                    const Divider(height: 1, color: _line),
                    const SizedBox(height: 20),
                    const Text(
                      '数据保存在本地 · Markdown',
                      style: TextStyle(color: _muted, fontSize: 12),
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

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    super.key,
    required this.label,
    this.value,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final String label;
  final String? value, subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: _ink, fontSize: 14),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    ),
  );
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
    TrashItemType.event => '待办事件',
  };

  IconData _typeIcon(TrashItemType type) => switch (type) {
    TrashItemType.task => Icons.check_box_outlined,
    TrashItemType.plan => Icons.calendar_today_outlined,
    TrashItemType.goal => Icons.flag_outlined,
    TrashItemType.event => Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: _paper,
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Column(
          children: [
            _WindowBar(title: '垃圾桶', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
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
                                '垃圾桶',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '删除后仍可在这里恢复。',
                                style: TextStyle(color: _muted, fontSize: 12),
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
                                      fontSize: 12,
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
                                                fontSize: 12,
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
                                          style: TextStyle(fontSize: 12),
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
                    fontSize: 14,
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: option.label,
    child: Tooltip(
      message: option.label,
      child: InkWell(
        key: Key('accent-${option.key}'),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 40,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: option.color,
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
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
          Text('Markdown 已同步', style: TextStyle(color: _muted, fontSize: 12)),
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
          const Text('无法读取 Vault', style: TextStyle(color: _ink, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
