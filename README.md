# Good Day

Good Day 是一个 Markdown-first 的 Windows 日计划应用。界面可以离开，计划文件仍然属于用户。

## Vault

首次启动后，应用会在用户文档目录创建：

```text
Good Day Vault/
├── Tasks/      # 每个活跃任务一个 Markdown
├── Daily/      # 每天的计划与完成记录
└── Archive/    # 从界面删除的任务，仍可找回
```

`Tasks/` 是应用的真实数据源。关闭并重新打开 Good Day 时，任务会直接从这些 Markdown 文件恢复，不依赖数据库。

Daily 文件中的 `goodday:begin` 与 `goodday:end` 标记之间由应用维护；标记外可以在 Obsidian、VS Code 或任意文本编辑器中自由书写，应用不会覆盖。

## 本地开发

```powershell
flutter pub get
flutter test
flutter run -d windows
```
