# GRemote 一体化工作平台 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. User has already authorized execution; proceed inline with one final fresh review.

**执行结果：** App 重构与电脑侧验收已交付，记录见 docs/testing/2026-11-01-gr-platform-refactor.md。当前无 ADB 设备，安装与新版真机验收待连接；初始步骤保留作为实施依据。

**Goal:** 实现确认后的四栏直达工作区及“点击编辑、长按保存分享”，复用真实照片/相机链路并保留兼容门禁。
**Architecture:** 现有Flutter服务分层保持；路由重排、新相机工作区、应用相册成员集合与资源管理在独立组件落地。用provider注入HTTP/文件/平台行为，所有可写功能依赖真实capability。
**Tech Stack:** Flutter/Dart、Riverpod、GoRouter、SQLite、既有Pigeon Android/iOS边界与native imaging。
**Spec:** ../specs/2026-11-01-gr-platform-design.md

## Global Constraints
- 用户已批准直达工作区并要求开干；相册点击直接编辑，长按保存/分享。
- 底栏严格首页、相册、相机、拍摄；保留对焦与快门分离、拍摄退出、下载及相机写入门禁。
- 旧数据库、配方、已验证十槽事务和手机renderer不被远端目录或UI覆盖。
- 不添加假数据、无效滑杆或假成功；当前固件未提供的扩展遥控明确不可用。
- 专业编辑算法为用户明确后续扩展，本次保留现有编辑能力及稳定资源路径。
- 不操作原M10V脏工作区、不自动刷机、不发布生产。

## Review Focus
1. 相册长按不能同时触发点击编辑或误保存，分享失败有提示。
2. 源照片移除/权限变化与DB升级不丢失旧编辑、配方或应用成员。
3. 切来源/底栏/进入编辑器时下载和原图传输门禁仍正确。
4. 远端错误/新renderer/不完整下载不能替换已验证缓存或开放相机写入。
5. 第4栏拍摄仍正确停止实景、程序、快门并恢复屏幕方向。

### Task 1: 四栏路由、首页与基础视觉
**Files:** lib/app/router.dart, lib/features/home/home_page.dart, lib/app/theme/*, test/app/router_test.dart, test/features/home_page_test.dart; new lib/features/camera/camera_page.dart.
**Interfaces:** CameraPage 为第3栏工作区；保留 /shoot /library /edit/:mediaId 及旧功能深链。
- [ ] RED: 底栏顺序、首页不含试卷台/口号，第4栏拍摄隐藏底栏、返回保持分支状态。
- [ ] GREEN: 重排分支，改掉index==1硬编码，移除纯装饰文案，新增相机页面最小可导航壳。
- [ ] Run flutter test test/app/router_test.dart test/features/home_page_test.dart → PASS; commit.

### Task 2: 应用相册成员、真实导入与长按动作
**Files:** lib/media/local/{media_gateway,local_media_repository,native_media_gateway}.dart, lib/features/library/{library_page,library_controller}.dart, lib/storage/gremote_database.dart, pigeons/media_api.dart + generated bindings/native implementations; new lib/features/library/album_actions.dart and import/collection service; test/media/* test/features/library_page_test.dart test/storage/*.
**Interfaces:** AlbumCollectionRepository.add(mediaId,source)/listIDs; AlbumActions.importPhotos()/save(item)/share(item) provider-injected realplatform boundary. Old media IDs/editor routes stable.
- [ ] RED: v5 migration preserves records; app collection includes camera downloads/user import, not unrelated scan rows; duplicate/cancel imports unchanged; tap edit and longpress sheet/save/share disjoint; platform failures displayed.
- [ ] GREEN: 增量表迁移，真实文件/照片导入与平台保存分享，日期三列，本地集合不受GR机型过滤。
- [ ] Run flutter test test/media test/storage test/features/library_page_test.dart → PASS; commit.

### Task 3: 机内相册、持续下载与编辑资源迁移
**Files:** lib/features/library/camera_gallery.dart, camera_transfer.dart, library_page.dart; lib/features/darkroom/darkroom_page.dart/editor/*; test/features/library/* test/features/darkroom_page_test.dart.
**Interfaces:** 来源切换保留CameraGallery任务；download返回URI登记collection；编辑资源页复用现LUT/方案/最近编辑。
- [ ] RED: 未连接提示；切来源仍显示当前下载进度；下载成功进入应用相册；断连停后续请求；照片直接编辑/资源菜单可达。
- [ ] GREEN: 来源分段tab+保活任务，下载URI登记，保留批量/RAW语义与传输门禁，资源页移至相册二级。
- [ ] Run flutter test test/features/library test/features/darkroom_page_test.dart test/features/library_recipe_test.dart → PASS; commit.

### Task 4: 胶卷表格、详情、十槽确认及能力驱动扩展
**Files:** new lib/features/camera/{camera_page,film_library_page,film_detail_page,extensions_page}.dart; adapt existing film_workbench/camera_films_page.dart widgets/controller reuse; tests test/features/camera/*.
**Interfaces:** Camera workspace consumes cameraFilmCatalogProvider + CompanionSyncController; existing prepare/install/activation unchanged.
- [ ] RED: 51库列表/详情；只读/未连接/未配对/当前v2扩展理由；十槽真实目标05确认；旧只读字段不出现可写控件；旧结果未知不重放。
- [ ] GREEN: 紧凑表格、参考预览来源、可收起十槽、复用安全装卷操作；全部扩展分组从明确支持描述呈现，缺RPC仅解释不可用。
- [ ] Run flutter test test/features/camera test/features/camera_films_page_test.dart test/camera → PASS; commit.

### Task 5: 官网同步缓存、胶卷库文件与自定义LUT入口
**Files:** new lib/camera/library/{official_film_library,library_cache,library_bundle}.dart + providers/UI; reuse darkroom/lut/lut_library.dart; test/camera/library/*.
**Interfaces:** OfficialFilmLibrary.sync() returns validated remote metadata/cache; downloaded bundle stored separately from firmware-pinned camera contract. Cache commits after model/hash/CRC validation.
- [ ] RED: 成功目录同步/缓存、HTTP失败保留旧缓存、错误模型/CRC/renderer拒绝、相机不兼容时禁写；导入LUT真实持久且capability=false不上传/不假成功。
- [ ] GREEN: 真实HTTPS GET目录与既有导出接口适配、限长下载和完整校验/原子缓存；复用LUT导入资源持久库，在库中可查看用途/机内限制。
- [ ] Run flutter test test/camera/library test/darkroom/lut_library_test.dart → PASS; commit.

### Task 6: 整体验证、独立审查与APK交付
**Files:** tests integration/screenshots/evidence, docs/testing/*.
- [ ] 完整Flutter tests、scopedanalyze、Android native checks、debug APK build；host/ARM结果分层报告。
- [ ] 一次全分支freshreview；Critical/Important一轮RED→GREEN修复与完整回归。
- [ ] 手机仍授权连接时安装新APK保留数据，实测四栏/相册点按长按/机身读取装卷；不触发未授权拍摄、不自动刷固件。
- [ ] 记录已完成/未支持/未测及产物hash；保留分支待用户验收，不生产发布。
