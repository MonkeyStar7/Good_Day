import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/main.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/models/reminder_item.dart';
import 'package:good_day/settings/app_settings.dart';

void main() {
  testWidgets(
    'compact subtasks and equal themed history filters preserve interaction',
    (tester) async {
      await tester.runAsync(() async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(456, 820);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final vault = await Directory.systemTemp.createTemp('goodday_polish_');
        final now = DateTime(2026, 10, 12, 8);
        final repository = VaultRepository(vault, clock: () => now)
          ..usesReminderWorkflow = true;
        await repository.initialize();
        final settings = AppSettingsController.inMemory();
        final boundary = GlobalKey();
        Future<void> settle() async {
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }

        try {
          final parent = await repository.saveReminder(
            title: '主任务',
            notes: '',
            dueAt: DateTime(2026, 10, 12, 9),
            rule: const ReminderRule(RepeatUnit.none),
            enabled: false,
            subtasks: const [GoodDaySubtask(id: 'child', title: '子任务')],
          );
          final plain = await repository.saveReminder(
            title: '没有子任务',
            notes: '',
            dueAt: DateTime(2026, 10, 12, 9),
            rule: const ReminderRule(RepeatUnit.none),
            enabled: false,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: GoodDayApp(
                repository: repository,
                settingsController: settings,
                clock: () => now,
              ),
            ),
          );
          await settle();
          final parentCircle = tester.getCenter(
            find.byKey(Key('reminder-complete-${parent.id}')),
          );
          final childCircle = tester.getCenter(
            find.descendant(
              of: find.byKey(const Key('reminder-subtask-child')),
              matching: find.byType(Checkbox),
            ),
          );
          expect(childCircle.dy - parentCircle.dy, lessThanOrEqualTo(38));
          final plainRow = tester.getRect(
            find.byKey(Key('reminder-row-${plain.id}')),
          );
          final plainCircle = tester.getCenter(
            find.byKey(Key('reminder-complete-${plain.id}')),
          );
          // Hovering the circular checkbox must not tint the whole task row.
          Future<List<int>> sample(Offset point) async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final offset =
                (point.dy.floor() * image.width + point.dx.floor()) * 4;
            final pixel = bytes.sublist(offset, offset + 4);
            image.dispose();
            return pixel;
          }

          final probe = Offset(plainRow.right - 58, plainCircle.dy);
          final before = await sample(probe);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(plainCircle);
          await tester.pumpAndSettle();
          expect(await sample(probe), before);
          await mouse.removePointer();
          expect(
            plainCircle.dy - plainRow.top,
            closeTo(plainRow.bottom - plainCircle.dy, 0.1),
          );
          await tester.tap(find.byKey(const Key('reminder-subtask-child')));
          await settle();
          expect(
            (await repository.loadReminders())
                .firstWhere((item) => item.id == parent.id)
                .subtasks
                .single
                .isCompleted,
            isTrue,
          );
          await tester.tap(find.byKey(const Key('nav-history')));
          await settle();
          final completed = find.byKey(const Key('history-filter-completed'));
          final incomplete = find.byKey(const Key('history-filter-incomplete'));
          expect(tester.getSize(completed), tester.getSize(incomplete));
          expect(tester.getSize(completed).height, 50);
          Text label(Finder button) => tester.widget<Text>(
            find.descendant(of: button, matching: find.byType(Text)),
          );
          expect(label(completed).style!.fontSize, 17);
          expect(label(incomplete).style!.fontSize, 17);
          final material = tester.widget<Material>(
            find.ancestor(of: completed, matching: find.byType(Material)).first,
          );
          final color = material.color!;
          expect((color.r - color.b).abs(), lessThan(0.03));
          await tester.tap(incomplete);
          await settle();
          expect(find.text('主任务'), findsOneWidget);
          expect(find.text('没有子任务'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await repository.idle;
          settings.dispose();
          await vault.delete(recursive: true);
        }
      });
    },
  );
}
