import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/backup_page.dart';
import 'package:good_day/data/vault_backups.dart';

void main() {
  testWidgets(
    'backup page fits a narrow window and requires confirmation before restoring',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(340, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final backups = [
        VaultBackup(
          id: 'example',
          createdAt: DateTime(2026, 10, 10, 10),
          kind: 'manual',
          files: const ['Tasks/test.md'],
          digests: const {},
        ),
      ];
      var created = 0;
      var restored = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupPage(
            path: r'C:\Users\测试用户\Documents\很长的数据文件夹\Good Day Vault\.goodday\backups',
            onList: () async => backups,
            onCreate: () async {
              created++;
            },
            onRestore: (id) async {
              expect(id, 'example');
              restored++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('create-backup-button')));
      await tester.pumpAndSettle();
      expect(created, 1);
      await tester.tap(find.text('恢复').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(restored, 0);
      await tester.tap(find.text('恢复').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-restore-backup')));
      await tester.pumpAndSettle();
      expect(restored, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed backup creation displays an error and allows another attempt',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupPage(
            path: 'trial',
            onList: () async => [],
            onCreate: () async {
              if (++attempts == 1) throw Exception('磁盘不可写');
            },
            onRestore: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-backup-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('磁盘不可写'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-backup-button')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.textContaining('磁盘不可写'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
