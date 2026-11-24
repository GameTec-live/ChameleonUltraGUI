# Chameleon Ultra GUI（Windows 修复版）

本仓库是 [GameTec-live/ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI) 的 Fork，针对 Windows 桌面版做了三项修复，并提供与当前已安装 1.4 版完全对应的预编译免安装包。

## 版本对应关系

| 内容 | 版本 / 基线 | 说明 |
| --- | --- | --- |
| 预编译免安装包 | **1.4.0**（tag `1.4`）+ 本 Fork 修复 | 适配已安装的 1.4 Windows 引擎 |
| `main` 分支 | 上游当前 main + 同一套修复 | 含 1.4 之后的上游新功能 |
| `fix/windows-ble-window-state` 分支 | tag `1.4` + 本 Fork 修复 | 预编译包对应的源码基线 |

预编译包构建环境：Flutter **3.47.9**、Dart **3.13.7**、引擎 `89c39edfdfae2949f6806e4a315c0c08522238b7`（与 1.4 安装版 `flutter_windows.dll` 的 SHA-256 完全一致）。

## 预编译免安装包

- 文件：[`prebuilt/ChameleonUltraGUI-1.4.0-ble-portable.zip`](prebuilt/ChameleonUltraGUI-1.4.0-ble-portable.zip)
- SHA-256：`0e24aa6a7e0a98a78c88428d0ed483def0c367bb57d55ba9d7d292251cf19931`
- 用法：**先完全退出已安装的 1.4 版**，解压后运行 `chameleonultragui.exe`。便携版与原版共用配置与卡片数据，不会覆盖原安装目录。

## 本次改动

1. **修复连接页 UI 卡顿**：自动扫描改为先读取串口元数据，跳过蓝牙 / 非 USB 串口，不再打开它们。此前每 3 秒扫描一次，蓝牙串口（如 COM5）打开一次会阻塞约 5.2 秒，导致界面持续冻结。
2. **Windows 蓝牙（BLE）连接**：连接页可发现 `ChameleonUltra-*` / `ChameleonLite-*`，点击即可通过 BLE 连接（Nordic UART 服务）；插着 USB 时优先使用 USB。实测可连接 Chameleon Ultra，正常读取固件、电量与卡槽信息。
3. **记住窗口位置 / 大小 / 最大化**：通过 Win32 API 保存并在下次启动时恢复；窗口位置不在任何显示器内时自动回退到默认位置。
4. **连接保活**：连接期间每 12 秒发送一次轻量指令（读取电量）并保持系统唤醒；BLE 空闲不再掉线，设备也不会在断连后自动关机。

## 限制

- BLE 暂不支持 DFU 固件升级；刷机请使用 USB。
- BLE 需要设备开机且蓝牙广播已启用（固件设置中的 BLE 配对开关）。
- 预编译包基于 1.4.0；直接构建 `main` 会包含 1.4 之后的上游新功能，需要自行重新构建。

## 从源码构建（Windows）

1. 安装 Flutter 3.47.9 与 Visual Studio 2022 的“使用 C++ 的桌面开发”工作负载（含 Windows SDK）。
2. 在 `chameleonultragui/` 目录执行：

```powershell
flutter pub get
flutter build windows --release
```

产物位于 `build/windows/x64/runner/Release/`。

## 许可

GPL-3.0，与原项目一致。上游项目：https://github.com/GameTec-live/ChameleonUltraGUI
