import 'app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/vault_backups.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.path,
    required this.onList,
    required this.onCreate,
    required this.onRestore,
  });
  final String path;
  final Future<List<VaultBackup>> Function() onList;
  final Future<void> Function() onCreate;
  final Future<void> Function(String id) onRestore;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<VaultBackup> _backups = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final backups = await widget.onList();
      if (mounted) {
        setState(() {
          _backups = backups;
          _busy = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '无法读取备份：$error';
          _busy = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '操作未完成：$error。请保留当前数据，检查备份列表后重试。';
        });
      }
    }
  }

  Future<void> _restore(VaultBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复这份备份？'),
        content: const Text(
          '应用数据和外观设置会回到备份时的状态。恢复前会先备份当前数据；之后新增的内容不会保留在当前列表中。提醒记录也会还原，可能再次提醒。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-restore-backup'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => widget.onRestore(backup.id), '备份已恢复，恢复前的数据也已备份');
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: context.appColors.paper,
      appBar: AppBar(
        title: const Text('数据备份'),
        backgroundColor: context.appColors.paper,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '每天首次读取或修改数据前自动备份，保留最近 7 份。备份保存在当前 Vault 内；换电脑或防范磁盘损坏，仍需复制整个 Vault 到其他位置。',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 12),
          SelectableText(widget.path, style: const TextStyle(fontSize: 12)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.path)),
              child: const Text('复制备份路径'),
            ),
          ),
          FilledButton(
            key: const Key('create-backup-button'),
            onPressed: _busy ? null : () => _run(widget.onCreate, '已创建备份'),
            child: const Text('立即备份'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Color(0xFF8B3A32))),
            TextButton(
              onPressed: _busy ? null : _reload,
              child: const Text('重新读取'),
            ),
          ],
          if (!_busy && _backups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('暂无完整备份'),
            ),
          for (final backup in _backups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                backup.createdAt.toLocal().toString().split('.').first,
              ),
              subtitle: Text(
                '${switch (backup.kind) {
                  'daily' => '自动备份',
                  'before-restore' => '恢复前备份',
                  _ => '手动备份',
                }} · ${backup.files.length} 个文件',
              ),
              trailing: TextButton(
                onPressed: _busy ? null : () => _restore(backup),
                child: const Text('恢复'),
              ),
            ),
        ],
      ),
    ),
  );
}
