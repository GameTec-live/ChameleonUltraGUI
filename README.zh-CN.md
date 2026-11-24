# Chameleon Ultra GUI（Windows 修复版）

本仓库是 [GameTec-live/ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI) 的 Fork，针对 Windows 桌面版做了四项修复，并附上可直接运行的 Windows 1.4 版免安装包。

## 版本对应关系

| 内容 | 版本 / 基线 | 说明 |
| --- | --- | --- |
| 预编译免安装包 | **1.4.0**（tag `1.4`）+ 本 Fork 修复 | 适配已安装的 1.4 Windows 引擎 |
| `main` 分支 | 上游当前 main + 同一套修复 | 含 1.4 之后的上游新功能 |
| `fix/windows-ble-window-state` 分支 | tag `1.4` + 本 Fork 修复 | 预编译包对应的源码基线 |

## 预编译免安装包

- 文件：[`prebuilt/ChameleonUltraGUI-1.4.0-ble-portable.zip`](prebuilt/ChameleonUltraGUI-1.4.0-ble-portable.zip)
- 发布页：[Releases · Bluetooth](https://github.com/lyx7725/ChameleonUltraGUI/releases/tag/Bluetooth)（同一份压缩包）
- 内容：包内含全部运行文件（`chameleonultragui.exe`、Flutter 引擎、插件 DLL、`data/` 资源），**无需安装原版**。
- 用法：解压后运行 `chameleonultragui.exe`。若已安装 1.4 版，请先完全退出；便携版与原版共用配置与卡片数据，不会覆盖原安装目录。

## 本次改动

1. **修复连接页 UI 卡顿**：自动扫描改为先读取串口元数据，跳过蓝牙和非 USB 串口，避免打开这些端口时阻塞界面。
2. **Windows 蓝牙（BLE）连接**：连接页可发现 `ChameleonUltra-*` / `ChameleonLite-*`，可通过 BLE（Nordic UART 服务）连接；插着 USB 时优先使用 USB。
3. **记住窗口位置 / 大小 / 最大化**：通过 Win32 API 保存并在下次启动时恢复；窗口位置不在任何显示器内时自动回退到默认位置。
4. **连接稳定 / 保活**：Windows 侧改用固件可接受的 Balanced BLE 连接参数；连接期间定时发送轻量指令并保持系统唤醒，断链后自动重连。

## 限制

- BLE 暂不支持 DFU 固件升级；刷机请使用 USB。
- BLE 需要设备开机且蓝牙广播已启用（固件设置中的 BLE 配对开关）。
- 预编译包基于 1.4.0；直接构建 `main` 会包含 1.4 之后的上游新功能，需要自行重新构建。

## 从源码构建（Windows）

1. 安装 Flutter 与 Visual Studio 2022 的“使用 C++ 的桌面开发”工作负载（含 Windows SDK）。
2. 在 `chameleonultragui/` 目录执行：

```powershell
flutter pub get
flutter build windows --release
```

产物位于 `build/windows/x64/runner/Release/`。

## 许可

GPL-3.0，与原项目一致。上游项目：https://github.com/GameTec-live/ChameleonUltraGUI
