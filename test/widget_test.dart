import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/desktop_experience.dart';
import 'package:good_day/main.dart';
import 'package:good_day/models/good_day_goal.dart';
import 'package:good_day/models/good_day_plan.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/good_day_event.dart';
import 'package:good_day/settings/app_settings.dart';
import 'package:good_day/models/task_series.dart';
import 'package:good_day/task_browser_page.dart';

void main() {
  testWidgets(
    'pin reflects native state, survives routes and handles failure',
    (tester) async {
      final desktop = _FakeDesktopExperience();
      await tester.pumpWidget(
        GoodDayApp(
          repository: _MemoryRepository(),
          settingsController: AppSettingsController.inMemory(),
          desktopExperience: desktop,
        ),
      );
      await tester.pumpAndSettle();
      IconButton button() =>
          tester.widget<IconButton>(find.byKey(const Key('window-pin')));
      expect(button().isSelected, false);
      await tester.tap(find.byKey(const Key('window-pin')));
      await tester.pumpAndSettle();
      expect(desktop.windowPinned.value, true);
      expect(button().isSelected, true);
      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      expect(button().isSelected, true);
      desktop.failPin = true;
      await tester.tap(find.byKey(const Key('window-pin')));
      await tester.pumpAndSettle();
      expect(button().isSelected, true);
      expect(find.text('置顶设置未成功，请重试'), findsOneWidget);
      desktop.failPin = false;
      await tester.tap(find.byKey(const Key('window-pin')));
      await tester.pumpAndSettle();
      expect(button().isSelected, false);
    },
  );

  testWidgets(
    'period text navigation and empty/completed sections stay uncluttered',
    (tester) async {
      final repository = _MemoryRepository();
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const Key('period-navigation-line')), findsOneWidget);
      expect(find.text('2026年9月8日 · 周二'), findsOneWidget);
      expect(find.byKey(const Key('task-section-进行中')), findsNothing);
      expect(find.byKey(const Key('task-section-已完成')), findsNothing);
      expect(find.text('添加今日待办任务'), findsOneWidget);
      expect(
        find.text('待办'),
        findsOneWidget,
      ); // The left note remains the sole page label.
      Text period(String name) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(Key('task-period-$name')),
          matching: find.byType(Text),
        ),
      );
      expect(
        period('day').style!.fontSize,
        greaterThan(period('week').style!.fontSize!),
      );
      await tester.tap(find.byKey(const Key('task-period-week')));
      await tester.pumpAndSettle();
      expect(find.text('2026年第37周 · 9月7日—9月13日'), findsOneWidget);
      final dayEdge = tester
          .getRect(find.byKey(const Key('task-period-day')))
          .bottom;
      final weekEdge = tester
          .getRect(find.byKey(const Key('task-period-week')))
          .bottom;
      expect(dayEdge, closeTo(weekEdge, 0.1));
      expect(
        period('week').style!.fontSize,
        greaterThan(period('day').style!.fontSize!),
      );
      await tester.tap(find.byKey(const Key('task-period-day')));
      await tester.tap(find.byKey(const Key('add-task-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-task-field')), '完成一个任务');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('task-checkbox-${repository.tasks.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-section-已完成')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('task-section-已完成'))).top -
            tester.getRect(find.byKey(const Key('add-task-button'))).bottom,
        greaterThanOrEqualTo(48),
      );
    },
  );

  testWidgets(
    'every accent recolors paper notes and borders while preserving goal colors',
    (tester) async {
      final settings = AppSettingsController.inMemory();
      final repository = _MemoryRepository();
      final goal = await repository.addGoal(
        name: '考研',
        description: '',
        colorValue: 0xFF8779A6,
      );
      final task = await repository.assignTaskGoal(
        await repository.addTask('数学'),
        goal.id,
      );
      await tester.pumpWidget(
        GoodDayApp(repository: repository, settingsController: settings),
      );
      await tester.pumpAndSettle();
      Color? lastPaper, lastNote, lastBorder;
      for (final accent in AppAccent.values) {
        await settings.setAccent(accent);
        await tester.pumpAndSettle();
        final box =
            tester
                    .widget<Container>(find.byKey(const Key('main-paper')))
                    .decoration
                as BoxDecoration;
        final note =
            tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.byKey(const Key('nav-today')),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final border = (box.border as Border).top.color;
        if (lastPaper != null) {
          expect(box.color, isNot(lastPaper));
          expect(note.color, isNot(lastNote));
          expect(border, isNot(lastBorder));
        }
        lastPaper = box.color;
        lastNote = note.color;
        lastBorder = border;
        final label = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(Key('task-content-${task.id}')),
                matching: find.byType(Text),
              )
              .first,
        );
        expect(label.style!.color, Color(goal.colorValue));
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'period pages separate ongoing tasks and aggregate completions, with manual rescheduling',
    (tester) async {
      var now = DateTime(2026, 9, 8, 9, 30);
      final repository = _MemoryRepository(clock: () => now);
      final daily = await repository.addTask('今日三套卷子');
      final weekly = await repository.addPeriodTask('本周一整本', TaskPeriod.week);
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今日三套卷子'), findsOneWidget);
      expect(find.text('本周一整本'), findsNothing);
      await tester.tap(find.byKey(Key('task-checkbox-${daily.id}')));
      await tester.pumpAndSettle();
      final label = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(Key('task-content-${daily.id}')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(label.style!.decoration, TextDecoration.lineThrough);
      await tester.tap(find.byKey(const Key('task-period-week')));
      await tester.pumpAndSettle();
      expect(find.text('本周一整本'), findsOneWidget);
      expect(find.text('今日三套卷子'), findsOneWidget);
      expect(find.byKey(Key('task-period-label-${daily.id}')), findsOneWidget);
      expect(find.byKey(Key('task-period-label-${weekly.id}')), findsNothing);
      await tester.tap(find.byKey(Key('task-checkbox-${weekly.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-period-month')));
      await tester.pumpAndSettle();
      expect(find.text('本周一整本'), findsOneWidget);
      expect(find.text('今日三套卷子'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-task-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-task-field')), '本月完成课程');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repository.tasks.last.period, TaskPeriod.month);
      now = DateTime(2026, 10, 1, 9);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('今日三套卷子'), findsNothing);
      expect(find.text('本周一整本'), findsNothing);
      expect(find.text('本月完成课程'), findsNothing);
      await tester.tap(find.byKey(const Key('task-period-year')));
      await tester.pumpAndSettle();
      expect(find.text('今日三套卷子'), findsOneWidget);
      expect(find.text('本周一整本'), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-period-backlog')));
      await tester.pumpAndSettle();
      expect(find.text('本月完成课程'), findsOneWidget);
      expect(find.byKey(const Key('add-task-button')), findsNothing);
      final waiting = repository.tasks.last;
      await tester.tap(find.byKey(Key('task-content-${waiting.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('reassign-task-${waiting.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('安排到本周'));
      await tester.pumpAndSettle();
      expect(find.text('本月完成课程'), findsNothing);
      await tester.tap(find.byKey(const Key('task-period-week')));
      await tester.pumpAndSettle();
      expect(find.text('本月完成课程'), findsOneWidget);
      expect(repository.tasks.last.period, TaskPeriod.week);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [400.0, 340.0]) {
    testWidgets('quiet layout and inline editing at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 720);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const capture = bool.fromEnvironment('CAPTURE_UI');
      if (capture) {
        await tester.runAsync(() async {
          final inter = FontLoader('Inter')
            ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
          await inter.load();
          final icons = File(
            'E:/Dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          );
          if (await icons.exists()) {
            final loader = FontLoader('MaterialIcons')
              ..addFont(
                icons.readAsBytes().then(
                  (bytes) => ByteData.sublistView(bytes),
                ),
              );
            await loader.load();
          }
          final chinese = File('C:/Windows/Fonts/msyh.ttc');
          if (await chinese.exists()) {
            final font = FontLoader('Microsoft YaHei UI')
              ..addFont(
                chinese.readAsBytes().then(
                  (bytes) => ByteData.sublistView(bytes),
                ),
              );
            await font.load();
          }
        });
      }
      final repository = _MemoryRepository();
      final goal = await repository.addGoal(
        name: '专业学习',
        description: '打好数学与机器学习基础',
        colorValue: 0xFF789A7A,
      );
      await repository.addGoal(
        name: '语言学习',
        description: '每天积累一点表达能力',
        colorValue: 0xFF66899B,
      );
      await repository.addGoal(
        name: '阅读与生活',
        description: '留一些时间给自己',
        colorValue: 0xFFF2B544,
      );
      var task = await repository.addTask('学习线性代数 · 第三章');
      task = await repository.assignTaskGoal(task, goal.id);
      task = await repository.addSubtask(task, '阅读课程笔记');
      task = await repository.addSubtask(task, '完成课后练习');
      task = await repository.updateTaskDetails(
        task,
        title: task.title,
        notes: '先复习公式，再整理易错题',
      );
      await repository.addTask('复习英语单词');
      await repository.setCompleted(await repository.addTask('阅读 20 页'), true);
      final plan = await repository.addPlan(
        title: '完成机器学习基础课程',
        deadline: DateTime.now().add(const Duration(days: 20)),
        goalId: goal.id,
      );
      await repository.addPlan(
        title: '读完《深度学习》',
        deadline: DateTime.now().add(const Duration(days: 12)),
      );
      await repository.deleteTask(await repository.addTask('整理本周错题'));
      final previewPeriodTasks = <TaskPeriod, GoodDayTask>{};
      if (capture) {
        for (final period in [
          TaskPeriod.week,
          TaskPeriod.month,
          TaskPeriod.year,
        ]) {
          previewPeriodTasks[period] = await repository.addPeriodTask(
            '${period.label}刷题计划',
            period,
          );
        }
      }
      final boundaryKey = GlobalKey();
      final previewSettings = AppSettingsController.inMemory();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: GoodDayApp(
            repository: repository,
            settingsController: previewSettings,
            desktopExperience: _FakeDesktopExperience(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      Future<void> inspect(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$name at $width');
        if (capture) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('build/ui-preview')
              ..createSync(recursive: true);
            await File('${directory.path}/${width.toInt()}-$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }

      await inspect('01-today');
      if (capture) {
        await previewSettings.setAccent(AppAccent.blueGrey);
        await inspect('13-blue-theme');
        await previewSettings.setAccent(AppAccent.warmBrown);
        await inspect('14-brown-theme');
        await tester.tap(find.byKey(const Key('task-period-week')));
        await inspect('15-empty-week');
        await tester.tap(find.byKey(const Key('task-period-day')));
        await previewSettings.setAccent(AppAccent.forest);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await inspect('04-task-detail');
      await tester.tap(find.byKey(Key('task-reminder-settings-${task.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('custom-reminder-${task.id}')));
      await inspect('11-task-options');
      await tester.ensureVisible(
        find.byKey(ValueKey('reminder-wheels-${task.id}')),
      );
      await inspect('12-task-options-scrolled');
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      if (capture) {
        for (final entry in previewPeriodTasks.entries) {
          await tester.tap(find.byKey(Key('task-period-${entry.key.name}')));
          await inspect('16-${entry.key.name}-list');
          await tester.tap(find.byKey(Key('task-content-${entry.value.id}')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(Key('task-reminder-settings-${entry.value.id}')),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(ValueKey('reminder-wheels-${entry.value.id}')),
          );
          await inspect('17-${entry.key.name}-reminder');
          await tester.ensureVisible(find.text('取消'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('task-period-day')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('nav-plans')));
      await inspect('02-plans');
      await tester.tap(find.byKey(Key('edit-plan-${plan.id}')));
      await inspect('05-plan-detail');
      await tester.tap(find.byKey(const Key('nav-goals')));
      await inspect('03-goals');
      await tester.tap(find.byKey(Key('edit-goal-${goal.id}')));
      await inspect('06-goal-detail');
      await tester.tap(find.byKey(Key('delete-goal-${goal.id}')));
      await inspect('09-delete-confirm');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-button')));
      await inspect('07-settings');
      await tester.tap(find.byKey(const Key('font-picker-button')));
      await inspect('10-font-picker');
      await tester.tap(find.byKey(const Key('font-picker-button')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('trash-button')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('trash-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trash-button')));
      await tester.pumpAndSettle();
      expect(find.byType(TrashPage), findsOneWidget);
      await inspect('08-trash');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets(
    'left notes keep history in the same window and protect task edits',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _MemoryRepository();
      final task = await repository.addTask('已经完成的阅读');
      await repository.setCompleted(task, true);
      final desktop = _FakeDesktopExperience();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GoodDayApp(
            repository: repository,
            settingsController: AppSettingsController.inMemory(),
            desktopExperience: desktop,
          ),
        ),
      );
      await _flushMicrotasks(tester);
      final paper = tester.getRect(find.byKey(const Key('main-paper')));
      for (final mode in ['today', 'plans', 'goals', 'history']) {
        final tab = tester.getRect(find.byKey(Key('nav-$mode')));
        expect(tab.right, lessThanOrEqualTo(paper.left + 1));
      }
      expect(find.byKey(const Key('home-mode-switch')), findsNothing);
      expect(find.byKey(const Key('home-schedule-task')), findsNothing);
      await tester.tap(find.byKey(const Key('nav-history')));
      await _flushMicrotasks(tester);
      expect(find.byType(TaskBrowserPage), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('nav-today')), findsOneWidget);
      expect(find.text('已经完成的阅读'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('task-filter-completed')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('安排任务'), findsNothing);
      const capture = bool.fromEnvironment('CAPTURE_UI');
      if (capture) {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/ui-preview/400-history-notes.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byKey(const Key('nav-plans')));
      await _flushMicrotasks(tester);
      expect(find.byKey(const Key('add-plan-button')), findsOneWidget);
      expect(find.byType(TaskBrowserPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'todo shows notes without a checkbox, colors titles and embeds reminder settings',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _MemoryRepository();
      final goal = await repository.addGoal(
        name: '考研',
        description: '',
        colorValue: 0xFF66899B,
      );
      var task = await repository.addTask('刷三套试卷');
      task = await repository.assignTaskGoal(task, goal.id);
      final desktop = _FakeDesktopExperience();
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
          desktopExperience: desktop,
        ),
      );
      await _flushMicrotasks(tester);
      expect(find.text('待办'), findsWidgets);
      expect(find.byKey(const Key('nav-events')), findsNothing);
      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await _flushMicrotasks(tester);
      await tester.enterText(
        find.byKey(Key('task-note-${task.id}')),
        '整理错题并回顾公式',
      );
      await tester.tap(find.byKey(Key('task-reminder-settings-${task.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-task-title')), findsNothing);
      expect(find.text('安排日期'), findsNothing);
      expect(await desktop.saveGuard!(), isFalse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('remind-after-${task.id}-5')));
      await _flushMicrotasks(tester);
      expect(repository.tasks.single.reminder, isNotNull);
      await tester.tap(find.byKey(const Key('nav-plans')));
      await _flushMicrotasks(tester);
      await tester.tap(find.byKey(const Key('nav-today')));
      await _flushMicrotasks(tester);
      expect(find.byKey(Key('task-note-preview-${task.id}')), findsOneWidget);
      expect(find.text('考研'), findsNothing);
      final title = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(Key('task-content-${task.id}')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(title.style!.color, Color(goal.colorValue));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(repository.tasks.single.notes, '整理错题并回顾公式');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('adds, completes, and removes a task from the UI', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await _flushMicrotasks(tester);

    expect(find.byKey(const Key('good-day-brand-mark')), findsOneWidget);
    expect(find.byKey(const Key('add-task-button')), findsOneWidget);

    final addRow = find.byKey(const Key('add-task-button'));
    final addRowRect = tester.getRect(addRow);
    await tester.tapAt(Offset(addRowRect.right - 8, addRowRect.center.dy));
    await _flushMicrotasks(tester);
    await tester.enterText(
      find.byKey(const Key('new-task-field')),
      '完成 Good Day MVP',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _flushMicrotasks(tester);

    expect(find.text('完成 Good Day MVP'), findsOneWidget);
    final task = repository.tasks.single;
    final checkbox = find.byKey(Key('task-checkbox-${task.id}'));

    await tester.tap(checkbox);
    await _flushMicrotasks(tester);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    expect(find.byKey(Key('delete-task-${task.id}')), findsNothing);
    await tester.tap(find.byKey(Key('task-content-${task.id}')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(Key('delete-task-${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await _flushMicrotasks(tester);
    expect(find.text('完成 Good Day MVP'), findsNothing);
    expect(repository.tasks, isEmpty);
  });

  testWidgets('finishes or cancels a new task when clicking elsewhere', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await _flushMicrotasks(tester);

    await tester.tap(find.byKey(const Key('add-task-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-task-field')), '点击外部创建');
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    expect(repository.tasks.single.title, '点击外部创建');
    expect(find.text('点击外部创建'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-task-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-task-field')), '   ');
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    expect(repository.tasks, hasLength(1));
    expect(find.byKey(const Key('new-task-field')), findsNothing);
    expect(find.byKey(const Key('add-task-button')), findsOneWidget);
  });

  testWidgets(
    'edits task details and shows checkable subtasks when collapsed',
    (tester) async {
      final repository = _MemoryRepository();
      final task = await repository.addTask('旧任务内容');
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
        ),
      );
      await _flushMicrotasks(tester);

      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await _flushMicrotasks(tester);
      await tester.enterText(
        find.byKey(Key('task-title-${task.id}')),
        '新的任务内容',
      );
      await tester.enterText(find.byKey(Key('task-note-${task.id}')), '一行备注');
      await tester.pump(const Duration(milliseconds: 700));
      await _flushMicrotasks(tester);

      final addSubtaskRow = find.byKey(Key('add-subtask-${task.id}'));
      final addSubtaskRect = tester.getRect(addSubtaskRow);
      await tester.tapAt(
        Offset(addSubtaskRect.right - 4, addSubtaskRect.center.dy),
      );
      await _flushMicrotasks(tester);
      await tester.enterText(
        find.byKey(Key('new-subtask-field-${task.id}')),
        '第一个子任务',
      );
      await tester.tap(find.text('GOOD DAY'));
      await _flushMicrotasks(tester);

      final updated = repository.tasks.single;
      expect(updated.title, '新的任务内容');
      expect(updated.notes, '一行备注');
      expect(updated.subtasks.single.title, '第一个子任务');
      expect(find.byKey(Key('task-note-${task.id}')), findsNothing);
      expect(find.text('第一个子任务'), findsOneWidget);

      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await _flushMicrotasks(tester);
      final subtask = repository.tasks.single.subtasks.single;
      await tester.enterText(
        find.byKey(Key('subtask-title-${task.id}-${subtask.id}')),
        '修改后的子任务',
      );
      await tester.tap(find.text('GOOD DAY'));
      await _flushMicrotasks(tester);
      expect(repository.tasks.single.subtasks.single.title, '修改后的子任务');
      expect(find.byKey(Key('task-note-${task.id}')), findsNothing);

      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await _flushMicrotasks(tester);
      await tester.tap(find.byKey(Key('add-subtask-${task.id}')));
      await _flushMicrotasks(tester);
      await tester.enterText(
        find.byKey(Key('new-subtask-field-${task.id}')),
        '   ',
      );
      await tester.tap(find.text('GOOD DAY'));
      await _flushMicrotasks(tester);
      expect(repository.tasks.single.subtasks, hasLength(1));
      expect(find.byKey(Key('task-note-${task.id}')), findsNothing);

      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('subtask-checkbox-${task.id}-${subtask.id}')),
      );
      await _flushMicrotasks(tester);
      expect(repository.tasks.single.subtasks.single.isCompleted, isTrue);
    },
  );

  testWidgets('opens settings and changes the font', (tester) async {
    final controller = AppSettingsController.inMemory();
    final desktopExperience = _FakeDesktopExperience();
    await tester.pumpWidget(
      GoodDayApp(
        repository: _MemoryRepository(),
        settingsController: controller,
        desktopExperience: desktopExperience,
      ),
    );
    await _flushMicrotasks(tester);

    await tester.tap(find.byKey(const Key('settings-button')));
    await _flushMicrotasks(tester);
    expect(find.text('设置'), findsWidgets);
    expect(find.byKey(const Key('choose-vault-button')), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('launch-at-startup-checkbox')))
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('launch-at-startup-option')));
    await _flushMicrotasks(tester);
    expect(desktopExperience.launchAtStartup, isTrue);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('launch-at-startup-checkbox')))
          .value,
      isTrue,
    );

    await tester.ensureVisible(find.byKey(const Key('font-picker-button')));
    await tester.tap(find.byKey(const Key('font-picker-button')));
    await _flushMicrotasks(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('font-dengxian')),
      280,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('font-dengxian')));
    await _flushMicrotasks(tester);
    expect(controller.settings.font, AppFont.dengXian);
  });

  testWidgets('tray request opens settings and close hides the window', (
    tester,
  ) async {
    final desktopExperience = _FakeDesktopExperience();
    await tester.pumpWidget(
      GoodDayApp(
        repository: _MemoryRepository(),
        settingsController: AppSettingsController.inMemory(),
        desktopExperience: desktopExperience,
      ),
    );
    await _flushMicrotasks(tester);

    desktopExperience.requestSettings();
    await _flushMicrotasks(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('launch-at-startup-option')), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await _flushMicrotasks(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await _flushMicrotasks(tester);
    expect(desktopExperience.hideCount, 1);
  });

  testWidgets('left note navigation switches pages with shared goal labels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await _flushMicrotasks(tester);

    await tester.tap(find.byKey(const Key('nav-plans')));
    await _flushMicrotasks(tester);
    expect(find.text('计划'), findsWidgets);
    await tester.tap(find.byKey(const Key('nav-goals')));
    await _flushMicrotasks(tester);
    expect(find.text('目标'), findsWidgets);

    await tester.tap(find.byKey(const Key('add-goal-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-goal-name')), '深度学习');
    await tester.enterText(
      find.byKey(const Key('new-goal-description')),
      '完成 D2L 学习',
    );
    await tester.tap(find.byKey(const Key('goal-color-2')));
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    final goal = repository.goals.single;
    expect(goal.name, '深度学习');
    expect(goal.description, '完成 D2L 学习');

    expect(find.byKey(const Key('nav-events')), findsNothing);
    await tester.tap(find.byKey(const Key('nav-today')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(const Key('add-task-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-task-field')), '阅读第三章');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _flushMicrotasks(tester);
    final task = repository.tasks.single;
    await tester.tap(find.byKey(Key('task-content-${task.id}')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(Key('task-goal-${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('goal-menu-${goal.id}')));
    await tester.pumpAndSettle();
    expect(repository.tasks.single.goalId, goal.id);

    await tester.tap(find.byKey(const Key('nav-plans')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(const Key('add-plan-button')));
    await _flushMicrotasks(tester);
    await tester.enterText(find.byKey(const Key('new-plan-title')), '完成第三章');
    await tester.tap(find.byKey(const Key('plan-deadline-week')));
    await tester.tap(find.byKey(Key('plan-goal-${goal.id}')));
    await tester.tap(find.text('GOOD DAY'));
    await _flushMicrotasks(tester);

    final plan = repository.plans.single;
    expect(plan.title, '完成第三章');
    expect(plan.goalId, goal.id);
    expect(find.textContaining('%'), findsOneWidget);

    await tester.tap(find.byKey(Key('plan-checkbox-${plan.id}')));
    await _flushMicrotasks(tester);
    expect(repository.plans.single.isCompleted, isTrue);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('edits and deletes plans and goals, then restores from trash', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _MemoryRepository();
    final goal = await repository.addGoal(
      name: '旧目标',
      description: '旧描述',
      colorValue: 0xFFF2B544,
    );
    final plan = await repository.addPlan(
      title: '旧计划',
      deadline: DateTime.now().add(const Duration(days: 7)),
      goalId: goal.id,
    );
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await _flushMicrotasks(tester);

    await tester.tap(find.byKey(const Key('nav-plans')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(Key('edit-plan-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(Key('edit-plan-title-${plan.id}')),
      '新计划',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await _flushMicrotasks(tester);
    expect(repository.plans.single.title, '新计划');

    await tester.tap(find.byKey(Key('delete-plan-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await _flushMicrotasks(tester);
    expect(repository.plans, isEmpty);

    await tester.tap(find.byKey(const Key('nav-goals')));
    await _flushMicrotasks(tester);
    await tester.tap(find.byKey(Key('edit-goal-${goal.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Key('edit-goal-name-${goal.id}')), '新目标');
    await tester.pump(const Duration(milliseconds: 700));
    await _flushMicrotasks(tester);
    expect(repository.goals.single.name, '新目标');

    await tester.tap(find.byKey(Key('delete-goal-${goal.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await _flushMicrotasks(tester);
    expect(repository.goals, isEmpty);

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('trash-button')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('trash-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trash-button')));
    await tester.pumpAndSettle();
    expect(find.text('新计划'), findsOneWidget);
    expect(find.text('新目标'), findsOneWidget);

    await tester.tap(find.byKey(Key('restore-plan-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('restore-goal-${goal.id}')));
    await tester.pumpAndSettle();
    expect(repository.plans.single.title, '新计划');
    expect(repository.goals.single.name, '新目标');
    expect(find.text('垃圾桶是空的'), findsOneWidget);
  });
  testWidgets(
    'immediate navigation saves the task and edited subtask before disposal',
    (tester) async {
      final repository = _MemoryRepository();
      var task = await repository.addTask('原任务');
      task = await repository.addSubtask(task, '原子任务');
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(Key('task-title-${task.id}')),
        '马上切换也要保存',
      );
      await tester.enterText(
        find.byKey(Key('subtask-title-${task.id}-${task.subtasks.single.id}')),
        '子任务也保存',
      );
      await tester.tap(find.byKey(const Key('nav-plans')));
      await tester.pumpAndSettle();
      expect(repository.tasks.single.title, '马上切换也要保存');
      expect(repository.tasks.single.subtasks.single.title, '子任务也保存');
      expect(find.byKey(Key('task-title-${task.id}')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('blank task names are filled and no longer block navigation', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final task = await repository.addTask('原任务');
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(Key('task-title-${task.id}'));
    await tester.tap(find.byKey(Key('task-content-${task.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(field, '   ');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(repository.tasks.single.title, '未命名1');
    expect(tester.widget<TextField>(field).controller!.text, '未命名1');
    expect(find.text('任务内容不能为空'), findsNothing);
    await tester.enterText(field, '');
    await tester.tap(find.byKey(const Key('nav-plans')));
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(repository.tasks.single.title, '未命名1');
    await tester.tap(find.byKey(const Key('nav-today')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-task-button')));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repository.tasks.map((task) => task.title), ['未命名1', '未命名2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default name saved in flight does not overwrite newly typed title',
    (tester) async {
      final repository = _SlowEditRepository();
      final task = await repository.addTask('开始');
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await tester.pumpAndSettle();
      final field = find.byKey(Key('task-title-${task.id}'));
      await tester.enterText(field, '');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump();
      expect(repository.started, isTrue);
      await tester.enterText(field, '新名字要保留');
      repository.gate.complete();
      await tester.pumpAndSettle();
      expect(repository.tasks.single.title, '新名字要保留');
      expect(tester.widget<TextField>(field).controller!.text, '新名字要保留');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed saves keep the editor open and retry allows navigation', (
    tester,
  ) async {
    final repository = _FailingEditRepository();
    final task = await repository.addTask('仍在磁盘的标题');
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('task-content-${task.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Key('task-title-${task.id}')), '失败后也不能丢');
    await tester.tap(find.byKey(const Key('nav-plans')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('task-title-${task.id}')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(Key('task-title-${task.id}')))
          .controller!
          .text,
      '失败后也不能丢',
    );
    expect(repository.tasks.single.title, '仍在磁盘的标题');
    repository.fail = false;
    await tester.tap(find.byKey(const Key('nav-plans')));
    await tester.pumpAndSettle();
    expect(repository.tasks.single.title, '失败后也不能丢');
    expect(find.byKey(Key('task-title-${task.id}')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing during an in-flight save persists the newest revision', (
    tester,
  ) async {
    final repository = _SlowEditRepository();
    final task = await repository.addTask('开始');
    await tester.pumpWidget(
      GoodDayApp(
        repository: repository,
        settingsController: AppSettingsController.inMemory(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('task-content-${task.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Key('task-title-${task.id}')), '第一次编辑');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    expect(repository.started, isTrue);
    await tester.enterText(
      find.byKey(Key('task-title-${task.id}')),
      '保存过程中继续输入',
    );
    await tester.tap(find.byKey(const Key('nav-plans')));
    repository.gate.complete();
    await tester.pumpAndSettle();
    expect(repository.tasks.single.title, '保存过程中继续输入');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hiding the window flushes an edit without waiting for debounce',
    (tester) async {
      final repository = _MemoryRepository();
      final desktop = _FakeDesktopExperience();
      final task = await repository.addTask('关闭前');
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
          desktopExperience: desktop,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('task-content-${task.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(Key('task-title-${task.id}')), '关闭后保留');
      await desktop.hideWindow();
      await tester.pumpAndSettle();
      expect(repository.tasks.single.title, '关闭后保留');
      expect(desktop.hideCount, 1);
    },
  );

  testWidgets(
    'a missing plan deadline prevents navigation and preserves its draft',
    (tester) async {
      final repository = _MemoryRepository();
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-plans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-plan-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-plan-title')),
        '还没选日期的计划',
      );
      await tester.tap(find.byKey(const Key('nav-today')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-plan-title')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('new-plan-title')))
            .controller!
            .text,
        '还没选日期的计划',
      );
      expect(repository.plans, isEmpty);
    },
  );

  testWidgets(
    'midnight refresh and resume move overdue tasks to waiting and preserve history',
    (tester) async {
      var now = DateTime(2026, 9, 8, 23, 59, 55);
      final repository = _RolloverRepository(clock: () => now);
      final desktop = _FakeDesktopExperience();
      await repository.addTask('留到明天');
      await repository.setCompleted(await repository.addTask('昨天完成'), true);
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          settingsController: AppSettingsController.inMemory(),
          desktopExperience: desktop,
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      now = DateTime(2026, 9, 9, 0, 0, 5);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('2026年9月9日 · 周三'), findsOneWidget);
      expect(find.text('留到明天'), findsNothing);
      expect(find.text('昨天完成'), findsNothing);
      expect(dateKey(repository.tasks.first.scheduledDate), '2026-09-08');
      await tester.tap(find.byKey(const Key('task-period-backlog')));
      await tester.pumpAndSettle();
      expect(find.text('留到明天'), findsOneWidget);
      now = DateTime(2026, 9, 11, 8);
      desktop.refreshRequests.value++;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-period-day')));
      await tester.pumpAndSettle();
      expect(find.text('2026年9月11日 · 周五'), findsOneWidget);
      expect(dateKey(repository.tasks.first.scheduledDate), '2026-09-08');
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeDesktopExperience implements DesktopExperience {
  @override
  final ValueNotifier<bool> windowPinned = ValueNotifier(false);
  bool failPin = false;
  @override
  Future<void> setWindowPinned(bool enabled) async {
    if (failPin) throw StateError('pin failed');
    windowPinned.value = enabled;
  }

  @override
  final ValueNotifier<int> openSettingsRequests = ValueNotifier<int>(0);

  @override
  final ValueNotifier<int> refreshRequests = ValueNotifier<int>(0);
  Future<bool> Function()? saveGuard;
  @override
  void setSaveGuard(Future<bool> Function()? guard) => saveGuard = guard;
  bool launchAtStartup = false;
  int hideCount = 0;

  void requestSettings() => openSettingsRequests.value++;

  @override
  Future<void> hideWindow() async {
    if (await (saveGuard?.call() ?? Future.value(true))) hideCount++;
  }

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> setReminderOnTop(bool enabled) async {}

  @override
  Future<bool> showEventReminder(
    GoodDayEvent event,
    DateTime occurrence,
    DateTime now,
    Future<void> Function(Duration? snooze) resolve, {
    int accentRgb = 0x365D46,
  }) async => false;

  @override
  Future<bool> isLaunchAtStartupEnabled() async => launchAtStartup;

  @override
  Future<void> setLaunchAtStartupEnabled(bool enabled) async {
    launchAtStartup = enabled;
  }
}

Future<void> _flushMicrotasks(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

class _MemoryRepository extends VaultRepository {
  _MemoryRepository({DateTime Function()? clock})
    : super(
        Directory('memory-vault'),
        clock: clock ?? () => DateTime(2026, 9, 8, 9, 30),
      );

  final List<GoodDayTask> tasks = [];
  final List<GoodDayGoal> goals = [];
  final List<GoodDayPlan> plans = [];
  final Map<String, GoodDayTask> trashedTasks = {};
  final Map<String, GoodDayPlan> trashedPlans = {};
  final Map<String, GoodDayGoal> trashedGoals = {};
  var _sequence = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<GoodDayTask>> loadTasks() async => List.of(tasks);

  @override
  Future<List<GoodDayGoal>> loadGoals() async => List.of(goals);

  @override
  Future<List<GoodDayPlan>> loadPlans() async => List.of(plans);

  @override
  Future<List<TaskSeries>> loadTaskSeries() async => [];

  @override
  Future<List<GoodDayEvent>> loadEvents() async => [];

  @override
  Future<List<GoodDayTask>> loadTaskReminders() async => List.of(tasks);

  @override
  Future<GoodDayTask> saveTaskOptions({
    required GoodDayTask task,
    required EventRepeat repeat,
    required DateTime? reminderAt,
    int reminderIntervalMinutes = 0,
  }) async => _replace(
    task.copyWith(
      repeat: repeat,
      clearReminder: reminderAt == null,
      reminder: reminderAt == null
          ? null
          : GoodDayEvent(
              id: 'task_${task.id}',
              title: task.title,
              notes: task.notes,
              startsAt: reminderAt,
              intervalMinutes: reminderIntervalMinutes,
              expiresAt: task.period.end(task.scheduledDate),
            ),
    ),
  );

  @override
  Future<GoodDayTask> addPeriodTask(String title, TaskPeriod period) async {
    final task = await addTask(title);
    return _replace(task.copyWith(period: period));
  }

  @override
  Future<GoodDayTask> rescheduleTaskPeriod(
    GoodDayTask task,
    TaskPeriod period,
  ) async => _replace(task.copyWith(period: period, scheduledDate: now));

  @override
  Future<GoodDayTask> addTask(String title) async {
    final now = DateTime(2026, 9, 8, 9, _sequence++);
    final task = GoodDayTask(
      id: 'test_${_sequence.toString()}',
      title: title.trim().isEmpty ? _nextUnnamedTitle() : title,
      createdAt: now,
      scheduledDate: now,
    );
    tasks.add(task);
    return task;
  }

  @override
  Future<GoodDayTask> setCompleted(GoodDayTask task, bool completed) async {
    final updated = task.setCompleted(completed, DateTime(2026, 9, 8, 10));
    final index = tasks.indexWhere((item) => item.id == task.id);
    tasks[index] = updated;
    return updated;
  }

  @override
  Future<GoodDayTask> assignTaskGoal(GoodDayTask task, String? goalId) async {
    return _replace(task.assignGoal(goalId));
  }

  @override
  Future<GoodDayGoal> addGoal({
    required String name,
    required String description,
    required int colorValue,
  }) async {
    final goal = GoodDayGoal(
      id: 'goal_${++_sequence}',
      name: name,
      description: description,
      colorValue: colorValue,
      createdAt: DateTime(2026, 9, 9, 9),
    );
    goals.add(goal);
    return goal;
  }

  @override
  Future<GoodDayPlan> addPlan({
    required String title,
    required DateTime deadline,
    String? goalId,
  }) async {
    final plan = GoodDayPlan(
      id: 'plan_${++_sequence}',
      title: title,
      createdAt: DateTime.now(),
      deadline: deadline,
      goalId: goalId,
    );
    plans.add(plan);
    return plan;
  }

  @override
  Future<GoodDayPlan> setPlanCompleted(GoodDayPlan plan, bool completed) async {
    final updated = plan.setCompleted(completed, DateTime.now());
    final index = plans.indexWhere((item) => item.id == plan.id);
    plans[index] = updated;
    return updated;
  }

  @override
  Future<GoodDayGoal> updateGoal(
    GoodDayGoal goal, {
    required String name,
    required String description,
    required int colorValue,
  }) async {
    final updated = goal.update(
      name: name,
      description: description,
      colorValue: colorValue,
    );
    final index = goals.indexWhere((item) => item.id == goal.id);
    goals[index] = updated;
    return updated;
  }

  @override
  Future<GoodDayPlan> updatePlan(
    GoodDayPlan plan, {
    String? title,
    DateTime? deadline,
    String? goalId,
    bool clearGoal = false,
  }) async {
    final updated = plan.update(
      title: title,
      deadline: deadline,
      goalId: goalId,
      clearGoal: clearGoal,
    );
    final index = plans.indexWhere((item) => item.id == plan.id);
    plans[index] = updated;
    return updated;
  }

  @override
  Future<void> deletePlan(GoodDayPlan plan) async {
    trashedPlans[plan.id] = plan;
    plans.removeWhere((item) => item.id == plan.id);
  }

  @override
  Future<void> deleteGoal(GoodDayGoal goal) async {
    trashedGoals[goal.id] = goal;
    goals.removeWhere((item) => item.id == goal.id);
  }

  @override
  Future<GoodDayTask> updateTaskDetails(
    GoodDayTask task, {
    required String title,
    required String notes,
  }) async {
    if (title.trim().isEmpty) {
      title = RegExp(r'^未命名[1-9][0-9]*$').hasMatch(task.title)
          ? task.title
          : _nextUnnamedTitle();
    }
    return _replace(task.updateDetails(title: title, notes: notes));
  }

  String _nextUnnamedTitle() {
    var number = 1;
    final titles = {
      ...tasks.map((task) => task.title),
      ...trashedTasks.values.map((task) => task.title),
    };
    while (titles.contains('未命名$number')) {
      number++;
    }
    return '未命名$number';
  }

  @override
  Future<GoodDayTask> addSubtask(GoodDayTask task, String title) async {
    final updated = task.addSubtask(
      GoodDaySubtask(id: 'sub_${++_sequence}', title: title),
    );
    return _replace(updated);
  }

  @override
  Future<GoodDayTask> updateSubtask(
    GoodDayTask task,
    String subtaskId, {
    String? title,
    bool? isCompleted,
  }) async {
    return _replace(
      task.updateSubtask(subtaskId, title: title, isCompleted: isCompleted),
    );
  }

  @override
  Future<GoodDayTask> removeSubtask(GoodDayTask task, String subtaskId) async {
    return _replace(task.removeSubtask(subtaskId));
  }

  @override
  Future<void> deleteTask(GoodDayTask task) async {
    trashedTasks[task.id] = task;
    tasks.removeWhere((item) => item.id == task.id);
  }

  @override
  Future<List<TrashItem>> loadTrash() async => [
    for (final task in trashedTasks.values)
      TrashItem(
        type: TrashItemType.task,
        id: task.id,
        title: task.title,
        deletedAt: DateTime(2026, 9, 9),
      ),
    for (final plan in trashedPlans.values)
      TrashItem(
        type: TrashItemType.plan,
        id: plan.id,
        title: plan.title,
        deletedAt: DateTime(2026, 9, 9),
      ),
    for (final goal in trashedGoals.values)
      TrashItem(
        type: TrashItemType.goal,
        id: goal.id,
        title: goal.name,
        deletedAt: DateTime(2026, 9, 9),
      ),
  ];

  @override
  Future<void> restoreTrashItem(TrashItem item) async {
    switch (item.type) {
      case TrashItemType.task:
        tasks.add(trashedTasks.remove(item.id)!);
        return;
      case TrashItemType.plan:
        plans.add(trashedPlans.remove(item.id)!);
        return;
      case TrashItemType.goal:
        goals.add(trashedGoals.remove(item.id)!);
        return;
      case TrashItemType.event:
        return;
    }
  }

  @override
  Future<void> emptyTrash() async {
    trashedTasks.clear();
    trashedPlans.clear();
    trashedGoals.clear();
  }

  GoodDayTask _replace(GoodDayTask updated) {
    final index = tasks.indexWhere((item) => item.id == updated.id);
    tasks[index] = updated;
    return updated;
  }
}

class _FailingEditRepository extends _MemoryRepository {
  bool fail = true;
  @override
  Future<GoodDayTask> updateTaskDetails(
    GoodDayTask task, {
    required String title,
    required String notes,
  }) async {
    if (fail) throw const FileSystemException('模拟磁盘不可写');
    return super.updateTaskDetails(task, title: title, notes: notes);
  }
}

class _SlowEditRepository extends _MemoryRepository {
  final gate = Completer<void>();
  bool started = false;
  @override
  Future<GoodDayTask> updateTaskDetails(
    GoodDayTask task, {
    required String title,
    required String notes,
  }) async {
    if (!started) {
      started = true;
      await gate.future;
    }
    return super.updateTaskDetails(task, title: title, notes: notes);
  }
}

class _RolloverRepository extends _MemoryRepository {
  _RolloverRepository({required super.clock});
}
