# Film Workbench App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付离线可用、符合已确认视觉的试卷台和数字胶卷。
**Architecture:** 真源生成的配方和纯渲染库驱动后台预览，SQLite 保存不可变配方及照片证据，Riverpod 控制 UI 与导出。
**Tech Stack:** Flutter/Dart/Riverpod/SQLite、C/C++ FFI、Node 生成器。
**Spec:** [规格](../specs/2026-10-21-integrated-film-workbench-design.md)。

## Global Constraints

[总计划](2026-10-21-film-workbench.md)的全部 Global Constraints 和接口字典适用；数据库 v4、预览 960/640、48 MiB、印样 24 张/页、原片不覆盖。

## Review Focus

卡身份复用/后到 RAW → A2/A4；已处理 JPEG 与未知配方 → A3/A6；320px/大字/快速退出/减少动画 → A3/A5；印样缺图、低磁盘、取消 → A6；目录 ID 增长与并发修改源文件 → A1。

## A1：生成目录、能力和渲染快照

**Files:** Create `scripts/sync_m10v_contract.mjs`、`scripts/sync_m10v_contract.test.mjs`、`assets/films/catalog.json`、`assets/films/icons/`、`lib/film/catalog/film_catalog.dart`、`lib/film/model/film_recipe.dart`、`lib/camera/companion/companion_protocol.dart`、`test/film/film_catalog_test.dart`、`native/imaging/vendor/m10v/manifest.json`；Modify `pubspec.yaml`。M10V 真源 `contracts/companion-v1.json` 在 B1 创建，A1 只消费该真源，不另建第二份 schema。

**Interfaces:** 消费 M10V `nativeCatalog()`、`normalizeConfiguration()` 和纯算法源码依赖；产生总计划的 FilmCatalog、FilmRecipe，以及带每文件 SHA/许可证的 vendor manifest。生成器 `syncContract({sourceDir,outputDir,check}) -> Promise<Manifest>`，命令参数 `--source PATH [--check]`。

- [ ] 写失败测试：保留所有稳定 ID（含 289），可见列表由源筛选生成；相同参数不同名称 fingerprint 相同；无效 grain/EI、未知 schema 拒绝；源在读取中变化则失败且不替换现有快照。 代表用例 `recipe_hash_ignores_display_name` 的核心断言：`expect(first.fingerprint, renamed.fingerprint)`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `node --test scripts/sync_m10v_contract.test.mjs` 和 `flutter test test/film/film_catalog_test.dart`，确认红灯属于缺失的新接口。
- [ ] 实现生成器及值对象，先临时目录生成、核对 source fingerprint 后整体发布；依赖闭包只复制纯算法和数据，保留 notices，记录是否 dirty，不复制相机固件。
- [ ] 重跑上述命令及 `node scripts/sync_m10v_contract.mjs --source /Users/zhaoo/Desktop/code/zhaoo/m10v --check`；预期 ID/哈希一致，故意改源后 check 非零。
- [ ] 只提交生成器、目录/图标、合法纯源码快照、notices、模型与测试：`feat: share versioned M10V film catalog and recipes`。

## A2：胶卷仓储和 v4 数据迁移

**Files:** Create `lib/film/model/{film_roll,camera_photo_identity}.dart`、`lib/film/store/{film_repository,sync_repository}.dart`、`test/film/film_repository_test.dart`；Modify `lib/storage/gremote_database.dart`、`test/storage/gremote_database_test.dart`。

**Interfaces:** 消费 FilmRecipe；产生 `FilmRepository.createRoll({required String name,required int targetCount,required FilmRecipe recipe}) -> Future<FilmRoll>`、`closeRoll(String)`、`addConfirmedPhoto({required String rollId,required CameraPhotoIdentity identity,required FilmRecipe recipe,required List<String> files,required RecipeConfidence confidence}) -> Future<RollItem>`、`listItems(String)`。`SyncRepository.saveBaseline(CompanionSnapshot)` 和 `saveOperation(SyncOperation)` 是 C2 的持久化边界。

- [ ] 写失败测试：真实 v1/v2/v3 fixture 升级保留旧数据；1–24 字符卷名、目标 1–999；两个并发开卷事务只能成功一个；同卷 JPG+DNG 合并一张；不同 instance/storageEpoch 的同名文件独立；修改配方不改变历史项。 代表用例 `late_raw_merges_without_cross_camera_collision` 的核心断言：`expect((await repo.listItems(roll.id)).length, 1)`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `flutter test test/film/film_repository_test.dart test/storage/gremote_database_test.dart`，记录新用例红灯。
- [ ] 实现 schema v4、唯一活动卷约束/事务、稳定身份索引、未知结果操作日志；同版本重复打开不重建表，JSON 损坏按单条错误返回，不清空库。
- [ ] 重跑该命令；关闭再打开数据库验证卷、照片和 pending/unknown 操作持久，旧图库记录逐项不变。
- [ ] 提交 `feat: persist film rolls immutable recipes and sync baselines`。

## A3：真实纯渲染与有界预览调度

**Files:** Create `native/imaging/src/m10v_preview.{h,cpp}`、`native/imaging/tests/m10v_preview_test.cpp`、`lib/film/preview/{film_preview_engine,film_preview_controller}.dart`、`test/film/film_preview_controller_test.dart`；Modify `native/imaging/{CMakeLists.txt,include/gremote_imaging.h,src/api.cpp,tests/test_runner.cpp}`、`lib/imaging/{imaging_bindings,ffi_imaging_engine}.dart`。

**Interfaces:** 消费 A1 的冻结纯源码与 FilmRecipe；C API `int gr_film_preview_v1(const uint8_t *rgba,uint32_t width,uint32_t height,uint32_t pitch,const uint8_t *recipe,uint32_t recipeBytes,uint32_t stages,uint8_t *out,const int32_t *cancel)`，返回码沿现有 ImagingException 规则映射。Dart `FilmPreviewEngine.render({required PreviewImage source,required FilmRecipe recipe,required PreviewStage stage,required int generation}) -> Future<FilmPreviewResult>`；结果含 generation、recipeFingerprint、image、stage。

- [ ] 写失败测试：RGBA↔Y/CbCr422 固定向量、奇数宽度/stride padding、所有效果关闭、特殊卷、取消后内存释放；请求 A/B/C 快速切换最多一执行一待执行，C 覆盖 B，A 结果不能刷新 C；worker 确认退出前不能释放取消标志；超过 48 MiB 降级/释放；已处理 JPEG 默认无重复全色彩。 代表用例 `latest_frame_wins_and_cancel_flag_lives_until_exit` 的核心断言：`expect(results.last.generation, 3); expect(maxPending, 1)`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `bash scripts/build_native_host.sh` 和 `flutter test test/film/film_preview_controller_test.dart`，确认新接口红灯，不以现有 host 用例通过替代。
- [ ] 实现保持源图只读的适配器、纯渲染共享、后台 worker 与最新帧队列；JPEG 字节解码复用 `ui.instantiateImageCodec` 的有界异步模式（参考 LiveFrameAnalyzer），codec/image 完成后 dispose，只有最新解码结果能进入 native worker；颜色阶段和空间阶段绑定同一配方；960 降到 640；销毁时取消 generation，禁止从 worker 更新已销毁 notifier。
- [ ] 重跑两条命令；使用 M10V host renderer 对相同输入对照输出，保存固定向量/舍入证据，仍将相机 Live View 标为近似。
- [ ] 提交 `feat: render M10V trial previews with bounded background work`。

## A4：按真实文件归档与断线补入

**Files:** Create `lib/film/capture/{roll_capture_recorder,roll_reconciliation}.dart`、`test/film/roll_capture_recorder_test.dart`；Modify `lib/camera/capture/capture_tracker.dart`、`lib/camera/sync/camera_state_controller.dart`，仅补充文件身份/事件字段；保留原有 tracker 行为。

**Interfaces:** 消费 A2、现有 CaptureRecord 和 C2 的已确认快照；`RollCaptureRecorder.record(CaptureRecord,RecipeEvidence) -> Future<void>`；`RecipeEvidence` 含冻结 FilmRecipe、confidence、相机身份/代际。`RollReconciliation.candidates({required CameraPhotoBaseline before,required List<CameraFile> after}) -> List<UnassignedPhoto>` 仅提出候选；`assign(List<UnassignedPhoto>,String rollId,FilmRecipe)` 需显式用户操作。

- [ ] 写失败测试：快门超时/仅 captureId 变化不增加计数；延迟 RAW 补入原项；连接代际变化丢弃旧配方；两机同名/卡重置不串卷；断线新文件不自动归卷；桥不支持私有快照时 confidence=unverified。 代表用例 `shutter_timeout_does_not_create_roll_item` 的核心断言：`expect((await repo.listItems(roll.id)), isEmpty)`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `flutter test test/film/roll_capture_recorder_test.dart test/camera/capture_tracker_test.dart` 确认新增红灯且旧 tracker 保持基线。
- [ ] 实现订阅和去重，单张配方在证据产生时冻结；不改后台定位权限或拍摄计数语义；为 C2 的真实拍摄证据预留能力字段而不伪造。
- [ ] 重跑该命令，验证 body/app/program 三来源及退出重入无重复订阅。
- [ ] 提交 `feat: archive confirmed captures and reconcile unassigned photos`。

## A5：Flutter 工作台与视觉落地

**Files:** Create `lib/features/film_workbench/{film_workbench_page,trial_page,rolls_page,camera_films_page,workbench_providers}.dart`、`lib/features/film_workbench/widgets/{film_picker,comparison_preview,texture_sheet,roll_card,load_film_sheet,conflict_sheet}.dart`、`test/features/film_workbench_test.dart`、`assets/images/film_workbench_sample.jpg`（已确认的 AI 示例，保持来源标记）；Modify `lib/app/router.dart`、`lib/features/home/home_page.dart`、`lib/features/shoot/shoot_page.dart`、`lib/features/library/library_page.dart`。

**Interfaces:** 消费 A1–A4 的 repositories/controllers；`FilmWorkbenchPage({initialSection})` 路由 `/film-workbench`；试卷输入选择复用 MediaGateway 与 LiveViewController；相机 UI 只消费 C2 的 SyncState，未接通时真实显示 unsupported/offline。

- [ ] 写失败 widget 测试：以 GRemoteTheme.dark 在 320×640、390×844、1.4 textScale 下显示关键按钮且可滚动；拖分界线不调用 render；选卷不写相机；新卷空状态无示例假照片；减少动画/退出弹层焦点恢复/快速离开无异步 setState；原四导航仍可访问。 代表用例 `trial_browsing_never_writes_camera` 的核心断言：`expect(fakeCompanion.submittedOperations, isEmpty)`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `flutter test test/features/film_workbench_test.dart` 记录红灯。
- [ ] 落实已确认沉浸布局、比较模式、能力感知参数、真实缩略图与状态；手势反馈独立于渲染，44px 触控、180–230ms/280ms 动画；未完成安装不得静态显示“已同步”。
- [ ] 重跑用例及现有 home/shoot/library 页面测试；生成 Flutter 实际渲染截图对照视觉稿，记录差异，不用 HTML 原型截图替代 App 截图。
- [ ] 提交 `feat: build immersive film workbench and roll interfaces`。

## A6：联系印样、精选集和配方卡

**Files:** Create `lib/film/export/{contact_sheet_layout,contact_sheet_exporter,recipe_card_codec}.dart`、`lib/features/film_workbench/roll_export_page.dart`、`test/film/{contact_sheet_exporter,recipe_card_codec}_test.dart`；Modify `lib/darkroom/export/export_queue.dart`、`lib/media/local/media_gateway.dart`、`pigeons/media_api.dart`、`test/support/fake_media_gateway.dart` 、`android/app/src/main/kotlin/com/izhaoo/gremote/media/GRemoteMediaHostApi.kt`、`ios/Runner/Native/GRemoteMedia.swift` 与派生桥（只增加合成结果发布入口，旧单图导出接口不变）。

**Interfaces:** `ContactSheetLayout.pages(List<RollItem>,{int pageSize=24}) -> List<ContactSheetPage>`；`ContactSheetExporter.export(FilmRoll,List<RollItem>,{required ImagingCancelToken cancel}) -> Stream<ContactSheetProgress>`；`RecipeCardCodec.encode(FilmRecipe)/decode(Uint8List)`；`MediaGateway.publishGenerated({required String tempPath,required String displayName,required int width,required int height}) -> Future<String>`，不伪造 sourceId。

- [ ] 写失败测试：25 张分两页，按张解码；缺图保留位置，其他页继续；失败重试/取消/磁盘不足清理临时文件；已处理 JPEG 不再套色；精选仅导出所选项；配方卡无 GPS/密钥、未知 schema 不覆盖现状。 代表用例 `contact_sheet_paginates_and_retains_missing_cell` 的核心断言：`expect(pages.map((p) => p.items.length), [24, 1])`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `flutter test test/film/contact_sheet_exporter_test.dart test/film/recipe_card_codec_test.dart` 确认红灯。
- [ ] 实现逐张铺排与有界内存、独立生成图发布、现有队列串行协作、精选/配方卡导入分享；不覆盖原片；保留必要 EXIF 隐私策略。
- [ ] 重跑上述命令和现有 export_queue/export_service 测试；实际生成 JPEG 并解码核对尺寸、页数、缺图标记与文字位置。
- [ ] 提交 `feat: export roll contact sheets selections and portable recipes`。
