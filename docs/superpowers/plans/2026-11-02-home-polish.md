# 首页美化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地已定稿的首页，并让 App 本地相册照片成为可管理的作品封面。

**Architecture:** 首页专用样式与展示组件保留现有连接状态机和路由。独立封面模型通过已有本地相册与 app_kv 存储读取照片和配置；轮播生命周期由首页组件管理，不添加相机网络请求。

**Tech Stack:** Flutter、Riverpod、sqflite、已有 MediaGateway 与 LocalMediaRepository。

**Spec:** docs/superpowers/specs/2026-11-02-home-polish-design.md

## Global Constraints

- 全部开发在 develop；不恢复或覆盖其他工作区。
- 最多 5 张，自动播放间隔 8 秒，用户作品不叠 slogan。
- 只显示 App 相册可读照片，不自动请求权限，不读相机远程目录。
- 原始照片不变，封面配置独立持久化。
- 所有既有连接/故障/警告/诊断/定位能力保留，对焦与快门分离。
- M10V 扩展保持暂停，禁止生产发布。

## Review Focus

- 老照片新导入：按导入时间选择封面，不按 EXIF 拍摄时间。
- 权限撤销或照片失效：默认图回退，不能泄露旧缩略图或删除用户配置。
- 页面隐藏与返回：无后台定时切换，不叠加多个 timer。
- 横竖图及 320 宽/大字号：主体位置可调，控件与文字不溢出。
- 连接失败、未知固件与 Wi-Fi-only：必要警告和恢复入口仍可达。

### Task 1: 首页视觉与完整连接状态

**Files:**
- Modify: lib/features/home/home_page.dart
- Modify: lib/features/home/widgets/connection_card.dart
- Create: lib/features/home/widgets/home_brand.dart
- Create: lib/features/home/widgets/home_cover.dart
- Modify: lib/features/home/import_history.dart
- Modify if needed: lib/app/router.dart（只调整共享导航视觉，不改路由）
- Create: assets/images/gremote_brand_editorial.png
- Test: test/features/home_page_test.dart、test/app/router_test.dart

**Interfaces:** HomePage 仍从 connectionControllerProvider 读取真实状态；ConnectionCard 回调与现有签名不变。HomeCover 暂以默认图渲染，随后接入 Task 2/3。

- [ ] 按既有测试补充/保留导航与操作行为验证：连接、取消、重试、设置授权、手动 Wi-Fi、诊断、协议探测、拍摄路由。
- [ ] 从已选 B 素材制作独立标识资源；保留原始概念图的可追溯身份，核对小尺寸清晰度与透明边缘。
- [ ] 按设计调整首页局部排版，复用所有真实连接状态与必要警告；不全局换主题影响未设计页面。
- [ ] 运行相关首页与路由测试，人工检查 320/390 宽、大字体、连接与失败状态；提交本任务代码。

### Task 2: 作品封面配置与本地照片选择

**Files:**
- Create: lib/features/home/home_cover_settings.dart
- Create: lib/features/home/home_cover_repository.dart
- Modify: lib/media/local/local_media_repository.dart
- Test: test/features/home/home_cover_repository_test.dart

**Interfaces:**
- HomeCoverSettings：version=1、useDefault、autoplay、orderedEntries；每项保存 mediaId、uri、alignmentX/Y（-1..1）。
- HomeCoverRepository.load()/save(HomeCoverSettings)：使用 app_kv 的 home.cover.v1，损坏记录读取失败后使用安全默认配置，不静默覆盖原记录。
- LocalMediaRepository.recentAlbumImports({int limit=5})：JOIN album_collection，按 added_at DESC、media_id DESC 返回本地 App 相册项。
- resolveCoverItems(settings, available)：保留指定顺序、最多 5 张，失效项跳过；没有指定且非 useDefault 时使用最近导入结果。

- [ ] 增加行为用例并先确认失败：老照片新导入优先、最多 5 张、显式恢复默认不被后续导入覆盖、指定顺序、缺失图片、损坏配置、uri 不匹配。
- [ ] 实现配置持久化、最近导入查询与选择规则；只存引用和取景位置，不复制/修改原图。
- [ ] 运行新增 repository 用例及现有 album_collection 回归；提交本任务代码。

### Task 3: 封面展示、管理与生命周期

**Files:**
- Modify: lib/features/home/widgets/home_cover.dart
- Create: lib/features/home/home_cover_manager.dart
- Modify: lib/features/home/home_page.dart
- Test: test/features/home/home_cover_test.dart

**Interfaces:** HomeCover 接受已核对照片、配置与可见状态；封面管理面板只通过 Task 2 的 save 更新配置，允许选图/排序/单张固定/位置调整/自动播放/恢复默认。缩略图沿用 MediaGateway.thumbnail，禁止全尺寸原图反复解码。

- [ ] 增加行为测试并确认失败：8 秒后切换、交互暂停、后台/切页暂停、返回重新计时、单张不播、减少动态效果、权限撤销回退、最新导入更新。
- [ ] 实现默认主图与用户作品两种展示，后者隐藏 slogan；显示页码提示并保留手动滑动。
- [ ] 实现长按管理与取景调整，持久保存顺序/位置；取消管理不保存草稿。
- [ ] 验证窄屏、大字号、横竖方向与拖动焦点，不得修改原照片或调用相机；相关行为测试通过后提交。

### Task 4: 交付验证

- [ ] 运行 flutter analyze 与相关测试；有新增跨模块变更时运行对应相册/定位/连接回归。
- [ ] 构建 Android arm64 debug APK，记录提交、版本、文件哈希。
- [ ] 有 USB 设备时安装并检查真实首页、系统相册权限、封面/后台恢复/管理保存和返回；未连接时明确未验证，不宣称真机通过。
- [ ] 在 docs/testing 记录已验证/未验证边界。用户未要求推送时保留本地提交，不发布生产。
