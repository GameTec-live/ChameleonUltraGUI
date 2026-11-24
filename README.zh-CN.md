# Chameleon Ultra GUI（Windows 修复版）

本仓库是 [GameTec-live/ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI) 的 Fork，针对 Windows 桌面版做了四项修复，并附上可直接运行的 Windows 1.4 版免安装包。

## 版本对应关系

| 内容 | 版本 / 基线 | 说明 |
| --- | --- | --- |
| 预编译免安装包 | **1.4.0**（tag `1.4`）+ 本 Fork 修复 | 适配已安装的 1.4 Windows 引擎 |
| `main` 分支 | 上游当前 main + 同一套修复 | 含 1.4 之后的上游新功能 |
| `fix/windows-ble-window-state` 分支 | tag `1.4` + 本 Fork 修复 | 预编译包对应的源码基线 |

## 预编译免安装包

请到 [Releases](https://github.com/lyx7725/ChameleonUltraGUI/releases) 页面下载 `ChameleonUltraGUI-1.4.0-ble3-portable.zip`。

仓库内也提供同一文件：[`prebuilt/ChameleonUltraGUI-1.4.0-ble3-portable.zip`](prebuilt/ChameleonUltraGUI-1.4.0-ble3-portable.zip)，SHA-256：`53eac79cb128fd82407bd71d2e073a36cef8759a086dbed9dd04fa0e2691bbd3`。

- 内容：包内含全部运行文件（`chameleonultragui.exe`、Flutter 引擎、插件 DLL、`data/` 资源），**无需安装原版**。
- 用法：解压后运行 `chameleonultragui.exe`。若已安装 1.4 版，请先完全退出；便携版与原版共用配置与卡片数据，不会覆盖原安装目录。

## 本次改动

1. **修复连接页 UI 卡顿**：自动扫描改为先读取串口元数据，跳过蓝牙和非 USB 串口，避免打开这些端口时阻塞界面。
2. **Windows 蓝牙（BLE）自动连接**：应用启动后只要未连接就在后台持续扫描广播；任何时候按下变色龙按键，发现 `ChameleonUltra-*` / `ChameleonLite-*`（名称或 Nordic UART 服务 UUID）后立即自动连接，不需要停留在连接页或点击刷新。插着 USB 时优先使用 USB。
3. **记住窗口位置 / 大小 / 最大化**：通过 Win32 API 保存并在下次启动时恢复；窗口位置不在任何显示器内时自动回退到默认位置。
4. **连接稳定 / 保活**：Windows 侧使用固件可接受的 Balanced BLE 连接参数；连接前停止扫描并清理旧状态，连接/发现服务/订阅/握手失败会自动退避重试，手动连接与自动重连串行执行；扫描被系统停掉或出错会自动重启，失败或断链后自动恢复持续扫描。连接期间每秒发送轻量保活指令并保持系统唤醒。每个阶段（扫描/连接/发现服务/订阅/握手）都会写入 `%TEMP%\chameleon_ble.log`（带时间戳、异步写盘，不影响 UI），其中 `watch.timing` 记录从第一次收到广播到握手成功的毫秒数。

## 限制

- BLE 暂不支持 DFU 固件升级；刷机请使用 USB。
- BLE 需要设备开机且蓝牙广播已启用（固件设置中的 BLE 配对开关）。
- 预编译包基于 1.4.0；直接构建 `main` 会包含 1.4 之后的上游新功能，需要自行重新构建。

## 日志

遇到连接问题时，请把 `%TEMP%\chameleon_ble.log`（一般在 `C:\Users\<用户名>\AppData\Local\Temp\chameleon_ble.log`）发给我。日志包含每次扫描、连接、发现服务、订阅和握手的耗时与错误信息，以及 `watch.timing`（第一次收到广播到握手成功的毫秒数），不包含卡片数据。

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
