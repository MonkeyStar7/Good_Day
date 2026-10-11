import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/desktop_experience.dart';
import 'package:good_day/events_page.dart';
import 'package:good_day/main.dart';
import 'package:good_day/models/good_day_event.dart';
import 'package:good_day/models/good_day_goal.dart';
import 'package:good_day/models/good_day_plan.dart';
import 'package:good_day/models/good_day_task.dart';
import 'package:good_day/settings/app_settings.dart';

void main() {
  testWidgets(
    'date and 24-hour time inputs save the selected schedule at 340',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(340, 720);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      GoodDayEvent? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => EventEditorDialog(
                    now: DateTime(2026, 10, 11, 9),
                    onSave: (event) async {
                      saved = event;
                    },
                  ),
                ),
                child: const Text('设置事件'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('设置事件'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), '下午开会');
      await tester.tap(find.byKey(const Key('event-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-time')));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(inputs.at(0), '14');
      await tester.enterText(inputs.at(1), '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('save-event')));
      await tester.pumpAndSettle();
      expect(saved!.startsAt, DateTime(2026, 10, 12, 14, 30));
    },
  );

  for (final width in [340.0, 400.0]) {
    testWidgets(
      'event editor validates, keeps failed input, saves a repeat at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 720);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        var fail = true;
        GoodDayEvent? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => EventEditorDialog(
                      now: DateTime(2026, 10, 11, 9),
                      onSave: (event) async {
                        if (fail) throw const FileSystemException('模拟不可写');
                        saved = event;
                      },
                    ),
                  ),
                  child: const Text('打开编辑'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开编辑'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-event')));
        await tester.pumpAndSettle();
        expect(find.text('请填写事件名称'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('event-title')), '每周整理资料');
        await tester.ensureVisible(find.byKey(const Key('event-repeat')));
        await tester.tap(find.byKey(const Key('event-repeat')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('每周').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('event-reminder-minutes')),
        );
        await tester.enterText(
          find.byKey(const Key('event-reminder-minutes')),
          '15',
        );
        await tester.tap(find.byKey(const Key('save-event')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('event-save-error')));
        await tester.pumpAndSettle();
        expect(find.textContaining('输入已保留'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('event-title')))
              .controller!
              .text,
          '每周整理资料',
        );
        expect(tester.takeException(), isNull);
        fail = false;
        await tester.tap(find.byKey(const Key('save-event')));
        await tester.pumpAndSettle();
        expect(find.byType(EventEditorDialog), findsNothing);
        expect(saved!.repeat, EventRepeat.weekly);
        expect(saved!.reminderMinutes, 15);
        expect(saved!.startsAt, DateTime(2026, 10, 11, 10));
      },
    );

    testWidgets(
      'reminder cannot dismiss silently and retries failed snooze at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 720);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        var fail = true;
        Duration? snoozed;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => EventReminderDialog(
                      event: GoodDayEvent(
                        id: 'example',
                        title: '马上参加会议',
                        notes: '带上笔记本',
                        startsAt: DateTime(2026, 10, 11, 10),
                      ),
                      occurrence: DateTime(2026, 10, 11, 10),
                      now: DateTime(2026, 10, 11, 9, 50),
                      onResolve: (delay) async {
                        if (fail) throw const FileSystemException('模拟不可写');
                        snoozed = delay;
                      },
                    ),
                  ),
                  child: const Text('提醒'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('提醒'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byType(EventReminderDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('snooze-5')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminder-save-error')), findsOneWidget);
        expect(tester.takeException(), isNull);
        fail = false;
        await tester.tap(find.byKey(const Key('snooze-5')));
        await tester.pumpAndSettle();
        expect(find.byType(EventReminderDialog), findsNothing);
        expect(snoozed, const Duration(minutes: 5));
      },
    );
  }

  testWidgets(
    'home creates events, protects open drafts, and preserves task navigation',
    (tester) async {
      final store = _EventRepository();
      final desktop = _Desktop();
      await tester.pumpWidget(
        GoodDayApp(
          repository: store,
          settingsController: AppSettingsController.inMemory(),
          desktopExperience: desktop,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-events')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), '下午开会');
      expect(await desktop.guard!(), isFalse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-event')));
      await tester.pumpAndSettle();
      expect(store.events.single.title, '下午开会');
      expect(find.text('下午开会'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-today')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-task-button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background timer brings the window forward, snoozes and deduplicates focus',
    (tester) async {
      var now = DateTime(2026, 10, 11, 9, 59);
      final store = _EventRepository(clock: () => now);
      store.events.add(
        GoodDayEvent(
          id: 'meeting',
          title: '十点开会',
          startsAt: DateTime(2026, 10, 11, 10),
        ),
      );
      final desktop = _Desktop();
      await tester.pumpWidget(
        GoodDayApp(
          repository: store,
          clock: () => now,
          settingsController: AppSettingsController.inMemory(),
          desktopExperience: desktop,
        ),
      );
      await tester.pumpAndSettle();
      expect(desktop.shows, 0);
      now = DateTime(2026, 10, 11, 10);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(desktop.shows, 1);
      expect(desktop.onTop, isTrue);
      expect(find.text('十点开会'), findsOneWidget);
      desktop.refreshRequests.value++;
      desktop.refreshRequests.value++;
      await tester.pumpAndSettle();
      expect(desktop.shows, 1);
      await tester.tap(find.byKey(const Key('snooze-5')));
      await tester.pumpAndSettle();
      expect(store.events.single.snoozedUntil, DateTime(2026, 10, 11, 10, 5));
      expect(desktop.onTop, isFalse);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(desktop.shows, 1);
      now = DateTime(2026, 10, 11, 10, 5);
      desktop.refreshRequests.value++;
      await tester.pumpAndSettle();
      expect(desktop.shows, 2);
      await tester.tap(find.byKey(const Key('acknowledge-reminder')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(desktop.shows, 2);
      expect(store.events.single.enabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'event pages render without overflow at the minimum desktop width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(340, 720);
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
          final font = FontLoader('Microsoft YaHei UI')
            ..addFont(
              File('C:/Windows/Fonts/msyh.ttc')
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes)),
            );
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              File(
                'E:/Dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await icons.load();
        });
      }
      final store = _EventRepository();
      store.events.add(
        GoodDayEvent(
          id: 'weekly',
          title: '每周整理学习笔记',
          notes: '回顾本周内容',
          startsAt: DateTime(2026, 10, 12, 19, 30),
          repeat: EventRepeat.weekly,
          reminderMinutes: 10,
        ),
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: GoodDayApp(
            repository: store,
            settingsController: AppSettingsController.inMemory(),
            desktopExperience: _Desktop(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-events')));
      await tester.pumpAndSettle();
      Future<void> inspect(String name) async {
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final bitmap = await boundary.toImage(pixelRatio: 2);
            final bytes = await bitmap.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory('build/ui-preview').createSync(recursive: true);
            await File('build/ui-preview/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            bitmap.dispose();
          });
        }
      }

      await inspect('events-340');
      await tester.tap(find.byKey(const Key('edit-event-weekly')));
      await tester.pumpAndSettle();
      await inspect('events-editor-340');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _Desktop implements DesktopExperience {
  @override
  final ValueNotifier<int> openSettingsRequests = ValueNotifier(0);
  @override
  final ValueNotifier<int> refreshRequests = ValueNotifier(0);
  Future<bool> Function()? guard;
  int shows = 0;
  bool onTop = false;
  @override
  void setSaveGuard(Future<bool> Function()? value) => guard = value;
  @override
  Future<void> showWindow() async {
    shows++;
  }

  @override
  Future<void> setReminderOnTop(bool enabled) async {
    onTop = enabled;
  }

  @override
  Future<void> hideWindow() async {}
  @override
  Future<bool> isLaunchAtStartupEnabled() async => false;
  @override
  Future<void> setLaunchAtStartupEnabled(bool enabled) async {}
}

class _EventRepository extends VaultRepository {
  _EventRepository({DateTime Function()? clock})
    : super(
        Directory('unused-event-memory'),
        clock: clock ?? () => DateTime(2026, 10, 11, 9),
      );
  final List<GoodDayEvent> events = [];
  @override
  Future<List<GoodDayTask>> loadTasks() async => [];
  @override
  Future<List<GoodDayGoal>> loadGoals() async => [];
  @override
  Future<List<GoodDayPlan>> loadPlans() async => [];
  @override
  Future<List<GoodDayEvent>> loadEvents() async => List.of(events);
  void _replace(GoodDayEvent event) {
    events.removeWhere((item) => item.id == event.id);
    events.add(event);
  }

  @override
  Future<GoodDayEvent> saveEvent(GoodDayEvent draft) async {
    final event = draft.id.isEmpty
        ? GoodDayEvent(
            id: 'new_event',
            title: draft.title,
            notes: draft.notes,
            startsAt: draft.startsAt,
            repeat: draft.repeat,
            reminderMinutes: draft.reminderMinutes,
            enabled: draft.enabled,
          )
        : draft;
    _replace(event);
    return event;
  }

  @override
  Future<GoodDayEvent?> prepareEventReminder(String id, DateTime now) async {
    final event = events.singleWhere((event) => event.id == id);
    final occurrence = event.dueOccurrence(now);
    if (occurrence == null) return null;
    final claimed = event.pending(occurrence);
    _replace(claimed);
    return claimed;
  }

  @override
  Future<void> resolveEventReminder(
    String id,
    DateTime occurrence, {
    DateTime? snoozeUntil,
  }) async {
    _replace(
      events
          .singleWhere((event) => event.id == id)
          .resolve(occurrence, snoozeUntil: snoozeUntil),
    );
  }
}
