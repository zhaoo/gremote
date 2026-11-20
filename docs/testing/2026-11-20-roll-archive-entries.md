# 胶卷归档入口与 M10V 服务提示修正

范围：GRemote develop 脏工作区，2026-11-20；保留已有离线胶卷、Live 及传输改动。

## 原因与行为

- 原「相机胶卷」是机身滤镜槽位的读取和无线装载页面，并不读取机身拍摄卷。改为「机身滤镜」，页面解释归档入口。
- 原「数字胶卷」包含 App 自建卷及从机身照片自动合并的卷。改为「胶卷归档」，说明下载 JPEG 原片会按机身卷编号、帧序自动归档，无需先在 App 新建卷。
- 增加「从相机导入胶卷」直达相册的相机来源；从已有本地相册页面再次进入也会切换来源。
- bridgeUnavailable 是服务尚未响应，不能据此断言相机不支持无线装卷。显示服务尚未就绪及重试提示；只有 capabilities 明确缺少 readState 才说明不提供滤镜配置读取。
- App 自建胶卷保持原行为：组织和导出本地照片，不启动机身胶卷模式。协议字段、写入逻辑及照片成像未改变。

## 自动验证

SDK：/Users/zhaoo/development/flutter-gremote-3.50.0/flutter/bin/flutter

- `flutter test --no-pub --concurrency=2 test/features/film_workbench_test.dart test/features/roll_archive_entry_test.dart test/features/camera_gallery_roll_test.dart test/camera/companion_sync_controller_test.dart test/film/camera_roll_importer_test.dart`：26 项通过。
- `flutter test --no-pub test/features/library_page_test.dart`：17 项通过，包含初始显示相机来源及返回本地刷新。
- 覆盖：归档按钮路由、空态说明、小屏布局、临时服务错误提示、下载原片的 M10R 元数据归档、JPEG/DNG 合并、乱序下载按帧序整理。
- 修改的 7 个主要源码/测试文件定向 analyze 无错误/警告，仅现有 deprecated_member_use 和花括号建议 info。
- `git diff --check` 通过。

## 真机待验证

这些测试不证明设备 HTTP 服务、SD 卡元数据或下载速度已通过。需要配套固件启动服务后，在 App 下载本卷 JPEG 原片，打开「胶卷归档」核对卷号、张数、帧序，并导出印样。Linux 服务 HELLO 启动问题由固件侧独立修复。未构建 APK，待整体联调统一打包。
