import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'safe_file.dart';

class VaultBackup {
  const VaultBackup({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.files,
    required this.digests,
  });
  final String id;
  final DateTime createdAt;
  final String kind;
  final List<String> files;
  final Map<String, String> digests;
}

class VaultBackups {
  VaultBackups(this.vault, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final Directory vault;
  final DateTime Function() _clock;
  static final _queues = <String, OperationQueue>{};
  static int _sequence = 0;
  static const retainedCount = 7;
  static const managedFolders = [
    'Tasks',
    'Plans',
    'Goals',
    'Events',
    'TaskSeries',
    'Daily',
    'Archive',
  ];
  Directory get directory => Directory(
    '${vault.path}${Platform.pathSeparator}.goodday${Platform.pathSeparator}backups',
  );
  OperationQueue get _queue => _queues.putIfAbsent(
    vault.absolute.path.toLowerCase(),
    OperationQueue.new,
  );

  Future<List<VaultBackup>> list() async {
    if (!await directory.exists()) return [];
    final result = <VaultBackup>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = File(
        '${entity.path}${Platform.pathSeparator}manifest.json',
      );
      if (!await manifest.exists()) {
        continue; // Incomplete snapshots are not offered.
      }
      try {
        final json =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        final id = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        final files = (json['files'] as List).cast<String>();
        final digests = (json['digests'] as Map).cast<String, String>();
        if (!RegExp(r'^\d{20}-\d{6}$').hasMatch(id) ||
            files.toSet().length != files.length ||
            digests.length != files.length ||
            files.any(
              (file) =>
                  !RegExp(r'^[0-9a-f]{64}$').hasMatch(digests[file] ?? ''),
            )) {
          continue;
        }
        if (files.any((path) => !_isManaged(path))) continue;
        result.add(
          VaultBackup(
            id: id,
            createdAt: DateTime.parse(json['createdAt'] as String),
            kind: json['kind'] as String,
            files: files,
            digests: digests,
          ),
        );
      } on Object {
        // Do not offer an incomplete or invalid backup for restoration.
      }
    }
    result.sort((a, b) => b.id.compareTo(a.id));
    return result;
  }

  Future<void> ensureDaily() => _queue.run(() async {
    await _recoverPendingRestore();
    final now = _clock();
    final existing = await list();
    if (existing.any(
      (backup) => backup.kind == 'daily' && _sameDay(backup.createdAt, now),
    )) {
      return;
    }
    await _create('daily');
  });

  Future<VaultBackup> createManual() => _queue.run(() async {
    await _recoverPendingRestore();
    return _create('manual');
  });

  File get _restoreJournal => _file(vault, '.goodday/restore-pending.json');

  Future<void> recoverPendingRestore() => _queue.run(_recoverPendingRestore);

  Future<void> _recoverPendingRestore() async {
    if (!await _restoreJournal.exists()) return;
    final journal = jsonDecode(
      await _restoreJournal.readAsString(),
    ) as Map<String, dynamic>;
    final contents = await _readSnapshot(journal['backupId'] as String);
    await _applyContents(contents);
    await _restoreJournal.delete();
  }

  Future<List<String>> _managedFiles() async {
    final files = <String>[];
    for (final folder in managedFolders) {
      final source = Directory('${vault.path}${Platform.pathSeparator}$folder');
      if (!await source.exists()) continue;
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
          final relative = entity.path
              .substring(vault.path.length + 1)
              .replaceAll('\\', '/');
          if (_isManaged(relative)) files.add(relative);
        }
      }
    }
    if (await _file(vault, '.goodday/settings.json').exists()) {
      files.add('.goodday/settings.json');
    }
    files.sort();
    return files;
  }

  Future<VaultBackup> _create(String kind) async {
    final now = _clock();
    final id =
        '${now.microsecondsSinceEpoch.toString().padLeft(20, '0')}-${(_sequence++).toString().padLeft(6, '0')}';
    final destination = Directory(
      '${directory.path}${Platform.pathSeparator}$id',
    );
    await destination.create(recursive: true);
    final files = await _managedFiles();
    final digests = <String, String>{};
    for (final relative in files) {
      final source = _file(vault, relative);
      final target = _file(destination, relative);
      await target.parent.create(recursive: true);
      final bytes = await source.readAsBytes();
      await SafeFile.writeBytes(target, bytes);
      digests[relative] = sha256.convert(bytes).toString();
    }
    await SafeFile.write(
      _file(destination, 'manifest.json'),
      jsonEncode({
        'createdAt': now.toIso8601String(),
        'kind': kind,
        'files': files,
        'digests': digests,
      }),
    );
    final complete = await list();
    for (final old in complete.skip(retainedCount)) {
      // Only directories found under our backup root, with valid manifests.
      await Directory('${directory.path}${Platform.pathSeparator}${old.id}')
          .delete(recursive: true);
    }
    return VaultBackup(
      id: id,
      createdAt: now,
      kind: kind,
      files: files,
      digests: digests,
    );
  }

  Future<void> restore(String id) => _queue.run(() async {
    await _recoverPendingRestore();
    // Validate the entire selected snapshot before touching current data.
    final contents = await _readSnapshot(id);
    final safety = await _create('before-restore');
    // A durable journal makes an interrupted multi-file restore recoverable.
    await SafeFile.write(_restoreJournal, jsonEncode({'backupId': safety.id}));
    try {
      await _applyContents(contents);
      await _restoreJournal.delete();
    } catch (_) {
      // Restore the pre-operation snapshot. If disk access still fails, leave
      // the journal and snapshot intact and block writes until recovery works.
      await _recoverPendingRestore();
      rethrow;
    }
  });

  Future<Map<String, List<int>>> _readSnapshot(String id) async {
    final matches = (await list()).where((backup) => backup.id == id);
    if (matches.isEmpty) throw const FileSystemException('备份不存在或不完整');
    final selected = matches.first;
    final source = Directory(
      '${directory.path}${Platform.pathSeparator}${selected.id}',
    );
    // Read and validate everything before changing any live file. Do not prune
    // the selected snapshot while the safety copy is being created.
    final contents = <String, List<int>>{};
    for (final relative in selected.files) {
      final snapshotFile = _file(source, relative);
      if (await FileSystemEntity.type(snapshotFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException('备份文件缺失，未修改当前数据', snapshotFile.path);
      }
      contents[relative] = await snapshotFile.readAsBytes();
      if (sha256.convert(contents[relative]!).toString() !=
          selected.digests[relative]) {
        throw FileSystemException('备份校验失败，未修改当前数据', snapshotFile.path);
      }
    }
    return contents;
  }

  Future<void> _applyContents(Map<String, List<int>> contents) async {
    for (final entry in contents.entries) {
      final target = _file(vault, entry.key);
      // An unchanged readonly file should not prevent a safe rollback.
      if (await target.exists() &&
          sha256.convert(await target.readAsBytes()) ==
              sha256.convert(entry.value)) {
        continue;
      }
      await SafeFile.writeBytes(target, entry.value);
    }
    for (final relative in await _managedFiles()) {
      if (!contents.containsKey(relative)) {
        await _file(vault, relative).delete();
      }
    }
  }

  static bool _isManaged(String path) {
    if (path.contains('\\') ||
        path
            .split('/')
            .any((part) => part == '..' || part.isEmpty || part == '.')) {
      return false;
    }
    return path == '.goodday/settings.json' ||
        (managedFolders.contains(path.split('/').first) &&
            path.endsWith('.md') &&
            !path.contains(':'));
  }

  static File _file(Directory root, String relative) => File(
    '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
  );
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
