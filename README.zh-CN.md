# Chameleon Ultra GUI（Windows / Android 修复版）

本仓库是 [GameTec-live/ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI) 的 Fork，包含 Windows 桌面修复、Windows BLE 自动连接，以及 Windows / Android 的 PIN 隐私与配对修复。

## 版本对应关系

| 内容 | 版本 / 基线 | 说明 |
| --- | --- | --- |
| 预编译包 | **1.4.0**（tag `1.4`）+ 本 Fork 修复 | Windows 适配已安装的 1.4 引擎；Android 为同一份 Dart 代码 |
| `main` 分支 | 上游当前 main + 同一套修复 | 含 1.4 之后的上游新功能 |
| `fix/windows-ble-window-state` 分支 | tag `1.4` + 本 Fork 修复 | 预编译包对应的源码基线 |

## 预编译包

- Windows 免安装包：`ChameleonUltraGUI-20261124-02-windows.zip`，SHA-256：`7E95B828B62AE0FF1619051817384EF914D3C958B709A3D5DD8CEF4F35E8CE16`
- Android APK（arm64）：`ChameleonUltraGUI-20261124-02-android-arm64.apk`，SHA-256：`257003ef6e2a27e4dd6e800eefbba56b5ae9afe1b5c923b04c29ecf2393659c1`
- Windows 下载：[`prebuilt/ChameleonUltraGUI-20261124-02-windows.zip`](prebuilt/ChameleonUltraGUI-20261124-02-windows.zip) 或 Releases 页面。
- Android 下载：[`prebuilt/ChameleonUltraGUI-20261124-02-android-arm64.apk`](prebuilt/ChameleonUltraGUI-20261124-02-android-arm64.apk) 或 Releases 页面。
- `prebuilt/` 仅保留最新版，旧版包已移除。

Windows 包解压后直接运行 `chameleonultragui.exe`，不会覆盖已安装的 1.4 版；便携版与原版共用配置和卡片数据。Android APK 使用调试证书签名，可直接侧载。

## 本次改动

1. **连接页精简**：删除“默认 BLE 密码”“首次连接可能较慢”“需在系统蓝牙设置里删除设备”等提示；页面只保留一个圆圈和一行状态——未发现设备为“等待设备…”，收到广播并开始连接为“正在连接…”，连接后为“已连接”。设备未开机时不会显示“正在连接”。
2. **PIN 不回显**：设置页的 PIN 输入框改为密码样式且始终为空，只写不读；设备设置解析不再保留 PIN，插件 API 也不再返回；调试日志对 PIN 相关命令整帧脱敏。应用**不把 PIN 写入任何配置文件**，配对凭据由操作系统（Windows 配对库 / Android 蓝牙栈）保存。
3. **在 CCCD 失败时立即配对**：真机日志显示连接（约 380 ms）和发现服务（约 570 ms）都成功，卡在 `setNotifyValue | Write CCCD failed: 2`。现在订阅失败会立刻触发配对，Windows 用自定义 `DeviceInformationCustomPairing` 的 `ProvidePin` 弹窗（失败后 22 ms 内弹出），Android 走系统 `createBond`；不会自动填入默认密码。成功后将 PIN 写入系统安全存储（Windows DPAPI / Android Keystore），下次直接复用；输错、取消或超时会回到可见状态。
4. **自动连接修复**：后台扫描与“记住的上次地址直连”真正并行，直连重试不再阻塞扫描；未开机时直连重试不改变界面状态。Android 发现 BLE 设备后始终自动连接，不再依赖“自动连接第一个设备”开关。
5. **保留原有能力**：Balanced 连接参数、1 秒保活、窗口位置/大小记忆、USB 自动识别均未回退；串口、COM 口和设备地址均未写死。
6. **状态与超时**：连接页只显示 `等待设备… / 正在连接… / 需要输入 PIN / PIN 错误 / 连接失败，重试中…`；每次连接 4–10 秒超时、配对 30 秒超时、PIN 弹窗 30 秒自动关闭，失败会明显回到“连接失败，重试中…”再回到“等待设备…”。PIN 弹窗会先把主窗口置前并置顶，取消后 60 秒内不再反复弹窗。

## 这次真机卡在“正在连接…”的原因

- `19:44:04.311` 连接成功（380 ms），`19:44:04.880` 发现服务成功（569 ms），`19:44:05.125` 订阅失败：`setNotifyValue | Write CCCD failed: 2`。
- 之后每 1.3–1.5 秒重复“连接→发现→订阅失败”，界面一直停在连接中；PIN 框从未出现。
- 原因是 CCCD 需要配对后的加密链路，而旧代码把“检查并请求 PIN”放在握手之后；CCCD 失败使握手永远无法开始，形成死锁。
- 修复后在 `20:15:26.740` 订阅失败，`20:15:26.762` 即弹出 PIN 框（本机日志可见 `pin.pair.start` → `pin.prompt.show`），不再依赖握手。
- 本机 `Get-PnpDevice` 中没有名称含 Chameleon 的配对记录，因此没有删除任何系统蓝牙项。

## 为什么原来的 PIN 设置没起作用

结论：**固件确实会在“BLE 配对”开启时强制 PIN，但修改 PIN / 开关配对后必须重启设备才生效；旧 GUI 又从未发起过配对，所以看起来完全没用。** 具体依据（上游固件 `firmware/application/src/`）：

1. `ble_main.c` 的 `set_ble_connect_key()` 通过 `sd_ble_opt_set(BLE_GAP_OPT_PASSKEY)` 把 6 位 PIN 写入 SoftDevice；它只在启动流程的 `ble_passkey_init()` 中调用一次。
2. GUI 的“保存 PIN”命令只调用 `settings_set_ble_connect_key()` 写 flash，运行时不会更新已经生效的 passkey，**必须重启设备**。
3. 所有 BLE 安全判断读的是启动时快照 `settings_get_ble_pairing_enable_first_load()`；配对开关同样**必须重启**才真正生效。
4. 固件默认 `ble_pairing_enable = false`；关闭时对端发起配对会被回复 `PAIRING_NOT_SUPP`，而 Nordic UART 透传服务本身是开放的，所以不配对也能正常使用，PIN 自然不会出现。
5. 已经绑定过的设备通过白名单和绑定密钥直接加密重连，不会再询问 PIN；要重新验证必须先“清除 BLE 绑定”。
6. 旧 GUI 从未调用系统配对接口，PIN 只影响以后在系统设置里手动配对，与软件连接无关。

## 固件层面还需要做什么

正常使用**不需要刷固件**，只需：

1. 在 GUI 设置里写入 6 位 PIN，并打开“BLE 配对”，保存。
2. **重启变色龙**（断电再开机或按复位），让新 PIN 和配对开关生效。
3. 清除电脑/手机以及设备上的旧绑定（GUI 里的“清除 BLE 绑定”），再重新连接。

如果希望“改 PIN / 开配对后不重启立即生效”，需要修改固件：在 `cmd_processor_set_ble_connect_key()` 中写入配置后同时调用 `set_ble_connect_key(data)`；并把 `settings_get_ble_pairing_enable_first_load()` 改为读取实时值、同步重建 Battery 服务的安全属性和广播白名单。本仓库没有刷写或修改任何设备固件/设置。

## 限制

- BLE 不支持 DFU 固件升级；刷机请使用 USB。
- BLE 需要设备开机且蓝牙广播已启用（固件设置中的 BLE 配对开关）。
- Android 版只做了编译与启动验证；真机配对界面由系统提供，未在本机实测。
- 预编译包基于 1.4.0；直接构建 `main` 会包含 1.4 之后的上游新功能，需要自行重新构建。

## 日志

连接问题请提供 `%TEMP%\chameleon_ble.log`（Windows）。日志包含扫描、连接、发现服务、订阅、握手耗时和错误，**不包含 PIN**；PIN 相关命令的收发帧会被替换为 `<redacted>`。

## 从源码构建

Windows：安装 Flutter、Visual Studio 2022“使用 C++ 的桌面开发”工作负载，然后：

```powershell
flutter pub get
flutter build windows --release
```

Android：安装 JDK 17、Android SDK Platform 37、NDK 28.2，然后：

```powershell
flutter build apk --release
```

## Fork 与许可

本项目从 [GameTec-live/ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI) fork，遵循上游 **GPL-3.0** 许可证；原始 `LICENSE` 与版权声明保留在仓库根目录。修改内容仅涉及 Windows/Android 连接、PIN 配对、窗口状态和界面状态，未改变上游许可条款。
