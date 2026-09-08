import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/models/good_day_task.dart';

void main() {
  late Directory temporaryVault;
  late DateTime now;
  late VaultRepository repository;

  setUp(() async {
    temporaryVault = await Directory.systemTemp.createTemp('good_day_vault_');
    now = DateTime(2026, 9, 8, 9, 30);
    repository = VaultRepository(temporaryVault, clock: () => now);
    await repository.initialize();
  });

  tearDown(() async {
    if (await temporaryVault.exists()) {
      await temporaryVault.delete(recursive: true);
    }
  });

  test('Markdown task is the source of truth and Daily stays readable', () async {
    final created = await repository.addTask('写下今天的计划');
    final taskFile = File(
      '${repository.tasksDirectory.path}${Platform.pathSeparator}${created.id}.md',
    );
    final dailyFile = File(
      '${repository.dailyDirectory.path}${Platform.pathSeparator}2026-09-08.md',
    );

    expect(await taskFile.exists(), isTrue);
    expect(await taskFile.readAsString(), contains('status: todo'));
    expect(await dailyFile.readAsString(), contains('- [ ] [写下今天的计划]'));

    final fromDisk = (await repository.loadTasks()).single;
    final completed = await repository.setCompleted(fromDisk, true);
    expect(completed.isCompleted, isTrue);
    expect(await taskFile.readAsString(), contains('status: done'));
    expect(await dailyFile.readAsString(), contains('- [x] [写下今天的计划]'));
    expect(await dailyFile.readAsString(), contains('## 今日完成'));
  });

  test('unfinished tasks roll forward without changing the old Daily file', () async {
    await repository.addTask('跨天任务');
    final oldDaily = File(
      '${repository.dailyDirectory.path}${Platform.pathSeparator}2026-09-08.md',
    );
    final oldContent = await oldDaily.readAsString();

    now = DateTime(2026, 9, 9, 8);
    final rolled = (await repository.loadTasks()).single;

    expect(dateKey(rolled.scheduledDate), '2026-09-09');
    expect(await oldDaily.readAsString(), oldContent);
    expect(
      await File(
        '${repository.dailyDirectory.path}${Platform.pathSeparator}2026-09-09.md',
      ).exists(),
      isTrue,
    );
  });

  test('deleting archives Markdown instead of destroying it', () async {
    final task = await repository.addTask('以后仍然可以找回');
    await repository.deleteTask(task);

    expect(await repository.loadTasks(), isEmpty);
    final archived = File(
      '${repository.archiveDirectory.path}${Platform.pathSeparator}${task.id}.md',
    );
    expect(await archived.exists(), isTrue);
    expect(await archived.readAsString(), contains('status: deleted'));
  });

  test('copies Markdown data to an empty vault without deleting source', () async {
    final task = await repository.addTask('搬到新的数据文件夹');
    final target = await Directory.systemTemp.createTemp('good_day_target_');
    addTearDown(() async {
      if (await target.exists()) await target.delete(recursive: true);
    });

    await repository.copyDataTo(target);
    final copiedRepository = VaultRepository(target, clock: () => now);
    final copiedTasks = await copiedRepository.loadTasks();

    expect(copiedTasks.single.title, task.title);
    expect(await repository.hasVaultData(), isTrue);
    expect(await copiedRepository.hasVaultData(), isTrue);
    expect(
      await File(
        '${repository.tasksDirectory.path}${Platform.pathSeparator}${task.id}.md',
      ).exists(),
      isTrue,
    );
  });

  test('deletes only Good Day managed data after a successful copy', () async {
    await repository.addTask('迁移后清理原数据');
    final unrelated = File(
      '${temporaryVault.path}${Platform.pathSeparator}我的其他文件.txt',
    );
    await unrelated.writeAsString('保留');
    final target = await Directory.systemTemp.createTemp('good_day_move_');
    addTearDown(() async {
      if (await target.exists()) await target.delete(recursive: true);
    });

    await repository.copyDataTo(target);
    await repository.deleteManagedData();

    expect(await repository.hasVaultData(), isFalse);
    expect(await unrelated.exists(), isTrue);
    expect(
      await VaultRepository(target, clock: () => now).hasVaultData(),
      isTrue,
    );
  });
}
