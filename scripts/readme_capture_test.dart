// Export the real application widgets with demo data, without native capture
// artifacts from transparent Windows surfaces or touching the installed vault.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/main.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/reminder_item.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/settings/app_settings.dart';

void main() {
  testWidgets('export README demo screens from current application', (
    tester,
  ) async {
    await tester.runAsync(() async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(456, 780);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final vault = await Directory.systemTemp.createTemp('goodday_readme_');
      final repository = VaultRepository(vault, clock: () => today)
        ..usesReminderWorkflow = true;
      await repository.initialize();
      final settings = AppSettingsController(
        const AppSettings(
          font: AppFont.microsoftYaHeiUi,
          accent: AppAccent.white,
          glassTransparency: 0.55,
        ),
      );
      final boundary = GlobalKey();
      try {
        for (final entry in {
          'Inter': 'assets/fonts/InterVariable.ttf',
          'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons': 'E:/Dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        }.entries) {
          await (FontLoader(entry.key)..addFont(
                File(entry.value).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
        }
        Future<ReminderItem> add(
          String title,
          int day,
          int hour, {
          String notes = '',
          List<GoodDaySubtask> subtasks = const [],
          bool daily = false,
        }) => repository.saveReminder(
          title: title,
          notes: notes,
          dueAt: today.add(Duration(days: day, hours: hour)),
          rule: ReminderRule(daily ? RepeatUnit.day : RepeatUnit.none),
          enabled: false,
          calendarRepeat: daily,
          subtasks: subtasks,
        );
        await add(
          '复习一章数学',
          0,
          9,
          notes: '专注 30 分钟，先易后难。',
          subtasks: const [
            GoodDaySubtask(id: 'demo_step1', title: '整理错题'),
            GoodDaySubtask(id: 'demo_step2', title: '完成一组练习'),
          ],
        );
        await add('整理项目资料', 0, 15, notes: '把想法记下来，一次做好一件事。');
        await add('阅读 20 分钟', 0, 20, daily: true);
        await add('完成一套练习题', 1, 9, notes: '留一点时间回顾错题。');
        await add('傍晚散步', 2, 18);
        await add('回顾这一周', 4, 20);
        await add('整理本月的阅读笔记', 15, 9);
        Future<void> settle() async {
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 15));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        Future<void> capture(String name) async {
          await settle();
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/images').create(recursive: true);
          await File('docs/images/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFB7D7DB),
                    Color(0xFFE4EDF0),
                    Color(0xFFE9DDD8),
                  ],
                ),
              ),
              child: GoodDayApp(
                repository: repository,
                settingsController: settings,
              ),
            ),
          ),
        );
        await capture('today');
        await tester.tap(find.byKey(const Key('nav-plans')));
        await settle();
        await tester.drag(find.byType(ListView).last, const Offset(0, -430));
        await capture('plans');
        await tester.tap(find.byKey(const Key('settings-button')));
        await capture('settings');
      } finally {
        await tester.pumpWidget(const SizedBox());
        await repository.idle;
        await settings.idle;
        settings.dispose();
        await vault.delete(recursive: true);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  });
}
