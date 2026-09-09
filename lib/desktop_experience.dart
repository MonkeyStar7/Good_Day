import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

abstract interface class DesktopExperience {
  ValueListenable<int> get openSettingsRequests;

  Future<void> hideWindow();

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
  bool _isExiting = false;

  @override
  ValueListenable<int> get openSettingsRequests => _openSettingsRequests;

  Future<void> initialize() async {
    launchAtStartup.setup(
      appName: 'Good Day',
      appPath: Platform.resolvedExecutable,
      packageName: 'com.goodday.good_day',
    );

    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    trayManager.addListener(this);
    final iconPath = File(Platform.resolvedExecutable).parent.uri
        .resolve('app_icon.ico')
        .toFilePath();
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Good Day');
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

  Future<void> showWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hideWindow() => windowManager.hide();

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
    if (_isExiting) return;
    _isExiting = true;
    trayManager.removeListener(this);
    await trayManager.destroy();
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

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
