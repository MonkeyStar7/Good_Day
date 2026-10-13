import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/settings/app_settings.dart';
import 'package:good_day/settings/vault_location_store.dart';
import 'package:good_day/reminder_sound.dart';

void main() {
  test(
    'size changes wait for window preparation and retain settings on failure',
    () async {
      final controller = AppSettingsController.inMemory();
      addTearDown(controller.dispose);
      final ready = Completer<void>();
      controller.prepareInterfaceSize = (_) => ready.future;
      final change = controller.setInterfaceSize(InterfaceSize.large);
      await Future<void>.delayed(Duration.zero);
      expect(controller.settings.interfaceSize, InterfaceSize.medium);
      ready.complete();
      await change;
      expect(controller.settings.interfaceSize, InterfaceSize.large);
      controller.prepareInterfaceSize = (_) async =>
          throw StateError('window unavailable');
      await expectLater(
        controller.setInterfaceSize(InterfaceSize.small),
        throwsStateError,
      );
      expect(controller.settings.interfaceSize, InterfaceSize.large);
    },
  );
  test('new installs use the Apple-style font preset by default', () {
    expect(const AppSettings().font, AppFont.appleStyle);
    expect(const AppSettings().accent, AppAccent.white);
    expect(const AppSettings().glassTransparency, 0.55);
    expect(const AppSettings().reminderSound, ReminderSound.none);
    expect(AppSettings.fromJson({}).accent, AppAccent.white);
    expect(AppSettings.fromJson({'accent': 'forest'}).accent, AppAccent.forest);
  });

  test('appearance settings persist inside the vault', () async {
    final vault = await Directory.systemTemp.createTemp('good_day_settings_');
    addTearDown(() async => vault.delete(recursive: true));

    final store = AppSettingsStore(vault);
    const settings = AppSettings(
      font: AppFont.dengXian,
      accent: AppAccent.white,
      interfaceSize: InterfaceSize.large,
      glassTransparency: 0.95,
      reminderSound: ReminderSound.warmKeys,
    );
    await store.save(settings);

    final loaded = await store.load();
    expect(loaded.font, AppFont.dengXian);
    expect(loaded.accent, AppAccent.white);
    expect(loaded.interfaceSize, InterfaceSize.large);
    expect(loaded.glassTransparency, 0.95);
    expect(loaded.reminderSound, ReminderSound.warmKeys);
    expect(await store.file.exists(), isTrue);
  });

  test('old and invalid appearance settings have safe defaults', () {
    expect(AppSettings.fromJson({}).interfaceSize, InterfaceSize.medium);
    expect(AppSettings.fromJson({}).glassTransparency, 0.55);
    expect(
      AppSettings.fromJson({'interfaceSize': 'unknown'}).interfaceSize,
      InterfaceSize.medium,
    );
    expect(
      AppSettings.fromJson({'glassTransparency': 'broken'}).glassTransparency,
      0.55,
    );
    expect(
      AppSettings.fromJson({'glassTransparency': 4}).glassTransparency,
      0.95,
    );
    expect(
      AppSettings.fromJson({'glassTransparency': -1}).glassTransparency,
      0,
    );
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
