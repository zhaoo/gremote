# GRemote 胶卷归档与动态照片测试

2026-11-16，`develop` 基线 `f4d725fea0fc38504e58d01e756b4f1db7290016`。候选安装包使用独立应用 ID `com.izhaoo.gremote.rolllive` 与本地 debug 签名。

- JPG/DNG 的 M10R 帧标签单独校验。相同卷号、帧号的 JPG 与 DNG 合并，排序和联系印样使用机身帧号。MCR2 缺失时保留「配方未验证」。用 SQL 独立唯一索引保护重复导入。
- Android 相册可用合成 M10R 样本直接验证归卷。测试包内三个文件名按字母排序时分别是 03、01、02，它们来自项目样片。样例短片是 H.264 MP4，3.077 秒。
- 通过 Android 工具手动选择 JPEG/MP4 导出新 Motion Photo。输出保留原 JPEG 与 MP4 内容，增加 Google XMP 和 MP4 尾部。Android 系统相册是否可播放仍待实机确认。
- 机身没有出刷机候选。M10V 普通快门的逐文件保存结果、关机前持久化和重启恢复，以及 Live 差异见机身仓库的 `docs/research/gr3-roll-live-2026-11-16.md`。

本地定向静态分析、Flutter 37 项、Kotlin 9 项。Flutter 单 worker。Gradle 单 worker、关闭并行和常驻 daemon、JVM 最多识别两个核心。APK 安装、真机相册和 iOS 流程未验证。
