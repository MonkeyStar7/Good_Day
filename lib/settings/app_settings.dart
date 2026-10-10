import 'dart:convert';
import 'dart:io';

import '../data/safe_file.dart';
import '../data/vault_backups.dart';

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
  graphite('graphite', '石墨', Color(0xFF343A36)),
  forest('forest', '松绿', Color(0xFF365D46)),
  blueGrey('blue_grey', '雾蓝', Color(0xFF536D7A)),
  warmBrown('warm_brown', '暖棕', Color(0xFF766052));

  const AppAccent(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;

  static AppAccent fromKey(String? key) => values.firstWhere(
    (accent) => accent.key == key,
    orElse: () => AppAccent.forest,
  );
}

class AppSettings {
  const AppSettings({
    this.font = AppFont.appleStyle,
    this.accent = AppAccent.forest,
  });

  final AppFont font;
  final AppAccent accent;

  AppSettings copyWith({AppFont? font, AppAccent? accent}) {
    return AppSettings(font: font ?? this.font, accent: accent ?? this.accent);
  }

  Map<String, Object> toJson() => {'font': font.key, 'accent': accent.key};

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      font: AppFont.fromKey(json['font'] as String?),
      accent: AppAccent.fromKey(json['accent'] as String?),
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
}
