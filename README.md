# Chameleon Ultra GUI（1.4 修改版）

这是基于上游项目 Chameleon Ultra GUI 1.4 的修改版，用于 Chameleon Ultra / Lite，使用 Flutter 编写，支持 Windows 和 Android。项目遵循 GPL-3.0 许可证。

## 相对上游的改动

- 蓝牙自动连接：程序和页面会持续扫描，设备开机广播后自动连接，不需要手动选择设备；Windows 会记住上次设备并直接尝试连接。
- PIN 配对：Windows 版在 CCCD 需要认证时立即弹出 PIN 输入框，配对成功后继续连接；设置页不再显示 PIN，PIN 也不会写入日志或配置文件。
- 蓝牙稳定性：Windows 使用 Balanced 连接参数，连接期间每秒保活，失败或断线后自动重试。
- USB 优先：检测到 USB 连接时优先使用 USB，蓝牙自动连接不会抢占。
- 串口扫描卡顿修复：Windows 扫描时先检查端口类型，跳过蓝牙和非 USB 串口，避免打开端口阻塞界面。
- 窗口位置记忆：Windows 版保存并恢复窗口位置、大小和最大化状态。
- 界面精简：连接页只保留一行状态提示，删除默认密码等新手提示；首页改为设备状态总览，分区展示设备、当前卡槽、8 个卡槽和最近卡片。

## 自行构建

Windows：

1. 安装 Flutter 3.47 或更新版本。
2. 安装 Visual Studio 2022 的“使用 C++ 的桌面开发”工作负载。
3. 在 `chameleonultragui` 目录执行：

```powershell
flutter pub get
flutter build windows --release
```

Android：

1. 安装 Flutter 3.47 或更新版本、JDK 17、Android SDK Platform 37、NDK 28.2。
2. 在 `chameleonultragui` 目录执行 `flutter pub get`。
3. 构建 arm64 APK：

```powershell
flutter build apk --release --target-platform android-arm64
```

## 注意事项

- 如果设备上已经安装同包名但签名不同的应用，需要先卸载旧应用再安装本版本。
- PIN 由设备固件校验；请在设备设置中开启 BLE 配对并重启设备后再连接。

## 许可

GPL-3.0。上游项目名称为 Chameleon Ultra GUI，原始 LICENSE 和版权声明保留在仓库中。
