import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/main.dart';
import 'package:good_day/edit_safety.dart';
import 'package:good_day/models/reminder_item.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/settings/app_settings.dart';

Future<void> settle(WidgetTester tester, VaultRepository repository) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await Future.sync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> openReminderOptions(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('reminder-enabled')));
  await tester.pumpAndSettle();
  if (!tester
      .widget<SwitchListTile>(find.byKey(const Key('reminder-enabled')))
      .value) {
    await tester.tap(find.byKey(const Key('reminder-enabled')));
  }
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('reminder-options-dialog')), findsNothing);
  expect(find.byKey(const Key('reminder-date')), findsOneWidget);
  expect(find.text('未完成时再次提醒'), findsNothing);
}

Future<void> applyReminderOptions(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  late Directory vault;
  late VaultRepository repository;
  final now = DateTime(2026, 10, 12, 8);
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('goodday_redesign_ui_');
    repository = VaultRepository(vault, clock: () => now)
      ..usesReminderWorkflow = true;
    await repository.initialize();
  });
  tearDown(() async => vault.delete(recursive: true));

  for (final width in [400.0, 340.0]) {
    testWidgets('simplified reminder workflow renders and saves at $width', (
      tester,
    ) async {
      await tester.runAsync(() async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 720);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        const capture = bool.fromEnvironment('CAPTURE_UI');
        if (capture) {
          await Future.sync(() async {
            final inter = FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
            await inter.load();
            for (final entry in {
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'E:/Dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
            }.entries) {
              final file = File(entry.value);
              if (await file.exists()) {
                final loader = FontLoader(entry.key)
                  ..addFont(
                    file.readAsBytes().then(
                      (bytes) => ByteData.sublistView(bytes),
                    ),
                  );
                await loader.load();
              }
            }
          });
        }
        await Future.sync(() async {
          await repository.addTask('旧的今日任务');
          await repository.addPlan(
            title: '旧的阶段计划',
            deadline: DateTime(2026, 12, 1),
          );
          await repository.addGoal(
            name: '考研',
            description: '原目标保留',
            colorValue: 0xFF789A7A,
          );
        });
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: GoodDayApp(
              repository: repository,
              clock: () => now,
              settingsController: AppSettingsController.inMemory(),
            ),
          ),
        );
        await settle(tester, repository);
        Future<void> inspect(String name) async {
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
          if (capture) {
            await Future.sync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/redesign-ui-preview')
                ..createSync(recursive: true);
              await File('${directory.path}/${width.toInt()}-$name.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }

        expect(find.byKey(const Key('today-heading')), findsOneWidget);
        expect(find.text('上午'), findsOneWidget);
        expect(find.text('下午'), findsOneWidget);
        expect(find.text('今晚'), findsOneWidget);
        expect(find.byKey(const Key('task-period-week')), findsNothing);
        expect(find.text('旧的今日任务'), findsNothing);
        await inspect('01-empty-today');
        // Empty space at the right of the heading must be clickable too.
        final morningHeader = tester.getRect(
          find.byKey(const Key('add-reminder-morning')),
        );
        await tester.tapAt(morningHeader.centerRight - const Offset(8, 0));
        await settle(tester, repository);
        expect(find.byKey(const Key('reminder-date')), findsNothing);
        expect(find.byKey(const Key('reminder-repeat')), findsNothing);
        expect(find.text('所属目标'), findsNothing);
        expect(find.text('添加待办事项名称'), findsOneWidget);
        expect(find.byIcon(Icons.add), findsOneWidget);
        expect(
          find.byKey(const Key('reminder-state-indicator')),
          findsOneWidget,
        );
        await tester.enterText(find.byKey(const Key('reminder-title')), '复习数学');
        await tester.enterText(
          find.byKey(const Key('reminder-notes')),
          '先整理错题',
        );
        await tester.ensureVisible(
          find.byKey(const Key('add-reminder-subtask')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-reminder-subtask')));
        await tester.pumpAndSettle();
        final subtaskInput = find.byWidgetPredicate(
          (widget) =>
              widget is TextFormField &&
              widget.key.toString().contains('subtask-title-'),
        );
        await tester.enterText(subtaskInput, '第一套试卷');
        await inspect('00-inline-editor');
        await tester.ensureVisible(
          find.byKey(const Key('todo-repeat-enabled')),
        );
        await tester.tap(find.byKey(const Key('todo-repeat-enabled')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reminder-repeat')));
        await tester.pumpAndSettle();
        expect(find.text('每天'), findsNWidgets(2));
        final menu = find.byType(Scrollable).last;
        expect(tester.getSize(menu).height, lessThanOrEqualTo(240));
        await inspect('01-repeat-menu');
        final customRepeatOption = find.descendant(
          of: menu,
          matching: find.text('自定义'),
        );
        await tester.scrollUntilVisible(
          customRepeatOption,
          120,
          scrollable: menu,
        );
        await tester.pumpAndSettle();
        await tester.tap(customRepeatOption);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('custom-repeat-interval')),
          '5',
        );
        await tester.tap(find.byType(DropdownButton<RepeatUnit>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('天').last);
        await tester.pumpAndSettle();
        final number = tester.getRect(
          find.byKey(const Key('custom-repeat-interval-box')),
        );
        final unit = tester.getRect(
          find.byKey(const Key('custom-repeat-unit')),
        );
        expect(number.height, unit.height);
        expect(number.top, unit.top);
        expect((number.center.dy - unit.center.dy).abs(), lessThan(1));
        expect(unit.left - number.right, inInclusiveRange(0, 15));
        expect(find.text('一次'), findsOneWidget);

        await openReminderOptions(tester);
        expect(find.text('09:00'), findsOneWidget);
        expect(find.byTooltip('2026年10月12日'), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('reminder-date'))).center.dy,
          tester.getRect(find.byKey(const Key('reminder-time'))).center.dy,
        );
        await tester.ensureVisible(find.byKey(const Key('reminder-time')));
        await tester.tap(find.byKey(const Key('reminder-time')));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoPicker), findsNWidgets(2));
        await inspect('02-date-time-editor');
        await tester.ensureVisible(find.byKey(const Key('early-reminder')));
        await tester.tap(find.byKey(const Key('early-reminder')));
        await tester.pumpAndSettle();
        final leadMenu = find.byType(Scrollable).last;
        final customLeadOption = find.descendant(
          of: leadMenu,
          matching: find.text('自定义'),
        );
        await tester.scrollUntilVisible(
          customLeadOption,
          120,
          scrollable: leadMenu,
        );
        await tester.pumpAndSettle();
        await tester.tap(customLeadOption);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('custom-lead-amount')),
          '20',
        );
        final leadNumber = tester.getRect(
          find.byKey(const Key('custom-lead-amount-box')),
        );
        final leadUnit = tester.getRect(
          find.byKey(const Key('custom-lead-unit')),
        );
        expect(leadNumber.top, leadUnit.top);
        expect(leadNumber.height, leadUnit.height);
        double textBaseline(Finder finder) {
          final box = tester.renderObject<RenderBox>(finder);
          return box
              .localToGlobal(
                Offset(
                  0,
                  box.getDryBaseline(
                    BoxConstraints.tight(box.size),
                    TextBaseline.alphabetic,
                  )!,
                ),
              )
              .dy;
        }

        await inspect('03-custom-early');
        for (final pair in [('custom-lead-amount', 'custom-lead-unit')]) {
          final editable = find.descendant(
            of: find.byKey(Key(pair.$1)),
            matching: find.byType(EditableText),
          );
          final unitText = find.descendant(
            of: find.byKey(Key(pair.$2)),
            matching: find.text('分钟'),
          );
          expect(
            (textBaseline(editable) - textBaseline(unitText)).abs(),
            lessThanOrEqualTo(1),
            reason:
                '${pair.$1}: editable=${textBaseline(editable)}, unit=${textBaseline(unitText)}',
          );
        }
        await inspect('03-custom-early');
        await applyReminderOptions(tester);
        await tester.ensureVisible(find.byKey(const Key('save-reminder')));
        await tester.tap(find.byKey(const Key('save-reminder')));
        await settle(tester, repository);
        final records = await Future.sync(() => repository.loadReminders());
        expect(records, hasLength(1));
        expect(records.single.dueAt, DateTime(2026, 10, 12, 9));
        expect(records.single.early!.amount, 20);
        expect(records.single.rule.unit, RepeatUnit.day);
        expect(records.single.rule.interval, 5);
        expect(find.text('复习数学'), findsOneWidget);
        expect(find.text('先整理错题'), findsOneWidget);
        expect(find.text('第一套试卷'), findsOneWidget);
        expect(records.single.subtasks.single.title, '第一套试卷');
        expect(find.byKey(const Key('next-reminder-morning')), findsOneWidget);
        expect(find.byIcon(Icons.add), findsNothing);
        // The subtask add icon is visible only inside the editor.
        await inspect('04-filled-today');
        await tester.tap(find.byKey(const Key('next-reminder-morning')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('add-reminder-subtask')), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('reminder-title')))
              .controller!
              .text,
          isEmpty,
        );
        await tester.ensureVisible(find.byKey(const Key('cancel-reminder')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cancel-reminder')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav-plans')));
        await settle(tester, repository);
        expect(find.byKey(const Key('scheduled-heading')), findsOneWidget);
        expect(find.text('今天 · 10月12日'), findsOneWidget);
        expect(find.text('明天 · 10月13日'), findsOneWidget);
        expect(find.text('后天 · 10月14日'), findsOneWidget);
        expect(find.text('复习数学'), findsWidgets);
        expect(find.text('旧的阶段计划'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('add-reminder-date-2026-10-18')),
          120,
        );
        expect(
          find.byKey(const Key('add-reminder-date-2026-10-18')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('add-reminder-date-2026-10-19')),
          findsNothing,
        );
        await inspect('05-scheduled');
        await tester.scrollUntilVisible(
          find.byKey(const Key('schedule-month-2026-11')),
          160,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('schedule-month-2026-11')));
        await tester.pumpAndSettle();
        await inspect('06-expanded-month');
        await openReminderOptions(tester);
        expect(find.byTooltip('2026年11月1日'), findsOneWidget);
        expect(find.text('09:00'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('cancel-reminder')));
        await tester.tap(find.byKey(const Key('cancel-reminder')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav-history')));
        await settle(tester, repository);
        await tester.tap(find.text('未完成'));
        await tester.pumpAndSettle();
        expect(find.text('旧的今日任务'), findsOneWidget);
        expect(find.text('旧的阶段计划'), findsOneWidget);
        expect(find.text('复习数学'), findsOneWidget);
        await inspect('07-preserved-history');
        expect(find.byKey(const Key('nav-goals')), findsNothing);
        expect(find.text('考研'), findsNothing);
        expect((await repository.loadGoals()).single.name, '考研');
        await tester.tap(find.byKey(const Key('nav-today')));
        await settle(tester, repository);
        await tester.tap(find.byKey(const Key('add-reminder-afternoon')));
        await tester.pumpAndSettle();
        await openReminderOptions(tester);
        expect(find.text('15:00'), findsOneWidget);
        await applyReminderOptions(tester);
        await tester.ensureVisible(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminder-editor')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('add-reminder-tonight')),
        );
        await tester.tap(find.byKey(const Key('add-reminder-tonight')));
        await tester.pumpAndSettle();
        await openReminderOptions(tester);
        expect(find.text('20:00'), findsOneWidget);
        await applyReminderOptions(tester);
        await tester.ensureVisible(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminder-editor')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await settle(tester, repository);
      });
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
  testWidgets(
    'inline details keep subtasks visible and delete directly into trash',
    (tester) async {
      await tester.runAsync(() async {
        final item = await repository.saveReminder(
          title: '整理资料',
          notes: '打印笔记',
          dueAt: now.add(const Duration(hours: 1)),
          rule: ReminderRule.presets['不重复']!,
          enabled: false,
          subtasks: const [GoodDaySubtask(id: 'part', title: '检查页码')],
        );
        await tester.pumpWidget(
          GoodDayApp(
            repository: repository,
            clock: () => now,
            settingsController: AppSettingsController.inMemory(),
          ),
        );
        await settle(tester, repository);
        expect(find.text('打印笔记'), findsOneWidget);
        expect(find.text('检查页码'), findsOneWidget);
        await tester.tap(find.byKey(const Key('reminder-subtask-part')));
        await settle(tester, repository);
        expect(
          (await repository.loadReminders()).single.subtasks.single.isCompleted,
          isTrue,
        );
        await tester.tap(find.byKey(Key('reminder-row-${item.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminder-date')), findsNothing);
        expect(find.byKey(const Key('delete-reminder')), findsOneWidget);
        expect(find.byKey(const Key('add-reminder-subtask')), findsOneWidget);
        expect(
          find.byKey(const Key('reminder-state-indicator')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('add-reminder-subtask')), findsOneWidget);
        expect(find.byKey(const Key('delete-reminder')), findsOneWidget);
        await openReminderOptions(tester);
        final scope = EditScope.of(
          tester.element(find.byKey(const Key('reminder-editor'))),
        )!;
        expect(
          await scope.flush(),
          isTrue,
          reason: 'Inline reminder edits save with the task',
        );
        await settle(tester, repository);
        expect((await repository.loadReminders()).single.enabled, isTrue);
        await tester.tap(find.byKey(Key('reminder-row-${item.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete-reminder')));
        await settle(tester, repository);
        expect(await repository.loadReminders(), isEmpty);
        expect((await repository.loadTrash()).single.title, '整理资料');
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await settle(tester, repository);
      });
    },
  );

  testWidgets('new reminder is saved before navigating away from the editor', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        GoodDayApp(
          repository: repository,
          clock: () => now,
          settingsController: AppSettingsController.inMemory(),
        ),
      );
      await settle(tester, repository);
      await tester.tap(find.byKey(const Key('add-reminder-morning')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reminder-title')), '离开也要保存');
      await tester.tap(find.byKey(const Key('nav-plans')));
      await settle(tester, repository);
      expect(find.byKey(const Key('scheduled-heading')), findsOneWidget);
      final records = await Future.sync(() => repository.loadReminders());
      expect(records.single.title, '离开也要保存');
      await tester.pumpWidget(const SizedBox());
      await settle(tester, repository);
    });
  });

  testWidgets(
    'an untouched empty editor closes when the tray save guard flushes',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          GoodDayApp(
            repository: repository,
            clock: () => now,
            settingsController: AppSettingsController.inMemory(),
          ),
        );
        await settle(tester, repository);
        await tester.tap(find.byKey(const Key('add-reminder-morning')));
        await tester.pumpAndSettle();
        final scope = EditScope.of(
          tester.element(find.byKey(const Key('reminder-editor'))),
        )!;
        expect(await scope.flush(), isTrue);
        await settle(tester, repository);
        expect(find.byKey(const Key('reminder-editor')), findsNothing);
        expect(await repository.loadReminders(), isEmpty);
        await tester.pumpWidget(const SizedBox());
        await settle(tester, repository);
      });
    },
  );

  testWidgets(
    'changing the date moves the same reminder into tomorrow without duplication',
    (tester) async {
      await tester.runAsync(() async {
        final item = await repository.saveReminder(
          title: '调整日期',
          notes: '',
          dueAt: DateTime(2026, 10, 12, 9),
          rule: ReminderRule.presets['不重复']!,
          enabled: false,
        );
        await tester.pumpWidget(
          GoodDayApp(
            repository: repository,
            clock: () => now,
            settingsController: AppSettingsController.inMemory(),
          ),
        );
        await settle(tester, repository);
        await tester.tap(find.byKey(Key('reminder-row-${item.id}')));
        await tester.pumpAndSettle();
        await openReminderOptions(tester);
        await tester.tap(find.byKey(const Key('reminder-date')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('13').last);
        await tester.tap(find.text('确定').last);
        await tester.pumpAndSettle();
        await applyReminderOptions(tester);
        await tester.ensureVisible(find.byKey(const Key('save-reminder')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-reminder')));
        await settle(tester, repository);
        expect(find.text('调整日期'), findsNothing);
        final records = await repository.loadReminders();
        expect(records, hasLength(1));
        expect(records.single.id, item.id);
        expect(records.single.dueAt, DateTime(2026, 10, 13, 9));
        await tester.tap(find.byKey(const Key('nav-plans')));
        await settle(tester, repository);
        expect(find.text('调整日期'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await settle(tester, repository);
      });
    },
  );

  testWidgets(
    'on the next day unfinished reminders stay overdue and completions stay in history',
    (tester) async {
      await tester.runAsync(() async {
        var time = now;
        final store = VaultRepository(vault, clock: () => time)
          ..usesReminderWorkflow = true;
        await store.saveReminder(
          title: '昨天没完成',
          notes: '',
          dueAt: DateTime(2026, 10, 12, 9),
          rule: ReminderRule.presets['不重复']!,
          enabled: false,
        );
        final done = await store.saveReminder(
          title: '昨天已完成',
          notes: '',
          dueAt: DateTime(2026, 10, 12, 15),
          rule: ReminderRule.presets['不重复']!,
          enabled: false,
        );
        await store.completeReminder(done, true);
        await tester.pumpWidget(
          GoodDayApp(
            repository: store,
            clock: () => time,
            settingsController: AppSettingsController.inMemory(),
          ),
        );
        await settle(tester, store);
        time = DateTime(2026, 10, 13, 8);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester, store);
        expect(find.text('2026年10月13日 · 周二'), findsOneWidget);
        expect(find.text('已过期'), findsOneWidget);
        expect(find.text('昨天没完成'), findsOneWidget);
        expect(find.text('昨天已完成'), findsNothing);
        await tester.tap(find.byKey(const Key('nav-history')));
        await settle(tester, store);
        expect(find.text('昨天已完成'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await settle(tester, store);
      });
    },
  );
}
