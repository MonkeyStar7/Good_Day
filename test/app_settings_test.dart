import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/settings/app_settings.dart';
import 'package:good_day/settings/vault_location_store.dart';

void main() {
  test('appearance settings persist inside the vault', () async {
    final vault = await Directory.systemTemp.createTemp('good_day_settings_');
    addTearDown(() async => vault.delete(recursive: true));

    final store = AppSettingsStore(vault);
    const settings = AppSettings(
      font: AppFont.dengXian,
      accent: AppAccent.forest,
    );
    await store.save(settings);

    final loaded = await store.load();
    expect(loaded.font, AppFont.dengXian);
    expect(loaded.accent, AppAccent.forest);
    expect(await store.file.exists(), isTrue);
  });

  test('selected vault location persists outside the vault', () async {
    final config = await Directory.systemTemp.createTemp('good_day_config_');
    final vault = await Directory.systemTemp.createTemp('good_day_location_');
    addTearDown(() async {
      await config.delete(recursive: true);
      await vault.delete(recursive: true);
    });

    final store = VaultLocationStore(config);
    await store.save(vault);

    expect((await store.load())!.absolute.path, vault.absolute.path);
  });

  test('legacy vault location migrates to the stable config file', () async {
    final root = await Directory.systemTemp.createTemp('good_day_migration_');
    final legacyConfig = Directory(
      '${root.path}${Platform.pathSeparator}legacy',
    );
    final stableConfig = Directory(
      '${root.path}${Platform.pathSeparator}stable',
    );
    final vault = Directory('${root.path}${Platform.pathSeparator}vault');
    addTearDown(() async => root.delete(recursive: true));

    final legacyStore = VaultLocationStore(legacyConfig);
    await legacyStore.save(vault);

    final stableStore = VaultLocationStore(
      stableConfig,
      legacyFiles: [legacyStore.file],
    );
    final migrated = await stableStore.load();

    expect(migrated!.absolute.path, vault.absolute.path);
    expect(await stableStore.file.exists(), isTrue);

    await legacyStore.file.delete();
    expect((await stableStore.load())!.absolute.path, vault.absolute.path);
  });
}
