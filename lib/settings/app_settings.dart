import 'dart:convert';
import 'dart:io';

import '../data/safe_file.dart';
import '../data/vault_backups.dart';
import '../app_colors.dart';

import 'package:flutter/material.dart';

enum AppFont {
  appleStyle('apple_style', '苹果风格', 'Inter'),
  microsoftYaHeiUi('microsoft_yahei_ui', '微软雅黑 UI', 'Microsoft YaHei UI'),
  microsoftYaHei('microsoft_yahei', '微软雅黑', 'Microsoft YaHei'),
  dengXian('dengxian', '等线', 'DengXian'),
  segoeUiVariable('segoe_ui_variable', 'Segoe UI', 'Segoe UI Variable');

  const AppFont(this.key, this.label, this.family);

  final String key;
  final String label;
  final String family;

  static AppFont fromKey(String? key) => values.firstWhere(
    (font) => font.key == key,
    orElse: () => AppFont.appleStyle,
  );
}

enum AppAccent {
  white('white', '白色', whiteGlassAccent),
  cloudYellow('cloud_yellow', '云朵黄', cloudYellowAccent),
  graphite('graphite', '石墨', Color(0xFF343A36)),
  forest('forest', '松绿', Color(0xFF365D46)),
  blueGrey('blue_grey', '雾蓝', Color(0xFF536D7A)),
  warmBrown('warm_brown', '暖棕', Color(0xFF766052)),
  ocean('ocean', '海蓝', Color(0xFF346C9B)),
  teal('teal', '青碧', Color(0xFF28756F)),
  lavender('lavender', '暮紫', Color(0xFF746094)),
  rose('rose', '玫瑰', Color(0xFFA2536D)),
  amber('amber', '秋金', Color(0xFF8C692C)),
  coral('coral', '珊瑚', Color(0xFFAE624D));

  const AppAccent(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;
  Color get swatchColor => this == AppAccent.white
      ? Colors.white
      : this == AppAccent.cloudYellow
      ? const Color(0xFFFFF2CA)
      : color;

  static AppAccent fromKey(String? key) => values.firstWhere(
    (accent) => accent.key == key,
    orElse: () => AppAccent.white,
  );
}

enum InterfaceSize {
  small('small', '小', 0.75),
  medium('medium', '中', 1),
  large('large', '大', 1.5);

  const InterfaceSize(this.key, this.label, this.scale);
  final String key;
  final String label;
  final double scale;
  static InterfaceSize fromKey(Object? key) => values.firstWhere(
    (size) => size.key == key,
    orElse: () => InterfaceSize.medium,
  );
}

class AppSettings {
  const AppSettings({
    this.font = AppFont.appleStyle,
    this.accent = AppAccent.white,
    this.interfaceSize = InterfaceSize.medium,
    this.glassTransparency = 0.55,
  });

  final AppFont font;
  final AppAccent accent;
  final InterfaceSize interfaceSize;

  /// Only the background is translucent; text and controls remain opaque.
  final double glassTransparency;

  AppSettings copyWith({
    AppFont? font,
    AppAccent? accent,
    InterfaceSize? interfaceSize,
    double? glassTransparency,
  }) {
    return AppSettings(
      font: font ?? this.font,
      accent: accent ?? this.accent,
      interfaceSize: interfaceSize ?? this.interfaceSize,
      glassTransparency: glassTransparency ?? this.glassTransparency,
    );
  }

  Map<String, Object> toJson() => {
    'font': font.key,
    'accent': accent.key,
    'interfaceSize': interfaceSize.key,
    'glassTransparency': glassTransparency,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      font: AppFont.fromKey(json['font'] as String?),
      accent: AppAccent.fromKey(json['accent'] as String?),
      interfaceSize: InterfaceSize.fromKey(json['interfaceSize']),
      glassTransparency:
          json['glassTransparency'] is num &&
              (json['glassTransparency'] as num).isFinite
          ? (json['glassTransparency'] as num).toDouble().clamp(0, 0.95)
          : 0.55,
    );
  }
}

class AppSettingsStore {
  AppSettingsStore(this.vaultDirectory)
    : _directory = Directory(
        '${vaultDirectory.path}${Platform.pathSeparator}.goodday',
      );

  final Directory _directory;
  final Directory vaultDirectory;

  File get file =>
      File('${_directory.path}${Platform.pathSeparator}settings.json');

  Future<AppSettings> load() async {
    if (!await file.exists()) return const AppSettings();
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
    } on FormatException {
      // Keep the invalid file untouched and fall back to safe defaults.
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    await VaultBackups(vaultDirectory).ensureDaily();
    await _directory.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await SafeFile.write(file, '${encoder.convert(settings.toJson())}\n');
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this.settings, {this.store});

  AppSettingsStore? store;
  AppSettings settings;
  Future<void> Function(InterfaceSize size)? prepareInterfaceSize;
  final _operations = OperationQueue();
  Future<void> get idle => _operations.idle;

  static Future<AppSettingsController> load(Directory vaultDirectory) async {
    final store = AppSettingsStore(vaultDirectory);
    return AppSettingsController(await store.load(), store: store);
  }

  factory AppSettingsController.inMemory() =>
      AppSettingsController(const AppSettings());

  Future<void> reload() => _operations.run(() async {
    settings = await store!.load();
    notifyListeners();
  });

  Future<void> setFont(AppFont font) => _operations.run(() async {
    if (settings.font == font) return;
    final next = settings.copyWith(font: font);
    await store?.save(next);
    settings = next;
    notifyListeners();
  });

  Future<void> setAccent(AppAccent accent) => _operations.run(() async {
    if (settings.accent == accent) return;
    final next = settings.copyWith(accent: accent);
    await store?.save(next);
    settings = next;
    notifyListeners();
  });

  Future<void> useVault(Directory vaultDirectory) => _operations.run(() async {
    final nextStore = AppSettingsStore(vaultDirectory);
    await nextStore.save(settings);
    store = nextStore;
  });

  Future<void> setInterfaceSize(InterfaceSize size) =>
      _operations.run(() async {
        if (settings.interfaceSize == size) return;
        await prepareInterfaceSize?.call(size);
        final next = settings.copyWith(interfaceSize: size);
        await store?.save(next);
        settings = next;
        notifyListeners();
      });

  Future<void> setGlassTransparency(double value) => _operations.run(() async {
    if (!value.isFinite) return;
    final next = settings.copyWith(glassTransparency: value.clamp(0, 0.95));
    if (settings.glassTransparency == next.glassTransparency) return;
    await store?.save(next);
    settings = next;
    notifyListeners();
  });
}
