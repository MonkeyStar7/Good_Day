import 'package:flutter/material.dart';

import 'app_update.dart';
import 'app_version.dart';
import 'app_colors.dart';

class AppUpdatePanel extends StatelessWidget {
  const AppUpdatePanel({super.key, required this.controller});
  final AppUpdateController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final stage = controller.stage;
      final message = switch (stage) {
        UpdateStage.checking => '正在检查更新…',
        UpdateStage.available => '发现新版本 ${controller.release!.version}',
        UpdateStage.downloading =>
          '正在下载 ${(controller.progress * 100).round()}%',
        UpdateStage.installing => '正在退出并安装更新…',
        UpdateStage.current => '当前已是最新版本',
        UpdateStage.failed => controller.error!,
        UpdateStage.idle => '从 GitHub 检查新版',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '版本 $appVersion',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton(
                key: const Key('check-app-update'),
                onPressed: controller.busy ? null : controller.check,
                child: const Text('检查更新'),
              ),
            ],
          ),
          Text(
            message,
            style: TextStyle(fontSize: 12, color: context.appColors.muted),
          ),
          if (stage == UpdateStage.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: controller.progress),
            ),
          if (stage == UpdateStage.available) ...[
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  controller.error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.muted,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('install-app-update'),
                onPressed: controller.update,
                child: const Text('下载并更新'),
              ),
            ),
            Text(
              '更新时会退出软件，安装完成后自动打开。待办和数据位置保留。',
              style: TextStyle(fontSize: 12, color: context.appColors.muted),
            ),
          ],
        ],
      );
    },
  );
}
