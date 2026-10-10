import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/safe_file.dart';
import 'package:good_day/data/vault_backups.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/good_day_task.dart';

void main() {
  late Directory vault;
  late VaultRepository repository;
  late DateTime now;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('good_day_safety_');
    now = DateTime(2026, 10, 10, 23, 59);
    repository = VaultRepository(vault, clock: () => now);
    await repository.initialize();
  });
  tearDown(() async {
    await repository.releaseSession();
    await vault.delete(recursive: true);
  });

  test(
    'safe writes preserve a readonly destination and allow a later retry',
    () async {
      final file = File('${vault.path}/保护中的文件.md');
      await SafeFile.write(file, '完整的原内容');
      if (Platform.isWindows) {
        final protect = await Process.run('attrib', ['+R', file.path]);
        expect(protect.exitCode, 0);
        try {
          await expectLater(
            SafeFile.write(file, '不能覆盖'),
            throwsA(isA<FileSystemException>()),
          );
          expect(await file.readAsString(), '完整的原内容');
        } finally {
          await Process.run('attrib', ['-R', file.path]);
        }
      }
      await Future.wait([
        SafeFile.write(file, '第一次'),
        SafeFile.write(file, '最后一次'),
      ]);
      expect(await file.readAsString(), '最后一次');
      expect(
        (await vault.list().toList()).where(
          (file) => file.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'overlapping stale edits preserve title, completion and both subtasks',
    () async {
      final task = await repository.addTask('旧标题');
      await Future.wait([
        repository.updateTaskDetails(task, title: '新标题', notes: '新备注'),
        repository.setCompleted(task, true),
        repository.addSubtask(task, '第一步'),
        repository.addSubtask(task, '第二步'),
      ]);
      final saved = (await repository.loadTasks()).single;
      expect(saved.title, '新标题');
      expect(saved.notes, '新备注');
      expect(saved.isCompleted, isTrue);
      expect(saved.subtasks.map((task) => task.title), ['第一步', '第二步']);
      final daily = await File('${vault.path}/Daily/2026-10-10.md')
          .readAsString();
      expect(daily, contains('新标题'));
      expect(daily, contains('第二步'));
    },
  );

  test('daily backup runs before rollover and retains the previous daily record', () async {
    final task = await repository.addTask('昨天未完成');
    final yesterday = File('${vault.path}/Daily/2026-10-10.md');
    final originalDaily = await yesterday.readAsString();
    now = DateTime(2026, 10, 11, 8);
    final loaded = await repository.loadTasks();
    expect(dateKey(loaded.single.scheduledDate), '2026-10-11');
    expect(await yesterday.readAsString(), originalDaily);
    final snapshot = (await repository.backups.list()).first;
    final backedUp = await File(
      '${repository.backups.directory.path}/${snapshot.id}/Tasks/${task.id}.md',
    ).readAsString();
    expect(backedUp, contains('scheduled: 2026-10-10'));
    expect(
      await File('${vault.path}/Daily/2026-10-11.md').readAsString(),
      contains('昨天未完成'),
    );
  });

  test('a future task is not pulled forward to today', () async {
    final task = await repository.addTask('下周做');
    final future = task.rollForward(DateTime(2026, 10, 17));
    await SafeFile.write(
      File('${vault.path}/Tasks/${task.id}.md'),
      future.toMarkdown(),
    );
    expect(
      dateKey((await repository.loadTasks()).single.scheduledDate),
      '2026-10-17',
    );
  });

  test('backups retain seven snapshots and restore saves the current state first', () async {
    final task = await repository.addTask('最初版本');
    final selected = await repository.createBackup();
    await repository.updateTaskDetails(task, title: '修改后', notes: '要保留的内容');
    final newer = await repository.addTask('恢复后应从当前列表移除');
    await repository.restoreBackup(selected.id);
    expect((await repository.loadTasks()).single.title, '最初版本');
    final safety = (await repository.backups.list()).firstWhere(
      (backup) => backup.kind == 'before-restore',
    );
    expect(
      await File(
        '${repository.backups.directory.path}/${safety.id}/Tasks/${newer.id}.md',
      ).exists(),
      isTrue,
    );
    await repository.restoreBackup(safety.id);
    final recovered = await repository.loadTasks();
    expect(
      recovered.map((task) => task.title),
      containsAll(['修改后', '恢复后应从当前列表移除']),
    );
    for (var index = 0; index < 9; index++) {
      now = now.add(const Duration(days: 1));
      await repository.loadTasks();
    }
    expect(
      await repository.backups.list(),
      hasLength(VaultBackups.retainedCount),
    );
  });

  test(
    'missing snapshot files abort restoration without changing current data',
    () async {
      final task = await repository.addTask('仍应保留');
      final backup = await repository.createBackup();
      await File(
        '${repository.backups.directory.path}/${backup.id}/Tasks/${task.id}.md',
      ).delete();
      await expectLater(
        repository.restoreBackup(backup.id),
        throwsA(isA<FileSystemException>()),
      );
      expect((await repository.loadTasks()).single.title, '仍应保留');
    },
  );

  test(
    'bad Markdown is reported, left untouched, and can still be backed up',
    () async {
      final bad = File('${vault.path}/Tasks/broken.md');
      await bad.writeAsBytes([0xff, 0xfe, 0x00]);
      expect(await repository.loadTasks(), isEmpty);
      expect(
        repository.unreadableFiles.map((path) => path.replaceAll('\\', '/')),
        contains(bad.path.replaceAll('\\', '/')),
      );
      final backup = await repository.createBackup();
      expect(
        await File(
          '${repository.backups.directory.path}/${backup.id}/Tasks/broken.md',
        ).readAsBytes(),
        [0xff, 0xfe, 0x00],
      );
      expect(await bad.readAsBytes(), [0xff, 0xfe, 0x00]);
    },
  );

  test('changed snapshot content fails its checksum before any live file is touched', () async {
    final task = await repository.addTask('有效的当前数据');
    final backup = await repository.createBackup();
    await File(
      '${repository.backups.directory.path}/${backup.id}/Tasks/${task.id}.md',
    ).writeAsString('被截断的备份');
    await expectLater(
      repository.restoreBackup(backup.id),
      throwsA(isA<FileSystemException>()),
    );
    expect((await repository.loadTasks()).single.title, '有效的当前数据');
  });

  test(
    'backup manifests cannot restore a file outside the managed Vault',
    () async {
      await repository.addTask('不应改变');
      final backup = await repository.createBackup();
      final manifest = File(
        '${repository.backups.directory.path}/${backup.id}/manifest.json',
      );
      final json =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      json['files'] = ['../outside.md'];
      await manifest.writeAsString(jsonEncode(json));
      await expectLater(
        repository.restoreBackup(backup.id),
        throwsA(isA<FileSystemException>()),
      );
      expect((await repository.loadTasks()).single.title, '不应改变');
    },
  );

  test(
    'Windows Vault lock rejects another handle and releases after closing',
    () async {
      if (!Platform.isWindows) return;
      await repository.acquireSession();
      final other = VaultRepository(vault, clock: () => now);
      await expectLater(
        other.acquireSession(),
        throwsA(isA<FileSystemException>()),
      );
      await repository.releaseSession();
      await other.acquireSession();
      await other.releaseSession();
    },
  );
}
