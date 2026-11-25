# Chameleon Ultra GUI 1.4.1

这是一个用于 Chameleon Ultra / Lite 的图形界面，基于上游项目 Chameleon Ultra GUI 1.4 的修改版，遵循 GPL-3.0 许可证。

## 相对上游的改动

- 蓝牙自动连接：后台持续扫描，设备广播后自动连接；Windows 会记住上次设备并直接尝试。
- USB 优先：Windows 启动先检查 USB，有 USB 变色龙就不启动蓝牙扫描；连接中插入 USB 会取消蓝牙尝试；USB 拔出后约 1 秒恢复蓝牙监听。
- 系统配对：需要 PIN 时使用 Windows 系统配对弹窗，不再使用软件自绘 PIN 框；设置页不显示 PIN，日志不记录 PIN。
- 蓝牙稳定性：Windows 使用 Balanced 连接参数，每秒保活，失败或断线自动重试，并正确释放蓝牙设备。
- 首页：重新设计为设备状态总览，适配深浅色、全部配色和手机窄屏，显示当前卡槽、8 个卡槽和最近卡片。
- Windows 修复：解决连接页串口扫描造成的界面卡顿，记住窗口位置、大小和最大化状态。
- 界面与多语言：精简连接页提示，状态、错误和配对引导全部走多语言，共 27 种语言。
- 电量：未知电量显示“—”，只有真实读到的低于 20% 才标红；握手后短暂重试，不做持续轮询。

## 自己构建

Windows：安装 Flutter 3.47 或更新版本，以及 Visual Studio 2022 的“使用 C++ 的桌面开发”工作负载。

```powershell
flutter pub get
flutter build windows --release
```

Android：安装 Flutter 3.47 或更新版本、JDK 17、Android SDK Platform 37、NDK 28.2。发行签名需要自己准备发行密钥并配置 `android/key.properties`，参考 `android/key.properties.example` 模板。

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## 注意事项

- 如果设备上已经安装同包名但签名不同的应用，需要先卸载旧应用再安装本版本。卸载前请先导出已保存的卡片。
- PIN 由设备固件校验；请在设备设置中开启 BLE 配对并重启设备后再连接。
- 上一版本保存的卡片和配置会保留在应用数据目录，但不同签名版本之间无法直接覆盖安装。

## 许可

GPL-3.0。上游项目名称为 Chameleon Ultra GUI，原始 LICENSE 和版权声明保留在仓库中。
