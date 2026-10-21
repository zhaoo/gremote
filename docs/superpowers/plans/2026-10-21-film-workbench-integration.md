# Film Workbench Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用真实平台传输接通五槽与双向同步，完成集成回归和可识别测试包。
**Architecture:** 独立固定目标传输、三方合并状态机与现有 Flutter/媒体系统集成；仅 committed+readback 才同步成功。
**Tech Stack:** Dart/Riverpod、Kotlin Network/Keystore、Pigeon、iOS Keychain/显式 unsupported、host HTTP 与 Flutter integration_test。
**Spec:** [规格](../specs/2026-10-21-integrated-film-workbench-design.md)。

## Global Constraints

[总计划](2026-10-21-film-workbench.md)的全部约束/接口适用；组件不存在时只读降级，不静默覆盖机身；后台不轮询；先交测试包等用户设备确认，不能提前推送或部署。

## Review Focus

Wi-Fi 切换后旧请求/旧会话结果 → C1/C2；iOS 未实现平台调用 → C1；ACK 丢失与新 boot → C2；源快照/目录漂移 → C3；联系人式配方卡或日志泄露密钥/位置 → C1/C3。

## C1：原生伴侣传输、配对和平台桥

**Files:** Create `lib/camera/companion/{companion_transport,companion_client,pairing_store}.dart`、`android/app/src/main/kotlin/com/izhaoo/gremote/device/http/BoundCompanionTransport.kt`、`android/app/src/main/kotlin/com/izhaoo/gremote/device/companion/CompanionPairingStore.kt`、`test/camera/companion_client_test.dart`、`android/app/src/test/kotlin/com/izhaoo/gremote/device/http/BoundCompanionTransportTest.kt`；Modify A1 生成的 `companion_protocol.dart` 的生成真源（只通过生成器改变）、`pigeons/device_api.dart`、Android `BoundCameraTransport.kt`（只提供已探测 host/Network 的受控访问）、`android/app/src/main/kotlin/com/izhaoo/gremote/device/GRemoteDeviceHostApi.kt`、`ios/Runner/Native/GRemoteDevice.swift`与 `scripts/generate_ios_bridges.py`。

**Interfaces:** 实现总计划的 CompanionTransport/Client、B3 签名和 B5 分块接口；Pigeon `companionRequest(method,path,headers,body)`、`saveCompanionPairing(instanceId,keyBytes)`、`removeCompanionPairing(instanceId)`，不接受任意 URL/端口。密钥操作由平台完成，不把持久密钥返还 Dart 日志；签名接口 `signCompanionRequest(instanceId,canonicalBytes) -> Uint8List` 使用保护存储中的 key。

- [ ] 写失败测试：仅固定已探测相机 host:18743 经同 Network；重定向/任意主机/路径穿越/跨会话回包拒绝；headers/body 保持原值；nonce HMAC 与 B3 fixtures 一致；密钥日志脱敏；缺组件和 iOS 未支持网络能力返回结构化 unsupported，不触发 MissingPluginException。 代表用例 `companion_cannot_redirect_off_bound_camera` 的核心断言：`assertEquals("invalidCompanionTarget", failure.code)`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `flutter test test/camera/companion_client_test.dart`、`(cd android && ./gradlew :app:testDebugUnitTest --tests '*BoundCompanionTransportTest')`，确认红灯。
- [ ] 实现固定目标与受限 body/read 超时、配对导入及平台保护存储，复用相机绑定 Network，不影响原厂请求；按 Pigeon 真源再生成 Dart/Kotlin/Swift，禁止手改派生文件。iOS 提供明确 unsupported 网络边界和 Keychain 存储，保留构建。
- [ ] 重跑两条测试；用 host B3 服务走真实 HTTP 签名/分块/错误解析闭环；记录为 host 联调，不当作 Android Wi-Fi 或相机验收。
- [ ] 提交 `feat: connect authenticated companion transport and protected pairing`。

## C2：三方合并、同步状态机和 UI 接通

**Files:** Create `lib/camera/companion/{three_way_merge,companion_sync_controller,sync_state}.dart`、`test/camera/{three_way_merge,companion_sync_controller}_test.dart`、`integration_test/film_workbench_flow_test.dart`；Modify A5 的 camera_films_page/load/conflict sheets 和 A4 的配方证据入口。

**Interfaces:** `threeWayMerge({required Map<String,Object?> base,required Map<String,Object?> local,required Map<String,Object?> remote,required CompanionCapabilities capabilities}) -> MergeResult`；`CompanionSyncController.refresh()/prepareLoad({required int slot,required FilmRecipe recipe,required bool activate})/resolve(Map<String,ConflictChoice>)/confirm()/reconcileUnknown()`。state 使用规格的连接/操作枚举，含 baseline、差异、busy、unverified/stale 标记，UI 不直接 set synced。

- [ ] 写失败测试：字段仅单端变化自动合并、同值不写、冲突显式选；保留两份只创建本地配方；未知新字段保留且禁止旧模型写；同 boot 同请求重试不重复提交；ACK 丢失→unknown，新 boot 不自动重放；2xx/pending/读回不符都不能 synced；装入成功激活失败显示“已装入，切换失败”；退出后旧响应不覆盖新会话。 代表用例 `lost_ack_remains_unknown_until_readback` 的核心断言：`expect(controller.state.operationStatus, SyncOperationStatus.unknown)`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `flutter test test/camera/three_way_merge_test.dart test/camera/companion_sync_controller_test.dart`，确认红灯。
- [ ] 实现 baseline 三方合并、持久操作日志、网络/相机忙互斥和拍摄/原图传输写入延后；前台每2秒最多一次刷新，后台停；自定义先 stage+verify 后装入；配置与激活两步确认，分别保留准确结果。接真实五槽/本张配方证据，移除原型假计数/假同步状态。
- [ ] 重跑测试和 `flutter test integration_test/film_workbench_flow_test.dart -d <实际连接的Android设备ID>`；无设备时后者明确 not-run，不用 fake 代替真机结论。host 联调覆盖断线/重启/冲突，硬件同时验收首张、连拍、RAW+JPEG、回放及机身参数回传。
- [ ] 提交 `feat: reconcile film slots and verify bidirectional synchronization`。

## C3：全量回归、测试候选与设备验收材料

**Files:** Create `docs/testing/film-workbench-acceptance.md`、`docs/testing/film-workbench-source-manifest.json`（只含可公开源码哈希）、`scripts/package_film_workbench_candidate.py`、`scripts/package_film_workbench_candidate_test.py`；Modify `pubspec.yaml`（候选版本身份）和 M10V 已有 receipt/导出入口需要的测试。私有产物写入新的 `dist/film-workbench-<buildId>/`，不提交固件/密钥/照片。

**Interfaces:** `package_film_workbench_candidate.py --apk PATH --camera-receipt PATH --out NEW_DIR` 生成 App+匹配相机支持/SD/配对文件/恢复说明/验证清单及 SHA256SUMS；验证 App renderer/catalog 与相机 receipt 匹配；不能用版本名相同代替内容身份。

- [ ] 写打包失败测试：旧/缺失 receipt、哈希不符、错误机型、已有输出目录、未知测试状态拒绝生成“已验收”标签；无硬件结果只能 offline-verified。配对密钥不出现在公开 manifest 或日志。 代表用例 `test_candidate_rejects_mismatched_renderer` 的核心断言：`assert result.returncode != 0`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `python3 -m unittest discover -s scripts -p 'package_film_workbench_candidate_test.py'`（测试文件与脚本同目录创建），确认红灯。
- [ ] 实现打包/验收材料；记录 changed/preserved/known-broken/untested、三仓库 revision/dirty fingerprint、实际检查及 skip；恢复只撤本功能文件/include，不覆盖其他 SD 脚本。
- [ ] 执行 GRemote `bash scripts/build_android.sh`；有 Xcode/CocoaPods 时执行 `bash scripts/build_ios.sh --no-codesign`，否则记录缺失；M10V `npm test` 及 B1–B5/保护索引相关 Python/ARM/最终 BIN 回读；检查候选 ZIP CRC/SHA256SUMS。新增改动后重跑受影响项，不无因重复长套件。
- [ ] 交付可识别测试包和逐步设备清单：连接/只读/装卷/机身改动/冲突/离线/重启/RAW+JPEG/连拍/回放/撤除。等待用户针对该 hash 的明确实测结果；有故障修复后新候选重新验收，通过后才按指定技能完成 main/GitHub/宝塔。

## 收尾评审

推荐 Native 执行时，在全分支完成后做一次独立代码评审，重点审协议授权、生命周期、事务/未知结果和相机既有行为；任何 P1/P2 修复都须重跑其对应检查，候选行为变化重新交设备验证。是否使用子代理评审由所选执行方式及适用评审技能决定，不能把模型意见替代设备证据。
