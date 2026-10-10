import 'dart:convert';
import 'dart:io';

import '../data/safe_file.dart';

import 'package:path_provider/path_provider.dart';

class VaultLocationStore {
  VaultLocationStore(this.configDirectory, {List<File> legacyFiles = const []})
    : _legacyFiles = List.unmodifiable(legacyFiles);

  final Directory configDirectory;
  final List<File> _legacyFiles;

  static Future<VaultLocationStore> create() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final legacyFiles = <File>[
      _childFile(_childDirectory(supportDirectory, 'Good Day')),
      _childFile(supportDirectory),
    ];

    Directory stableDirectory;
    final userProfile = Platform.environment['USERPROFILE']?.trim();
    if (Platform.isWindows && userProfile != null && userProfile.isNotEmpty) {
      final roamingDirectory = Directory(
        '$userProfile${Platform.pathSeparator}AppData'
        '${Platform.pathSeparator}Roaming',
      );
      stableDirectory = _childDirectory(roamingDirectory, 'Good Day');
      legacyFiles.add(
        _childFile(
          _childDirectory(
            _childDirectory(
              _childDirectory(roamingDirectory, 'com.goodday'),
              'Good Day',
            ),
            'Good Day',
          ),
        ),
      );
    } else {
      stableDirectory = _childDirectory(supportDirectory, 'Good Day');
    }

    return VaultLocationStore(stableDirectory, legacyFiles: legacyFiles);
  }

  File get file => File(
    '${configDirectory.path}${Platform.pathSeparator}vault-location.json',
  );

  Future<Directory?> load() async {
    final current = await _read(file);
    if (current != null) return current;

    for (final legacyFile in _legacyFiles) {
      if (legacyFile.absolute.path.toLowerCase() ==
          file.absolute.path.toLowerCase()) {
        continue;
      }
      final legacy = await _read(legacyFile);
      if (legacy == null) continue;
      await save(legacy);
      return legacy;
    }
    return null;
  }

  Future<Directory?> _read(File source) async {
    if (!await source.exists()) return null;
    try {
      final value = jsonDecode(await source.readAsString());
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
    await SafeFile.write(
      file,
      '${encoder.convert({'vaultPath': vaultDirectory.absolute.path})}\n',
    );
  }

  static Directory _childDirectory(Directory parent, String name) =>
      Directory('${parent.path}${Platform.pathSeparator}$name');

  static File _childFile(Directory parent) =>
      File('${parent.path}${Platform.pathSeparator}vault-location.json');
}
