import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models/good_day_event.dart';
import 'data/safe_file.dart';
import 'reminder_sound.dart';

abstract interface class DesktopExperience {
  ValueListenable<int> get openSettingsRequests;

  ValueListenable<int> get refreshRequests;

  ValueListenable<bool> get windowPinned;

  Future<void> setWindowPinned(bool enabled);

  void setSaveGuard(Future<bool> Function()? guard);

  Future<void> hideWindow();

  Future<void> showWindow();

  Future<void> setReminderOnTop(bool enabled);

  Future<bool> showEventReminder(
    GoodDayEvent event,
    DateTime occurrence,
    DateTime now,
    Future<void> Function(Duration? snooze) resolve, {
    int accentRgb = 0x54606D,
  });

  Future<bool> isLaunchAtStartupEnabled();

  Future<void> setLaunchAtStartupEnabled(bool enabled);
}

class SystemDesktopExperience extends DesktopExperience
    with WindowListener, TrayListener {
  static const _showWindowKey = 'show_window';
  static const _hideWindowKey = 'hide_window';
  static const _openSettingsKey = 'open_settings';
  static const _exitAppKey = 'exit_app';

  final ValueNotifier<int> _openSettingsRequests = ValueNotifier<int>(0);
  final ValueNotifier<int> _refreshRequests = ValueNotifier<int>(0);
  final ValueNotifier<bool> _windowPinned = ValueNotifier(false);
  bool _reminderOnTop = false;
  double interfaceScale = 1;
  double glassTransparency = 0.55;
  ReminderSound reminderSound = ReminderSound.woodTap;
  final _topmostOperations = OperationQueue();
  Future<bool> Function()? _saveGuard;
  static const _lifecycle = MethodChannel('good_day/lifecycle');
  static const _reminder = MethodChannel('good_day/reminder');
  bool _isExiting = false;
  bool _isCheckingExit = false;

  @override
  ValueListenable<int> get openSettingsRequests => _openSettingsRequests;

  @override
  ValueListenable<int> get refreshRequests => _refreshRequests;

  @override
  ValueListenable<bool> get windowPinned => _windowPinned;

  @override
  Future<void> setWindowPinned(bool enabled) =>
      _topmostOperations.run(() async {
        await windowManager.setAlwaysOnTop(enabled || _reminderOnTop);
        _windowPinned.value = enabled;
      });

  @override
  void setSaveGuard(Future<bool> Function()? guard) => _saveGuard = guard;

  Future<void> initialize({bool internalReview = false}) async {
    _lifecycle.setMethodCallHandler((call) async {
      if (call.method == 'resume' || call.method == 'timeChanged') {
        _refreshRequests.value++;
      }
    });
    launchAtStartup.setup(
      appName: internalReview ? 'Good Day Internal' : 'Good Day',
      appPath: Platform.resolvedExecutable,
      packageName: internalReview
          ? 'com.goodday.internal_review'
          : 'com.goodday.good_day',
    );

    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    trayManager.addListener(this);
    final iconPath = File(Platform.resolvedExecutable).parent.uri
        .resolve('app_icon.ico')
        .toFilePath();
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip(internalReview ? 'Good Day 内部试用' : 'Good Day');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _showWindowKey, label: '显示 Good Day'),
          MenuItem(key: _hideWindowKey, label: '隐藏 Good Day'),
          MenuItem.separator(),
          MenuItem(key: _openSettingsKey, label: '打开设置'),
          MenuItem.separator(),
          MenuItem(key: _exitAppKey, label: '退出 Good Day'),
        ],
      ),
    );
  }

  @override
  Future<void> showWindow() async {
    _refreshRequests.value++;
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> setReminderOnTop(bool enabled) =>
      _topmostOperations.run(() async {
        await windowManager.setAlwaysOnTop(enabled || _windowPinned.value);
        _reminderOnTop = enabled;
      });

  @override
  Future<bool> showEventReminder(
    GoodDayEvent event,
    DateTime occurrence,
    DateTime now,
    Future<void> Function(Duration? snooze) resolve, {
    int accentRgb = 0x54606D,
  }) async {
    final finished = Completer<void>();
    var saving = false;
    _reminder.setMethodCallHandler((call) async {
      if (call.method != 'action' || saving || finished.isCompleted) return;
      final minutes = call.arguments;
      if (minutes is! int || ![0, 5, 10, 30].contains(minutes)) return;
      saving = true;
      try {
        await resolve(minutes == 0 ? null : Duration(minutes: minutes));
        await _reminder.invokeMethod<void>('dismiss');
        finished.complete();
      } catch (error) {
        await _reminder.invokeMethod<void>('error', {
          'message': '未能保存，请重试：$error',
        });
      } finally {
        saving = false;
      }
    });
    try {
      await _reminder.invokeMethod<void>('show', {
        'accentRgb': accentRgb,
        'interfaceScale': interfaceScale,
        'glassTransparency': glassTransparency,
        'sound': reminderSound.key,
        'title': event.title,
        'time': '事件时间：${eventDateTimeLabel(occurrence)}',
        'date':
            '${occurrence.year} 年 ${occurrence.month} 月 ${occurrence.day} 日',
        'clock':
            '${occurrence.hour.toString().padLeft(2, '0')}:${occurrence.minute.toString().padLeft(2, '0')}',
        'notes': event.notes,
      });
      await finished.future;
      return true;
    } on MissingPluginException {
      return false; // Flutter-only previews have no Windows runner.
    } finally {
      _reminder.setMethodCallHandler(null);
    }
  }

  @override
  Future<void> hideWindow() async {
    if (!await (_saveGuard?.call() ?? Future.value(true))) return;
    await windowManager.hide();
  }

  Future<void> openSettings() async {
    await showWindow();
    _openSettingsRequests.value++;
  }

  @override
  Future<bool> isLaunchAtStartupEnabled() => launchAtStartup.isEnabled();

  @override
  Future<void> setLaunchAtStartupEnabled(bool enabled) =>
      enabled ? launchAtStartup.enable() : launchAtStartup.disable();

  Future<void> exitApp() async {
    if (_isExiting || _isCheckingExit) return;
    _isCheckingExit = true;
    try {
      if (!await (_saveGuard?.call() ?? Future.value(true))) {
        await showWindow();
        return;
      }
    } finally {
      _isCheckingExit = false;
    }
    _isExiting = true;
    trayManager.removeListener(this);
    await trayManager.destroy();
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<bool> installUpdate(File installer) async {
    if (_isExiting || _isCheckingExit) return false;
    if (!await (_saveGuard?.call() ?? Future.value(true))) return false;
    final appDirectory = File(Platform.resolvedExecutable).parent;
    final root = appDirectory.parent;
    if (appDirectory.uri.pathSegments
                .where((p) => p.isNotEmpty)
                .last
                .toLowerCase() !=
            'app' ||
        !await File('${root.path}${Platform.pathSeparator}unins000.exe')
            .exists()) {
      throw const FileSystemException('请使用安装包安装 Good Day 后再进行应用内更新');
    }
    // 1.4.13+ installers wait for this process to exit before touching App.
    await Process.start(installer.path, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/SP-',
      '/GOODDAYUPDATE=1',
      '/GOODDAYWAITPID=$pid',
      '/DIR=${root.path}',
    ], mode: ProcessStartMode.detached);
    await exitApp();
    return true;
  }

  @override
  void onWindowFocus() => _refreshRequests.value++;

  @override
  void onWindowClose() async {
    if (!_isExiting) await hideWindow();
  }

  @override
  void onTrayIconMouseDown() async {
    await showWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case _showWindowKey:
        await showWindow();
        return;
      case _hideWindowKey:
        await hideWindow();
        return;
      case _openSettingsKey:
        await openSettings();
        return;
      case _exitAppKey:
        await exitApp();
        return;
    }
  }
}
