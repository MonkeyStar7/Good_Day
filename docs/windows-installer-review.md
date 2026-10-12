# Windows 安装与升级

安装包由 `installer/good-day.iss` 和 Inno Setup 6 编译，为当前用户安装，无需管理员权限。

首次安装可选择程序和 Markdown 数据位置。程序默认当前用户的 `AppData\Local\Programs\Good Day`，数据默认文档目录下的 `Good Day Vault`。数据与程序目录相互独立，避免卸载和替换程序影响数据。

固定 AppId 用于沿用程序目录。每次安装直接读取软件当前的 `vault-location.json`，因此通过软件迁移数据后，下一次升级会使用迁移后的位置。已有数据的位置在安装向导中只读，迁移通过软件设置完成。

安装前检查目标程序的运行锁，要求先从托盘退出，避免终止未保存的编辑。旧的免安装版本首次使用安装包时，选择原程序位置；已有数据位置可以自动识别。无效位置设置会阻止安装，原文件保留。

安装完成后，程序以隐藏配置模式校验并保存首次数据位置；升级不重写已有配置，不覆盖 Markdown。卸载仅删除安装的程序文件、快捷方式和卸载记录，保留数据与目录设置。

## 验证

```powershell
scripts/package-windows.ps1
scripts/package-installer.ps1 -Compiler "Inno Setup 6\ISCC.exe" -Validation
scripts/validate-installer.ps1 -Installer "build\releases\installer-validation\Good-Day-1.4.4-windows-x64-setup.exe"
scripts/package-installer.ps1 -Compiler "Inno Setup 6\ISCC.exe"
```

验证版使用单独的 AppId、名称及临时用户配置，不修改个人数据。自动验收覆盖首次安装、中文与空格路径、记住程序位置、数据迁移后升级、运行保护、无效配置保护、卸载保留数据及个人配置不变。

应用的 162 项完整测试、安装相关和界面检查、原生提醒窗口测试、静态分析与格式检查通过。正式包同时提供 EXE 安装包、ZIP 免安装包和 SHA-256 校验文件。
