import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/installer_bootstrap.dart';
import 'package:good_day/settings/vault_location_store.dart';

void main() {
  late Directory root;
  late VaultLocationStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('goodday_installer_');
    store = VaultLocationStore(Directory('${root.path}/config'));
  });
  tearDown(() async => root.delete(recursive: true));
  test('first installation saves a custom Unicode data directory', () async {
    final data = Directory('${root.path}/自定义资料 文件夹');
    await configureInstallerVault(data, store);
    expect((await store.load())!.path, data.absolute.path);
    expect(await data.exists(), isTrue);
    expect(await data.list().toList(), isEmpty);
  });
  test('upgrade preserves configuration bytes and existing Markdown', () async {
    final data = Directory('${root.path}/original')..createSync();
    final record = File('${data.path}/keep.md')..writeAsStringSync('# 原数据');
    await store.save(data);
    final before = await store.file.readAsBytes();
    await configureInstallerVault(data, store);
    expect(await store.file.readAsBytes(), before);
    expect(await record.readAsString(), '# 原数据');
    await expectLater(
      configureInstallerVault(Directory('${root.path}/other'), store),
      throwsFormatException,
    );
    expect(await store.file.readAsBytes(), before);
  });
  test(
    'invalid existing configuration is kept rather than overwritten',
    () async {
      await store.configDirectory.create();
      await store.file.writeAsString('invalid original config');
      await expectLater(
        configureInstallerVault(Directory('${root.path}/new'), store),
        throwsFormatException,
      );
      expect(await store.file.readAsString(), 'invalid original config');
    },
  );
}
