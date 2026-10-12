import 'dart:io';

import 'settings/vault_location_store.dart';

/// Installers configure a first-run location, never migrate an existing vault.
Future<void> configureInstallerVault(
  Directory selected,
  VaultLocationStore store,
) async {
  final existing = await store.load();
  if (existing != null) {
    if (existing.absolute.path.toLowerCase() !=
        selected.absolute.path.toLowerCase()) {
      throw const FormatException('已有数据目录，请在软件设置中迁移数据');
    }
    return;
  }
  if (await store.file.exists()) {
    throw const FormatException('已有的数据目录设置无法读取，请先修复设置');
  }
  await selected.create(recursive: true);
  final probe = File(
    '${selected.path}${Platform.pathSeparator}.goodday-install-$pid.tmp',
  );
  try {
    await probe.writeAsString('Good Day installer write check', flush: true);
    await store.save(selected);
  } finally {
    if (await probe.exists()) await probe.delete();
  }
}
