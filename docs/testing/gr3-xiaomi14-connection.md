# GR III 2.10 + 小米 14 连接调试

## 相机准备

1. 在 GR III「蓝牙设置」中开启蓝牙并执行配对；若以前用 Image Sync / GR WORLD 配对，先核对相机和手机里的配对记录。
2. 单独测试 Wi-Fi 时，在「无线 LAN 设置」中设为开启，从「通信信息」抄录 SSID 和密码。在 gremote 首页点「手动连接 Wi-Fi」，允许系统连接无互联网网络。
3. 不要在诊断信息或 issue 中附上 Wi-Fi 密码。诊断 JSON 只含阶段、耗时与状态码。

## Mac 连接 Android 手机

在小米 14 开启开发者选项与 USB 调试，USB 线接 Mac，并在手机上允许此电脑调试。项目使用的 Android SDK 工具在 `/opt/homebrew/share/android-commandlinetools/platform-tools`。

```sh
export PATH="/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
adb devices -l
flutter devices
flutter run -d <flutter devices 显示的手机 ID>
```

首页连接失败后点「查看连接诊断」→「复制脱敏 JSON」。重点查看 `ble.connected`、`ble.mtu`、`ble.services`、`ble.readModel` 等事件与紧随其后的异常。若 `ble.disconnected` 带非零 `statusCode`，同时记录手机系统版本和相机屏幕提示。若只出现 `ble.connected`，后续没有 `ble.services`，优先检查服务发现阶段。

需要系统级日志时，在复现前运行：

```sh
adb logcat -c
adb logcat -v time -s BluetoothGatt:D BtGatt.GattService:D flutter:I '*:S'
```

复现后按 Ctrl-C 停止。分享日志前检查其中是否有设备地址、SSID 或其他私人信息。Mac 本身不能代替小米 14 验证 Android BLE 与 Wi-Fi 系统弹窗；Flutter 单测和 APK 构建只验证代码路径与可安装产物。
