# App 外观与设置 — 2026-11-03

用户已确认 gr-editor-studio-themes.html 视觉稿，最新确认「可以的」。实现位于 develop，未刷相机、未改 SD、未 push/发布。

## 已落地

- 首页更多菜单保留手动 Wi-Fi 和诊断，新增独立设置路由；返回保留连接状态。
- 深色、浅色、跟随系统，本地有序持久化，启动前加载；旧安装默认深色。保存失败可重试；启动读取失败的重试先重新读盘，避免用默认值覆盖已存偏好。
- 逐页 UI 语义色，照片/导出画布/相机参数独立；取景画面及照片上的覆盖控件使用不变的高对比色。
- 既有光圈与字标的显示时 alpha 蒙版。Flutter 真实 layer 输出检查：深浅两种主题四角 alpha=0，前景 tint 正确，半透明抗锯齿边缘存在。
- 全局手动触感反馈开关；关于读取 Android PackageManager / iOS Bundle 的真实版本和构建号，开源许可使用 Flutter LicenseRegistry。

## 自动检查

初始全套：580 pass，3 conditional skips。实现后的完整 Flutter suite 与 analyze/Android 构建结果见末尾追加记录。

针对检查：真实 SQLite 持久化/失败事务/重试/快速选择；实际 App 冷启动主题与系统模式；透明 Logo 的渲染像素；设置入口/返回保持连接状态；320×736、1.6 倍字体；保存失败提示/重试；触感平台调用门控。

## 待真机验收

ADB 本轮尚无设备，未覆盖安装或声称实际手机外观已确认。iOS 元数据接入尚未做 Xcode 构建。GPU 修图仍按独立实施计划推进；这个外观 APK 不代表 GPU 后端或照片画质已验收。

## 审查后结果

独立审查发现 4 个 P2，均完成定向 RED→GREEN：读取失败时合并用户意图以保留未知字段；弹层背景交给动态主题；Tooltip/系统控件触感门控（包含 Android/iOS 开关拖动）；浅色 RGB 通道前景/曲线颜色对比度。无 Critical、无 deferred minor。

最终完整 Flutter：601 passed，3 conditional skips；analyze 无问题；Android arm64 debug 构建成功，1.2.0-dev+15。APK：dist/gremote-appearance-1.2.0-dev+15-arm64-debug.apk。真机安装仍待 ADB 连接。GPU 图像处理不包含在此 APK 的完成声明中。
