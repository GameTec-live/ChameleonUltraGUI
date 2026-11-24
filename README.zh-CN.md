# Chameleon Ultra GUI（Windows / Android 修改版）

这是一个用于 Chameleon Ultra / Lite 的图形界面，基于上游 Chameleon Ultra GUI，使用 Flutter 编写，支持 Windows 和 Android。

## 相对上游的改动

- 蓝牙自动连接：程序打开后在后台扫描，设备按键开机即可自动连接；记住上次设备并并行直连。
- PIN 配对：CCCD 需要认证时立即请求配对；Windows 使用自定义 PIN 弹窗，Android 使用系统配对；PIN 只写不读，不写入日志和配置文件，配对成功后由系统安全存储复用。
- 连接稳定性：使用固件支持的 Balanced 连接参数，每秒保活，避免设备因空闲自动关机；连接失败会显示状态并自动重试。
- 窗口位置记忆：保存并恢复窗口位置、大小和最大化状态。
- 卡顿修复：扫描时跳过蓝牙和非 USB 串口，避免打开端口阻塞界面。
- 界面精简：连接页只保留状态提示，删除默认密码等新手提示。

## 自行构建

需要 Flutter 3.47 或更新版本。

Windows：安装 Visual Studio 2022 的“使用 C++ 的桌面开发”工作负载，然后执行：

```powershell
flutter pub get
flutter build windows --release
```

Android：安装 JDK 17、Android SDK Platform 37 和 NDK 28.2，然后执行：

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## 许可

本项目遵循 GPL-3.0 许可证，保留上游的 LICENSE 与版权声明。上游项目名称为 Chameleon Ultra GUI。
