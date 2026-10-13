# README 截图

这三张图来自当前 Good Day 的真实 Flutter 界面组件，使用独立的学习、阅读和计划示例数据。截图采用白色主题、55% 透明度及浅色渐变背景，不包含个人待办，也不通过拼接修改功能或布局。

Windows 原生透明窗口捕获存在叠影，因此由 `scripts/readme_capture_test.dart` 导出 2 倍分辨率 PNG。渐变背景用于说明视觉风格，实际 Windows 毛玻璃效果取决于桌面背景与系统环境。

- `today.png`：今天、备注和子任务。
- `plans.png`：未来日期和每日重复待办。
- `settings.png`：整体缩放、透明度、主题色和静音。

在 Windows 开发环境中重新导出：

```powershell
flutter test --no-pub scripts/readme_capture_test.dart
```

脚本默认使用本机当天日期，依赖 Windows 微软雅黑 UI 字体及 `E:/Dev/flutter` 的 Material Icons 字体文件。使用其他 Flutter 安装位置时调整脚本中的字体路径。运行时只写入临时示例数据和 `docs/images`，不访问安装版的数据位置。
