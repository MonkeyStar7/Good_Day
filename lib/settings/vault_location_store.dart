import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class VaultLocationStore {
  VaultLocationStore(this.configDirectory);

  final Directory configDirectory;

  static Future<VaultLocationStore> create() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return VaultLocationStore(
      Directory('${supportDirectory.path}${Platform.pathSeparator}Good Day'),
    );
  }

  File get file => File(
    '${configDirectory.path}${Platform.pathSeparator}vault-location.json',
  );

  Future<Directory?> load() async {
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) return null;
      final path = value['vaultPath'];
      if (path is! String || path.trim().isEmpty) return null;
      return Directory(path.trim());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> save(Directory vaultDirectory) async {
    await configDirectory.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert({'vaultPath': vaultDirectory.absolute.path})}\n',
      flush: true,
    );
  }
}
