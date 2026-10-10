# gremote 遥控拍摄（三期）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改固件的前提下，用 GR III 原厂 Wi‑Fi 接口实现参数遥控、驱动模式与程序拍摄、组合配方，拍摄页 100% 复刻 HyperOS 相机布局。

**Architecture:** 新增一层与 UI 无关的相机协议/状态层（解析、写入、同步、拍摄识别、程序执行、配方会话），由 Riverpod 控制器对外暴露；Kotlin 只新增 WebSocket 与屏幕常亮两个能力；拍摄页按 v3 原型重写。所有未上真机的协议行为都集中在 `props_parser` / `protocol_profile` / `capture_tracker` 三处，便于协议探测后修正。

**Tech Stack:** Flutter 3.24.5 / Dart 3.5.4、Riverpod 2、sqflite、Pigeon 22、Kotlin + OkHttp 4.12（WebSocket）、fake_async、MockWebServer。

**Spec:** `docs/superpowers/specs/2026-10-10-gremote-remote-control-design.md`

**通用约定**

- 测试命令：`flutter test <path>`；全量：`flutter test`；静态检查：`flutter analyze`。
- Kotlin 测试：`cd android && ./gradlew :app:testDebugUnitTest`（需 `JAVA_HOME` 指向 JDK 17）。
- 固件推导、未经真机验证的代码，在类注释里写 `firmware-derived / hardware-unverified`。
- 不在本仓库执行 `git commit`，提交统一在任务结束后按发布流程处理（git 根目录是上级目录，含其他项目改动）。
- 时间统一用「墙钟秒」：把相机/EXIF 的本地时间字段原样放进 `DateTime.utc(...)` 后取 `millisecondsSinceEpoch ~/ 1000`，避免时区换算。

---

## 文件结构

**新增（Dart）**

| 文件 | 职责 |
|---|---|
| `lib/camera/params/camera_param.dart` | `ParamKey`、`ParamEndpoint`、`CameraParam` |
| `lib/camera/params/exposure_values.dart` | tv/sv/xv 数值解析、对数空间就近量化 |
| `lib/camera/params/param_writer.dart` | 串行写入队列、合并、格式回退、结果类型 |
| `lib/camera/protocol/props_parser.dart` | `ParsedProps`、`ParsedParam`、`CameraStatus`、`parseProps` |
| `lib/camera/protocol/protocol_profile.dart` | `ProtocolProfile`、`WriteEncoding`、`WsSupport`、`ProtocolProfileStore` |
| `lib/camera/http/camera_files.dart` | `CameraFile`、`parsePhotoList`、`parseCaptureTime` |
| `lib/camera/gateway/change_socket.dart` | `ChangeSocket`、`ChangeSocketEvent`、`DeviceScreen` 接口 |
| `lib/camera/gateway/fake_camera_model.dart` | 可编程模拟相机（props、写入、照片、拍摄、changes） |
| `lib/camera/sync/camera_state.dart` | `CameraState`、`SyncMode`、合并逻辑 |
| `lib/camera/sync/change_stream.dart` | WebSocket + 轮询兜底 |
| `lib/camera/sync/camera_state_controller.dart` | Riverpod 控制器，唯一状态源 |
| `lib/camera/capture/capture_tracker.dart` | `CaptureRecord`、`CaptureSource`、列表差分识别 |
| `lib/camera/live/live_view_controller.dart` | Live View 帧（从拍摄页提出来，供测光共用） |
| `lib/camera/live/live_frame_analyzer.dart` | 亮度均值与直方图（`dart:ui`） |
| `lib/camera/program/program.dart` | `Program`、`ProgramStep`、`ProgramContext` |
| `lib/camera/program/program_runner.dart` | 执行器与 `ProgramRunState` |
| `lib/camera/program/bracket_program.dart` | 自定义包围、配方包围 |
| `lib/camera/program/ramp_program.dart` | 计划渐变、测光渐变 |
| `lib/camera/program/program_controller.dart` | Riverpod 包装、屏幕常亮、日志持久化 |
| `lib/camera/recipe/combo_recipe.dart` | `ComboRecipe` |
| `lib/camera/recipe/recipe_store.dart` | 组合配方 / 标记 / 程序日志存取 |
| `lib/camera/recipe/recipe_session.dart` | 激活、脱离、打标记 |
| `lib/camera/recipe/tag_matcher.dart` | 标记 ↔ 本地照片匹配 |
| `lib/diagnostics/protocol_probe.dart` | 只读探测、写入格式探测、报告 |
| `lib/features/settings/protocol_probe_page.dart` | 探测页 |
| `lib/features/shoot/shoot_mode.dart` | `ShootMode` 与 UI 状态 |
| `lib/features/shoot/widgets/{top_bar,viewfinder,param_row,param_ruler,mode_carousel,bottom_bar,recipe_strip,more_grid,drive_options,program_sheet,dim_overlay,histogram}.dart` | 拍摄页组件 |
| `lib/features/shoot/widgets/recipe_editor_dialog.dart` | 新建组合配方 |

**新增（Kotlin）**：`android/app/src/main/kotlin/com/zhaoo/gremote/device/http/ChangeSocketClient.kt`、`android/app/src/test/kotlin/com/zhaoo/gremote/device/http/ChangeSocketClientTest.kt`

**修改**：`pubspec.yaml`、`pigeons/device_api.dart`（重新生成 `lib/platform/device_api.g.dart` 与 `DeviceApi.g.kt`）、`android/app/build.gradle`、`BoundCameraTransport.kt`、`GRemoteDeviceHostApi.kt`、`MainActivity.kt`、`lib/storage/gremote_database.dart`、`lib/camera/http/camera_api.dart`、`lib/camera/gateway/{native_gateways,fake_gateways}.dart`、`lib/app/router.dart`、`lib/features/home/home_page.dart`、`lib/features/shoot/shoot_page.dart`、`lib/features/library/{library_page,library_controller}.dart`、`lib/features/library/widgets/media_grid.dart`、`lib/darkroom/export/export_queue.dart`、相关测试。

---

## A1 · 参数引擎与曝光遥控

### Task 1: 依赖与数据库 v2

**Files:** Modify `pubspec.yaml`、`lib/storage/gremote_database.dart`；Test `test/storage/gremote_database_test.dart`

- [ ] `pubspec.yaml` dev_dependencies 增加 `fake_async: ^1.3.1`；`flutter pub get`。
- [ ] 写测试：新库 `version == 2` 且存在 `app_kv/combo_recipes/capture_tags/program_runs`；用 v1 建表语句手工建库（`version: 1`）后再 `GRemoteDatabase.open` 升级，四张表存在、`local_media` 数据保留。
- [ ] 实现：`version = 2`；`onCreate` = `_createV1` + `_createV2`；`onUpgrade: (db, old, _) async { if (old < 2) await _createV2(db); }`。`_createV2` 的 SQL 与 spec §12 完全一致。
- [ ] 运行 `flutter test test/storage/gremote_database_test.dart`，PASS。

### Task 2: 参数模型、props 解析与状态合并

**Files:** Create `camera_param.dart`、`props_parser.dart`、`camera_state.dart`、`test/fixtures/props_gr3_derived.json`；Test `test/camera/props_parser_test.dart`、`test/camera/camera_state_test.dart`

接口：

```dart
enum ParamEndpoint { camera, lens }

enum ParamKey {
  aperture('av'), shutter('tv'), iso('sv'), exposureComp('xv'),
  whiteBalance('WBMode'), metering('meteringMode'),
  focusSetting('focusSetting', endpoint: ParamEndpoint.lens),
  exposureMode('exposureMode', readOnly: true),
  drive('shootMode'), effect('effect'), aspectRatio('aspectRatio'),
  stillFormat('stillFormat');
  const ParamKey(this.wireKey, {this.endpoint = ParamEndpoint.camera, this.readOnly = false});
  final String wireKey; final ParamEndpoint endpoint; final bool readOnly;
  String get listKey => '${wireKey}List';
  static ParamKey? fromWire(String key);
}

class CameraParam {               // 不可变
  final String wireKey; final String? current; final List<String> options;
  final ParamEndpoint endpoint; final bool readOnly;
  bool get writable => !readOnly && options.length >= 2;
}

class ParsedParam { final String? current; final List<String>? options; }
class CameraStatus { final int? battery; final bool? hot; final int? remain;
  final String? liveState; final String? captureState; final String? captureId; }
class ParsedProps { final Map<String, ParsedParam> params; final CameraStatus status;
  final Map<String, String> keyTypes; }
ParsedProps parseProps(Map<String, Object?> json);
```

解析规则：标量（String/num/bool）→ `current = '$value'`；`xxxList` 且值为 List → 基键 `xxx` 的 `options`（元素逐个 `'$e'`）；状态键 `battery`（int，或 `{level:int}`）、`hot`（bool）、`storages`（List，取第一个含 `remain` 的 map）、`liveState`、`state`、`captureId`（标量）进入 `CameraStatus`，不进 params；其余非标量/非列表忽略；`keyTypes` 记录每个顶层键的类型名（`string/number/bool/list/object/null`）。

```dart
enum SyncMode { offline, polling, webSocket }
class CameraState {
  static const offline = CameraState(...);
  final Map<String, CameraParam> params;  // wireKey → param（已知 + extras）
  final CameraStatus status; final SyncMode syncMode; final bool writesEnabled;
  final Map<String, String> pending;      // wireKey → target
  final Map<String, String> keyTypes;
  CameraParam? param(ParamKey key) => params[key.wireKey];
  Iterable<CameraParam> get extras;       // 非 ParamKey 且 options 非空
  CameraState applyProps(ParsedProps p);  // 局部合并
  CameraState copyWith({...});
}
```

合并规则：已有键只覆盖 partial 中出现的部分（current 出现才覆盖 current，options 出现才覆盖 options）；新键：若是 ParamKey 或同时有 current 和 options 才加入；status 逐字段非空覆盖。

测试用例：fixture 解析出 av/tv/sv/xv/WBMode/effect/shootMode 且 `exposureMode` 不可写；`tvList` 为空 → `writable == false`；未知 `fooMode/fooModeList` 进入 extras；只有 `bar` 没有 `barList` 不进 extras；`storages:[{"remain":812}]` → remain 812；局部更新 `{"av":"4.0"}` 保留原 `avList`；`props.json`（旧 fixture）解析不抛错。

- [ ] 写测试 → 运行 FAIL → 实现 → PASS。

### Task 3: 曝光值解析

**Files:** Create `exposure_values.dart`；Test `test/camera/exposure_values_test.dart`

```dart
double? parseTvSeconds(String v);   // "1/250"→0.004, "2"→2, "2.5\""→2.5, "30s"→30, 其他 null
int? parseIso(String v);            // "200"→200, "auto"/其他→null
double? parseEv(String v);          // "+0.3"→0.3, "-1/3"→-0.333.., "0"→0
double log2(double x);
/// 在 options 中找 log2(value) 最接近 target 的项；不可解析项跳过；全部不可解析返回 null。
String? nearestByLog(List<String> options, double target, double? Function(String) parse, {double? max});
bool allParse(List<String> options, Object? Function(String) parse, {Set<String> allow = const {}});
```

- [ ] 测试覆盖上面每种格式、`max` 限制、全部不可解析 → 实现 → PASS。

### Task 4: 协议画像

**Files:** Create `protocol_profile.dart`；Test `test/camera/protocol_profile_test.dart`

```dart
enum WriteEncoding { query, form, json, unknown }
enum WsSupport { supported, unsupported, unknown }
class ProtocolProfile { final String firmware; final WriteEncoding writeEncoding;
  final WsSupport webSocket; final DateTime? probedAt;
  factory ProtocolProfile.initial(String firmware); toJson(); fromJson(); copyWith(); }
class ProtocolProfileStore { ProtocolProfileStore(Database db);
  Future<ProtocolProfile> load(String firmware);    // 无记录 → initial
  Future<void> save(ProtocolProfile p); }           // app_kv key 'protocolProfile:<fw>'
final protocolProfileStoreProvider = Provider((ref) => ProtocolProfileStore(ref.watch(databaseProvider)));
```

- [ ] 测试 JSON 往返、未知枚举值回落 unknown、store 读写（sqflite ffi 内存库）→ 实现 → PASS。

### Task 5: CameraApi 扩展与照片列表

**Files:** Create `camera_files.dart`；Modify `camera_api.dart`；Test `test/camera/camera_api_test.dart`（追加）、`test/camera/camera_files_test.dart`

```dart
class CameraFile { final String dir; final String file;
  String get baseName; String get extension; String get remoteId => '$dir/$file'; }
List<CameraFile> parsePhotoList(Map<String, Object?> json);
// 支持 {"dirs":[{"name":"100RICOH","files":["R0001.JPG"]}]}；dirs 缺失返回空
int? parseCaptureWallSeconds(Map<String, Object?> info);
// 依次尝试 datetime/dateTime/captureDate/date；格式 "YYYY-MM-DDTHH:MM:SS" 或 "YYYY:MM:DD HH:MM:SS"
int? exifWallSeconds(String? takenAt);  // PhotoMeta.takenAt
```

`CameraApi` 新增：

```dart
Future<Map<String, Object?>> putParams(ParamEndpoint endpoint, Map<String, String> values, WriteEncoding encoding);
// query: PUT /v1/params/<ep>?k=v（Uri 编码）；form: body k=v&...，Content-Type application/x-www-form-urlencoded；
// json: body jsonEncode(values)，Content-Type application/json；unknown → ArgumentError。
// 2xx 但 errCode 存在且不为 200 → CameraApiException(code: 'cameraError')。
Future<List<CameraFile>> photos();
Future<Map<String, Object?>> photoInfo(CameraFile f);
Future<Uint8List> thumbnail(CameraFile f);   // GET /v1/photos/<dir>/<file>?size=thumb，非 2xx 抛 httpStatus
Future<Map<String, Object?>> revisions();
Future<Map<String, Object?>> cancelShoot();
```

- [ ] 测试三种编码的 method/path/header/body、errCode 判定、photos 解析、两种时间格式 → 实现 → PASS。

### Task 6: 参数写入器

**Files:** Create `param_writer.dart`；Test `test/camera/param_writer_test.dart`

```dart
sealed class WriteOutcome {}
class WriteConfirmed extends WriteOutcome { final String value; }
class WriteCorrected extends WriteOutcome { final String actual; }
class WriteRejected extends WriteOutcome { final String code; final String? message; }
class WriteTimedOut extends WriteOutcome {}
class WriteSuperseded extends WriteOutcome {}
class WritesDisabled extends WriteOutcome {}

class ParamWriter {
  ParamWriter({
    required Future<Map<String, Object?>> Function(ParamEndpoint, Map<String, String>, WriteEncoding) send,
    required Future<String?> Function(String wireKey) refreshAndRead,
    required WriteEncoding Function() encoding,
    required Future<void> Function(WriteEncoding) rememberEncoding,
    required void Function() disableWrites,
    Duration timeout = const Duration(seconds: 3),
  });
  Future<WriteOutcome> write(CameraParam param, String value);
  bool get busy;
}
```

行为：全局串行；每个 wireKey 最多一个排队值，新值让旧排队 future 以 `WriteSuperseded` 完成；`encoding()` 为 unknown 时依次 query→form→json，首个成功调用 `rememberEncoding`，三种都抛 `CameraApiException` → `disableWrites()` 并返回 `WritesDisabled`；已知编码失败 → `WriteRejected(cameraCode ?? code, cameraMessage)`；成功后响应含该键则以其为回读，否则 `refreshAndRead`；回读 == 目标 → Confirmed，否则 Corrected；整体超过 timeout → TimedOut。

- [ ] 测试：串行（第二个 send 在第一个完成后才开始）、合并、格式回退并记住、全部失败禁用、回读修正、超时（fake_async）→ 实现 → PASS。

### Task 7: 原生 WebSocket、屏幕常亮与网关

**Files:** Modify `pigeons/device_api.dart`、生成文件、`android/app/build.gradle`、`BoundCameraTransport.kt`、`GRemoteDeviceHostApi.kt`、`MainActivity.kt`、`native_gateways.dart`、`fake_gateways.dart`；Create `ChangeSocketClient.kt`、`ChangeSocketClientTest.kt`、`change_socket.dart`、`fake_camera_model.dart`

Pigeon `CameraDeviceHostApi` 增加：

```dart
@async void openChangeSocket(String path);
@async void closeChangeSocket();
void setKeepScreenOn(bool on);
```

生成：`dart run pigeon --input pigeons/device_api.dart`。

`ChangeSocketClient(client: OkHttpClient, emit: (String, String) -> Unit)`：`open(url)` 先关闭旧连接，新建 `WebSocket`，监听器只在 `socket === current` 时发事件：`changes.open` `{}`；`changes.message` `{"text":...}`（`JSONObject().put("text", text)`）；`onClosing` 调 `close(1000, null)`；`changes.closed` `{"code":n}`；`changes.failure` `{"status":n}` 或 `{}`。`close()` 关闭当前并置空。
`BoundCameraTransport`：`private val changeSocket = ChangeSocketClient(client.newBuilder().readTimeout(0, SECONDS).build(), emitEvent)`；`openChangeSocket(path)` = `changeSocket.open(resolve(path).replaceFirst("http://", "ws://"))`；`close()` 先 `changeSocket.close()`。
`GRemoteDeviceHostApi` 构造增加 `private val keepScreenOn: (Boolean) -> Unit`；`MainActivity` 传 `{ on -> runOnUiThread { if (on) window.addFlags(FLAG_KEEP_SCREEN_ON) else window.clearFlags(FLAG_KEEP_SCREEN_ON) } }`。
`build.gradle` 增加 `testImplementation "com.squareup.okhttp3:mockwebserver:4.12.0"`、`testImplementation "org.json:json:20240303"`（JVM 单测里 android 的 org.json 是桩）。

Dart：

```dart
sealed class ChangeSocketEvent {}
class ChangeSocketOpened / ChangeSocketMessage(String text) / ChangeSocketClosed(int? code) / ChangeSocketFailed(int? status)
abstract interface class ChangeSocket { Stream<ChangeSocketEvent> get events; Future<void> open(String path); Future<void> close(); }
abstract interface class DeviceScreen { Future<void> setKeepScreenOn(bool on); }
ChangeSocketEvent? changeSocketEventFrom(CameraDeviceEvent e);  // 解析 changes.* 事件
```

`CameraGatewayBundle` 增加 `ChangeSocket get changes; DeviceScreen get screen;`。Native 实现基于 `_callbacks.events` 过滤；Fake 实现转到 `FakeCameraModel`。

`FakeCameraModel`（模拟相机，`FakeCameraGateways` 持有）：初始 props 取自固件推导值（av 2.8、tv 1/250、sv 200、xv 0.0、WBMode auto、meteringMode multi、exposureMode Av、shootMode single、effect standard、各 List、storages remain 812、battery 82）；`handle(method, path, body)` 处理 props/params（query/form/json 均接受，exposureMode 拒绝）/shoot（生成 `R000NNNN.JPG`，remain-1，向 socket 推 `{"captureId":..,"state":"complete","remain":..}`）/photos/info/thumb；写参数后推 `{"<key>":"<value>"}`；可配置 `acceptEncodings`、`webSocket` 是否可用，供测试模拟 H3/H4 失败。现有 `/v1/ping`、`/v1/props` trace 名保持不变。

- [ ] Kotlin 测试（MockWebServer `withWebSocketUpgrade`）：open 发 `changes.open`、服务端消息转 `changes.message`、服务端关闭发 `changes.closed`、重开后旧连接事件被忽略 → 实现 → `./gradlew :app:testDebugUnitTest` PASS。
- [ ] Dart 测试 `test/camera/change_socket_test.dart`：`changeSocketEventFrom` 解析四类事件；`FakeCameraModel` 写入后推送、拍摄生成文件。

### Task 8: 变化同步

**Files:** Create `change_stream.dart`；Test `test/camera/change_stream_test.dart`

```dart
class ChangeStream {
  ChangeStream({
    required ChangeSocket socket,
    required Future<Map<String, Object?>> Function() fetchProps,
    required void Function(Map<String, Object?> json, {required bool full}) onProps,
    required void Function(SyncMode) onMode,
    required void Function(WsSupport) onSupport,
    required WsSupport initialSupport,
    Duration pollInterval = const Duration(seconds: 1),
  });
  Future<void> start();          // unsupported → 直接轮询模式；否则 open('/v1/changes')
  Future<void> stop();
  void setPollingAllowed(bool allowed);  // 拍摄页可见且前台
  Future<void> refresh();        // 全量刷新，onProps(full: true)
}
```

行为：`ChangeSocketOpened` → mode webSocket、`onSupport(supported)`、失败计数清零、`refresh()`；消息 JSON 对象 → `onProps(full:false)`，非对象忽略；`Closed/Failed` → mode polling，若从未 open 过则失败计数 +1，达到 3 → `onSupport(unsupported)` 不再重连，否则按 1/2/4/8/16/30 秒退避重连；轮询定时器仅在 mode == polling 且 allowed 时每秒 `refresh()`，刷新异常吞掉（由控制器记诊断）。

- [ ] 测试（fake_async）：消息合并、三次握手失败后不再 open 且开始轮询、断线退避时间序列、不允许时不轮询 → 实现 → PASS。

### Task 9: 拍摄完成识别

**Files:** Create `capture_tracker.dart`；Test `test/camera/capture_tracker_test.dart`

```dart
enum CaptureSource { app, body, program }
enum TimeSource { camera, phone }
class CaptureRecord { final String dir; final String baseName; final List<String> files;
  final int wallSeconds; final TimeSource timeSource; final String? effect;
  final CaptureSource source; final String? programRunId; final String? recipeId; }
class CaptureContext { final String? effect; final CaptureSource source; final String? programRunId; final String? recipeId; }

class CaptureTracker {
  CaptureTracker({ required Future<List<CameraFile>> Function() listPhotos,
    required Future<int?> Function(CameraFile) captureWallSeconds,
    required int Function() phoneWallSeconds,
    Duration poll = const Duration(seconds: 1) });
  Future<void> prime();                                 // 记录基线列表
  Future<List<CaptureRecord>> detect(CaptureContext ctx, {required Duration timeout});
  Stream<CaptureRecord> get records;
  static Duration timeoutFor(String? tv);  // max(10s, tvSeconds*2+5s)
}
```

行为：`detect` 立即差分一次，无新文件则每 `poll` 重试直到超时；新文件按 `baseName`（同目录）分组生成记录；时间取组内第一个文件的 info，失败用手机墙钟；更新基线；并发调用共用同一个进行中的 future（后到的 ctx 若 source 为 app/program 则覆盖 body）。超时返回空列表。

- [ ] 测试：RAW+JPEG 合并为一条、info 无时间回落 phone、超时空列表、并发合并 → 实现 → PASS。

### Task 10: 相机状态控制器

**Files:** Create `camera_state_controller.dart`；Test `test/camera/camera_state_controller_test.dart`

```dart
final cameraStateControllerProvider = NotifierProvider<CameraStateController, CameraState>(CameraStateController.new);
class CameraStateController extends Notifier<CameraState> {
  Stream<CaptureRecord> get captures;
  Future<WriteOutcome> setParam(String wireKey, String value);
  Future<List<CaptureRecord>> shootAndAwait({required bool autoFocus, required CaptureContext ctx});
  Future<void> refresh();
  void setShootPageActive(bool active);   // 驱动 ChangeStream.setPollingAllowed
  CameraApi get api;
}
```

行为：监听 `connectionControllerProvider`；进入 `ConnectionReady` 时以 `snapshot.identity.firmware` 加载画像、`refresh()`、`tracker.prime()`、`changeStream.start()`；离开 ready 时停止并回到 `CameraState.offline`；`onProps` 合并后若 `remain` 变小或 `captureId` 变化且当前没有 app/program 拍摄在途 → `tracker.detect(CaptureContext(source: body, effect: 当前 effect))`；写入期间 `pending[wireKey] = target`，完成后移除；写入成功后由写入器回读；`AppLifecycleListener` 回前台 `refresh()`；props 连续 5 次失败写诊断事件 `stage: 'props', exceptionCode: 'propsUnavailable'`。

- [ ] 测试（ProviderContainer + FakeCameraGateways(stepDelay: 0) + 内存库）：连接后 state.params 有 av；`setParam('sv','400')` 后 state 为 400；模拟相机推送 `{"av":"5.6"}` 后 state 更新；`shootAndAwait` 返回 1 条记录；断开后 offline → 实现 → PASS。

### Task 11: Live View 控制器与帧分析

**Files:** Create `live_view_controller.dart`、`live_frame_analyzer.dart`；Test `test/camera/live_view_controller_test.dart`

```dart
final liveViewControllerProvider = NotifierProvider<LiveViewController, Uint8List?>(...);
class LiveViewController extends Notifier<Uint8List?> { void attach(); void detach(); String? get error; }
// 引用计数 > 0 且 ConnectionReady 时 startLiveView，否则 stop；帧经 LiveViewParser 取最后一帧
class FrameStats { final double meanLuma; final List<int> histogram; }  // 64 bins, luma 0..1
abstract interface class LiveFrameAnalyzer { Future<FrameStats?> analyze(Uint8List jpeg); }
class UiLiveFrameAnalyzer implements LiveFrameAnalyzer { ... instantiateImageCodec(targetWidth: 64) ... }
final liveFrameAnalyzerProvider = Provider<LiveFrameAnalyzer>((_) => UiLiveFrameAnalyzer());
FrameStats statsFromRgba(Uint8List rgba);  // 纯函数，可测
```

- [ ] 测试 `statsFromRgba`（全白 mean≈1、直方图落在末格）、attach/detach 触发 start/stop（Fake trace）→ 实现 → PASS。

### Task 12: 协议探测

**Files:** Create `protocol_probe.dart`、`protocol_probe_page.dart`；Modify `router.dart`（`GoRoute('/probe')`）、`home_page.dart`（诊断面板加「协议探测」按钮）；Test `test/diagnostics/protocol_probe_test.dart`

```dart
class ProbeReport { final Map<String, int?> routes; final Map<String, String> keyTypes;
  final Map<String, List<String>> lists; final WsSupport webSocket; final int eventsIn10s;
  final Map<WriteEncoding, bool>? writeResults; Map<String, Object?> toJson(); }
class ProtocolProbe { ProtocolProbe({required CameraApi api, required ChangeSocket socket, Duration listen = const Duration(seconds: 10)});
  Future<ProbeReport> run({required bool includeWrite}); }
```

只读：ping/props/debug/revisions/photos 记录 HTTP 状态（异常记 null）；props 的 keyTypes 与全部 `xxxList`；`ssid/serialNo/macAddress/key` 的值不出现在报告中；photos 只记文件数（`routes['/v1/photos#count']`）。写入：读取 `xv` 当前值，三种编码各写一次同值，结果记 true/false，每次后读 props 校验 `xv` 未变（变了则立即写回并标 false）。页面：两个按钮（只读探测 / 含写入探测，后者先弹确认框）、结果列表、「复制 JSON」（`{"schema":"gremote-diagnostics/1","protocolProfile":report}`），探测完成后把 writeEncoding（首个 true）和 webSocket 存入画像。

- [ ] 测试（FakeCameraModel）：报告含 av 列表、不含 ssid 值、写入探测三种都 true 且 xv 不变；模拟只接受 form → `writeResults` 只有 form 为 true → 实现 → PASS。

### Task 13: 拍摄页框架（拍照 + 专业）与全屏

**Files:** Rewrite `shoot_page.dart`；Create `shoot_mode.dart`、`widgets/{top_bar,viewfinder,param_row,param_ruler,mode_carousel,bottom_bar,more_grid,histogram}.dart`；Modify `router.dart`（拍摄分支始终隐藏导航，沉浸式状态栏）；Test `test/features/shoot_page_test.dart`

```dart
enum ShootMode { more, timelapse, bracket, photo, pro }  // 轮播顺序
```

布局按 spec §10.2，取景区 `AspectRatio(3/4)` 内居中 `AspectRatio(3/2)` 的 Live View；Key 约定：`shutter-button`（保留）、`af-button`、`mode-<name>`、`param-<wireKey>`、`ruler`、`ruler-auto`、`aspect-<value>`、`recipe-toggle`。参数行只列可用的 WB/F/S/ISO/EV/测光；点不可写项 SnackBar「由机身决定」；刻度尺 `ListWheelScrollView` 横向（`RotatedBox`）以 options 为刻度，停止 2 秒自动收起，滚动停止时调用 `setParam`，pending 时值旁显示 `CircularProgressIndicator(strokeWidth: 1)`；顶栏机身档位读 `exposureMode`；⏱ 在 single/self2s/self10s 中循环；▥ 开关直方图（每 500ms 分析一次最新帧）；左下缩略图来自最近一条 CaptureRecord 的 `api.thumbnail`，点击 `context.go('/library')`；`PopScope` 拦截返回到 `/home`；进入时 `setShootPageActive(true)`，离开 false；未连接时取景显示「连接相机后显示取景画面」与「前往连接」。横屏：Row[参数列, 取景, 控制列]。

- [ ] Widget 测试：进入拍摄页底部导航消失；专业模式显示参数行，S 灰显；点 ISO 出现 ruler；拍照模式画幅圆点按列表出现；320×568 + 1.4 字号不溢出 → 实现 → PASS。
- [ ] 更新 `test/app/router_test.dart` 与 `test/features/mock_camera_flow_test.dart` 以适配新页面（「前往连接」仍可用；回首页改为 `appRouter.go('/home')` 或返回手势）。

---

## A2 · 驱动模式与程序拍摄

### Task 14: 程序抽象与执行器

**Files:** Create `program.dart`、`program_runner.dart`；Test `test/camera/program_runner_test.dart`

```dart
class ProgramStep { final Map<String, String> params; final String? recipeId; }
class ProgramContext { final CameraState state; final double nudgeEv; final int index; }
abstract class Program {
  String get kind; String get label; int get frameCount;
  Duration? get interval;                       // null = 连拍
  bool get supportsNudge;
  String? refusal(CameraState s);
  Future<ProgramStep> step(ProgramContext ctx);
}
enum RunPhase { idle, preparing, refused, running, paused, completed, aborted }
class ProgramRunState { final RunPhase phase; final String? kind; final int done; final int total;
  final DateTime? nextAt; final String? reason; final double nudgeEv; final String? runId; }
abstract interface class ProgramCamera {
  CameraState get state;
  Future<WriteOutcome> setParam(String wireKey, String value);
  Future<List<CaptureRecord>> shootAndAwait({required bool autoFocus, required CaptureContext ctx});
}
class ProgramRunner {
  ProgramRunner({required ProgramCamera camera, required void Function(ProgramRunState) onState,
    DateTime Function() now = DateTime.now, String Function()? newId});
  Future<void> start(Program p, {bool autoFocusFirst = false});
  void pause(String reason); Future<void> resume(); Future<void> abort(); void nudge(double ev);
  ProgramRunState get state; List<Map<String, Object?>> get log;
}
```

行为严格按 spec §8.2：preparing 时 refusal → refused；快照全部可写 params 的 current；若 `shootMode` 可写且不是 single 则写 single；第 i 张计划时刻 `start + i*interval`；每步只写与当前不同的键，`WriteConfirmed` 以外视为失败；shoot ctx `source: program, programRunId, recipeId: step.recipeId, effect: 写后 effect`；记录为空视为失败；失败 1 秒后重试一次，再失败 `paused('failure')`；paused 时等待 `resume()`，resume 从当前 index 继续（重拍失败的那一张）；完成/终止后按快照恢复改动过的键（失败只记日志）。

- [ ] 测试（fake_async + 内存 ProgramCamera）：按计划时刻拍摄、overrun 记入日志、失败重试后暂停、resume 继续、abort 恢复参数、refusal → 实现 → PASS。

### Task 15: 包围程序

**Files:** Create `bracket_program.dart`；Test `test/camera/bracket_program_test.dart`

```dart
class CustomBracketProgram extends Program {
  CustomBracketProgram({required this.wireKey, required this.centerIndex, required this.count, required this.stepIndices});
  // 偏移序列 0,-s,+s,-2s,+2s…取前 count 个，越界丢弃；frameCount = 有效帧数；refusal：参数不可写/count∉2..15
  static List<int> offsets(int count, int step);
}
class RecipeBracketProgram extends Program {
  RecipeBracketProgram(List<ComboRecipe> recipes);   // 2..8，effect 非空；refusal：effect 不可写或 effect 不在 effectList
}
```

- [ ] 测试偏移序列、越界丢弃、配方包围每步 params 与 recipeId → 实现 → PASS。

### Task 16: 渐变程序

**Files:** Create `ramp_program.dart`；Test `test/camera/ramp_program_test.dart`

```dart
class ExposurePair { final String tv; final String sv; }
class PlannedRampProgram extends Program {
  PlannedRampProgram({required ExposurePair start, required ExposurePair end, required int frames,
    required Duration interval, double? maxShutterSeconds});
  // brightness E = log2(t) + log2(iso/100)；E_i = E0 + (E1-E0)*i/(n-1) + nudge
  // isoBase = parseIso(start.sv)；t = 2^E/(isoBase/100)；t>cap → t=cap，iso=100*2^E/cap
  // tv=nearestByLog(tvList, log2(t), parseTvSeconds, max: cap)；sv=nearestByLog(numeric svList, log2(iso), …)
  // cap 默认 min(interval-1s, 30s)；refusal：exposureMode != 'M' / tv、sv 不可写 / 列表无法解析 / sv 为 auto
}
class MeteredRampProgram extends PlannedRampProgram {
  MeteredRampProgram({..., required Future<double?> Function() meter});
  // 第一帧记录目标亮度；之后 ΔEV=log2(target/current)，|Δ|<1/6 忽略，clamp ±1/3，累加到内部偏移
}
```

- [ ] 测试：起止插值端点、快门到上限后提 ISO、量化取最近值、nudge 平移、测光死区与步长、M 档前置条件 → 实现 → PASS。

### Task 17: 程序控制器与驱动 UI

**Files:** Create `program_controller.dart`、`widgets/{drive_options,program_sheet,dim_overlay}.dart`；Modify `shoot_page.dart`、`recipe_store.dart`（若 Task 18 未完成，先在本任务内建 `ProgramRunStore`，Task 18 合并进 RecipeStore——执行时按顺序先做 Task 18 的存储部分）；Test `test/features/shoot_program_test.dart`、`test/camera/program_controller_test.dart`

```dart
final programControllerProvider = NotifierProvider<ProgramController, ProgramRunState>(...);
class ProgramController extends Notifier<ProgramRunState> {
  Future<void> start(Program p); void pause(); Future<void> resume(); Future<void> abort(); void nudge(double ev);
}
```

行为：running/paused 时 `screen.setKeepScreenOn(true)`，其他 false；app 进入 `paused/hidden` 生命周期或连接离开 ready → `pause('background'/'disconnected')`；`state.status.hot == true` → `pause('hot')` 并拒绝新程序；运行结束把 `{kind, config, state, done, log}` 写入 `program_runs`（只保留 50 条）。
UI：包围/延时模式子选项 = 原生项（`shootModeList` 中按前缀分组，选中写 `shootMode`，下方提示「张数与间隔在机身菜单中设置」）+ 手机项（带「手机」标注，选中弹出 `program_sheet`）；`program_sheet` 表单字段与 spec §8.3 一致，「开始」调用 `start`；运行中：快门变红色方块（停止）、副键变暂停/继续、顶栏左侧进度、右侧 ☾、取景提示条显示下一张倒计时与参数、渐变程序显示 ±⅓；模式轮播锁定；`dim_overlay` 95% 黑色、一行进度、点击移除。测光渐变开关放在 ≡ 设置面板「实验功能」，默认关，开启时提示温度风险。

- [ ] 测试：开始程序后保持常亮被调用、轮播锁定、暗屏出现与移除、停止后恢复 → 实现 → PASS。

---

## A3 · 组合配方

### Task 18: 组合配方与存储

**Files:** Create `combo_recipe.dart`、`recipe_store.dart`；Test `test/camera/recipe_store_test.dart`

```dart
class ComboRecipe { final String id; final String name; final String? effect;
  final String? exportPresetId; final int sort; final DateTime createdAt;
  static final factory = ComboRecipe(id: 'factory', name: '原厂', ...);   // 只读，不入库
  bool get isFactory => id == 'factory'; }
class CaptureTag { final int id; final String baseName; final String dir; final int wallSeconds;
  final TimeSource timeSource; final String recipeId; final String? effect; final String? programRunId; final bool confirmed; }
class RecipeStore {
  RecipeStore(Database db, {DateTime Function()? clock});
  Future<List<ComboRecipe>> recipes(); Future<ComboRecipe> create({required String name, String? effect, String? exportPresetId});
  Future<void> delete(String id);
  Future<void> addTag(CaptureRecord r, String recipeId);
  Future<List<CaptureTag>> tagsForBaseNames(Iterable<String> names); Future<void> confirmTag(int id);
  Future<void> saveRun(Map<String, Object?> run);    // 超过 50 条删最旧
}
final recipeStoreProvider = Provider((ref) => RecipeStore(ref.watch(databaseProvider)));
```

- [ ] 测试 CRUD、排序、名字 >24 抛 ArgumentError、删除配方保留标记、run 只保留 50 条 → 实现 → PASS。

### Task 19: 配方会话

**Files:** Create `recipe_session.dart`；Test `test/camera/recipe_session_test.dart`

```dart
class RecipeSessionState { final ComboRecipe active; final bool detached; final bool switching; }
final recipeSessionProvider = NotifierProvider<RecipeSession, RecipeSessionState>(...);
class RecipeSession extends Notifier<RecipeSessionState> {
  Future<WriteOutcome?> activate(ComboRecipe r);  // effect 为空直接激活；否则 setParam('effect') 确认后激活
}
```

行为：监听 camera state，`active` 非原厂且 effect 非空、相机 effect ≠ 目标 → detached；监听 `captures`：`record.recipeId` 非空 → 用它打标记；否则 active 非原厂且未脱离 → 用 active 打标记；连接离开 ready → 重置为原厂。

- [ ] 测试激活、脱离、配方包围记录优先、原厂不打标记 → 实现 → PASS。

### Task 20: 标记匹配、图库与按配方导出

**Files:** Create `tag_matcher.dart`；Modify `export_queue.dart`、`library_controller.dart`、`library_page.dart`、`media_grid.dart`；Test `test/camera/tag_matcher_test.dart`、`test/darkroom/export_queue_test.dart`（追加）、`test/features/library_page_test.dart`（追加）

```dart
enum MatchStrength { strong, weak }
class TagMatch { final CaptureTag tag; final MatchStrength strength; bool get usable => strength == MatchStrength.strong || tag.confirmed; }
TagMatch? matchTag(LocalMediaItem item, List<CaptureTag> tags);
// baseName = displayName 去扩展名（大小写不敏感）；camera：|exifWall - tag| ≤ 2；phone：≤ 12h → weak；多个候选取差值最小
String baseNameOf(String displayName);
```

`ExportQueueController.startEach(List<(LocalMediaItem, ExportRecipe)> jobs)`；`start(items, recipe)` 改为调用它。
`LibraryState` 增加 `tags: Map<int, TagMatch>`、`recipeOnly: bool`；`_reload` 后用 `RecipeStore.tagsForBaseNames` 计算；`setRecipeOnly`、`confirmSelectedTags()`、`recipeJobs()`（返回可导出的 (item, recipe) 与跳过数，配方需有 `exportPresetId` 且 preset 存在）。
UI：筛选行增加 ChoiceChip「按配方」；`MediaTile` 增加 `badge`（usable：金色 ◍；weak 未确认：灰色「待确认」）；选择栏增加「按配方导出」（跳过数 > 0 先弹提示）与「确认配方」（仅选中项含 weak 时显示）。

- [ ] 测试：强/弱匹配、文件名循环取最近、`startEach` 每张不同配方、图库按配方筛选与导出入队 → 实现 → PASS。

### Task 21: 配方条与新建配方

**Files:** Create `widgets/recipe_strip.dart`、`widgets/recipe_editor_dialog.dart`；Modify `shoot_page.dart`、`top_bar.dart`；Test `test/features/shoot_recipe_test.dart`

行为：◍ 切换配方条（拍照/专业/包围/延时模式均可）；条目 = 原厂 + 已建配方 + 「＋ 新建」；缩略图：有 exportPresetId 时用 `lutLibraryProvider` + `imagingEngine.applyLut` 对样张缩略预览（失败/无 LUT 用渐变色块），文字叠加 effect 名；点选调用 `activate`，取景顶部提示条显示配方名 2 秒；脱离时图标灰色加红点，提示条「已脱离」；新建对话框：名称（≤24）、effect 下拉（`effectList`）、出图方案下拉（`darkroomStore.presets()`，可选「不自动出图」）。配方包围的 program_sheet 从这里的配方列表多选。若 `effectList` 缺失，配方条顶部提示「相机未报告机内配方」。

- [ ] 测试：打开配方条、新建配方出现在条目里、点选后 effect 写入模拟相机、机身改 effect 后显示已脱离 → 实现 → PASS。

---

## 收尾

### Task 22: 回归与构建

- [ ] 扩展 `integration_test/mock_camera_flow_test.dart`：连接 → 专业模式改 ISO → 新建配方并配方包围 3 张 → 断言模拟相机产生 3 个文件且 effect 序列正确。
- [ ] `flutter analyze` 无问题；`flutter test` 全部通过。
- [ ] `cd android && ./gradlew :app:testDebugUnitTest` 通过；`scripts/build_android.sh`（或 `flutter build apk --debug --target-platform android-arm64`）成功。
- [ ] 更新 `docs/protocol/gr3-stock-api.md`：补充 §2.1 的参数键与路由，状态均为 `firmware-confirmed / hardware-unverified`；`docs/testing/gr3-hardware-gate-1.md` 追加 spec §15 的检查项（状态 `not-run`）。
- [ ] 按 4.md 规则发起一次 CodeReview。

---

## Spec 覆盖自检

| Spec 章节 | 任务 |
|---|---|
| §5.1 参数表 / 显示规则 | 2、3、13 |
| §5.2 协议画像 / 写入格式 | 4、5、6、12 |
| §5.3 变化同步 | 7、8、10 |
| §6 状态与写入生命周期 | 2、6、10、13 |
| §7 拍摄完成识别 | 5、9、10 |
| §8.1 原生驱动 | 17 |
| §8.2 执行器 | 14、17 |
| §8.3 四种程序 | 15、16、17 |
| §9 组合配方 / 会话 / 匹配 / 导出 | 18、19、20、21 |
| §10 界面 / 全屏 / 横屏 | 13、17、21 |
| §11 协议探测 | 12 |
| §12 存储 | 1、18 |
| §13 错误处理 | 6、8、10、14、17 |
| §14 测试 | 各任务 + 22 |
| §15 真机清单 | 22 |
