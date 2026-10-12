# Good Day

一个把数据保存在本机 Markdown 文件中的 Windows 待办工具。

## 下载

当前版本 **1.4.11**，适用于 Windows 10／11 64 位，无需安装开发环境。

- [下载安装包](https://github.com/MonkeyStar7/Good_Day/releases/download/v1.4.11/Good-Day-1.4.11-windows-x64-setup.exe)
- [下载免安装版](https://github.com/MonkeyStar7/Good_Day/releases/download/v1.4.11/Good-Day-1.4.11-windows-x64.zip)
- [版本与校验文件](https://github.com/MonkeyStar7/Good_Day/releases/latest)

## 可以做什么

- **今天**：按上午、下午、今晚记录待办，添加备注和子任务，勾选完成。
- **计划**：按日期查看、添加待办，展开本月其他日期和后续月份。
- **提醒**：设置日期、滚轮时间和提前提醒；支持每分钟、每小时、每天、工作日、周末、每周、每两周、每月、每三个月、每六个月、每年或自定义重复。
- **历史**：查看已完成、未完成记录，搜索内容；删除的事项可从垃圾桶恢复。
- **桌面使用**：托盘后台提醒、窗口置顶、开机启动、主题色与字体选择。
- **外观**：75%／100%／150% 整体缩放，白色默认主题；毛玻璃背景透明度可调 0%～95%，默认 55%。
- **数据**：本机保存，支持选择／迁移数据目录、备份与恢复。

## 怎么使用

运行安装包，只需选择一个主目录。默认在当前用户的 `AppData\Local\Programs\Good Day`，也可以自定义；文件夹名称不随系统语言改变。

```text
Good Day/
├── App/   程序
└── MD/    首次安装的数据、设置和备份
```

打开软件，点击上午、下午、今晚或计划日期的标题行添加；已有事项下面的虚线圆圈可继续添加。名称下面填写备注，用“添加子任务”的小加号拆分任务。打开“提醒我”设置提醒，点击圆圈完成待办。

关闭窗口后软件留在托盘继续提醒；需要彻底关闭时，在托盘右键选择“退出”。电脑关机或程序退出时无法弹窗，重新启动后会补此前错过的提醒；新设为过去时间的提醒仅标红。

**升级**：先从托盘退出，再运行新版安装包。安装包自动沿用主目录和当前数据位置，无需重新选择，待办、设置及备份保留。旧版或已迁移到其他位置的数据继续留在原位置；需要更换数据位置时，在软件设置中迁移。卸载仅移除程序，保留数据目录。

免安装版解压后运行 `good_day.exe`；首次使用默认数据位置为“文档”中的 `Good Day\MD`，可在设置中更改。

## 从源码构建

准备 Flutter Windows 开发环境，然后运行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

使用 `scripts/package-windows.ps1` 制作免安装包；安装 [Inno Setup 6](https://jrsoftware.org/isdl.php) 后运行 `scripts/package-installer.ps1 -Compiler "安装目录\ISCC.exe"` 制作安装包。
