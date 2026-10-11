import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

abstract interface class DesktopExperience {
  ValueListenable<int> get openSettingsRequests;

  ValueListenable<int> get refreshRequests;

  void setSaveGuard(Future<bool> Function()? guard);

  Future<void> hideWindow();

  Future<void> showWindow();

  Future<void> setReminderOnTop(bool enabled);

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
  Future<bool> Function()? _saveGuard;
  static const _lifecycle = MethodChannel('good_day/lifecycle');
  bool _isExiting = false;
  bool _isCheckingExit = false;

  @override
  ValueListenable<int> get openSettingsRequests => _openSettingsRequests;

  @override
  ValueListenable<int> get refreshRequests => _refreshRequests;

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
      windowManager.setAlwaysOnTop(enabled);

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
