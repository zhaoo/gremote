# gremote 遥控拍摄设计（三期）

本设计细化主 spec（`2026-10-09-gremote-design.md`）§7「拍摄与实时取景」，并接入二期出图管线（`2026-10-10-gremote-export-pipeline-design.md`）。全部能力只使用 GR III 2.10 原厂 Wi‑Fi 接口，不修改固件。

## 1. 范围

本期交付三个部分，**设计一次完成，实现严格按 A1 → A2 → A3 顺序进行**：

- **A1 参数引擎 + 曝光遥控**：协议探测、能力协商、参数写入、变化同步，以及「拍照 / 专业」两个模式；
- **A2 驱动模式 + 程序拍摄**：相机原生驱动模式的切换和进度显示；手机编排的自定义包围、配方包围、计划渐变延时，以及实验性的测光渐变延时；
- **A3 组合配方**：远程切换机内 effect；组合配方 = 机内 effect + 出图方案；拍摄时打标记，图库按标记批量导出。

不在本期：相机下载流水线（主 spec §8）、机内图像控制细节参数（饱和度、色相等只在 USB PTP 中出现）、35/50mm 裁切（Wi‑Fi 接口中没有对应字段）、息屏后台执行、iOS、固件补丁。

## 2. 证据与假设

### 2.1 固件已确认（`webapid` 静态字符串，均未上真机）

- 路由：`GET /v1/props`、`PUT /v1/params/camera`、`PUT /v1/params/lens`、`PUT /v1/params/device`、`GET /v1/changes`、`POST /v1/camera/shoot`、`POST /v1/camera/shoot/cancel`、`POST /v1/camera/shoot/compose`、`GET /v1/photos`、`GET /v1/photos/{dir}/{file}/info`、`GET /v1/debug/revisions`。
- 参数键：`av/avList`、`tv/tvList`、`sv/svList`、`xv/xvList`、`WBMode/WBModeList`、`exposureMode/exposureModeList`、`meteringMode/meteringModeList`、`focusMode`、`focusSetting/focusSettingList`、`effect/effectList`、`shootMode/shootModeList`、`captureMode/captureModeList`、`aspectRatio`、`stillFormat/stillFormatList`、`stillSize/stillSizeList`。
- 状态键：`battery`、`hot`、`storages`（含 `remain`）、`liveState`、`captureId`、`state`、`stateStill`、`stateMovie`、`focused`。
- 驱动模式取值：`bracket`、`dofBracket`、`interval`、`intervalComp`、`intervalMovie`，以及 `Self2s / Self10s / Self12s / Remocon / Remocon3s` 变体。
- 白平衡取值：`auto`、`daylight`、`shade`、`tungsten`、`daylightFluorescent`、`manual1–3`、`cte`。
- 写入解析：`ParseKeyValuesString`（`key=value`）。
- 推送：crow WebSocket 处理函数，日志 `/v1/changes issue event.`；事件类型 `CaptureEvent`、`LensEvent`、`StorageEvent`、`TransferEvent`。

### 2.2 待真机验证的假设

| 编号 | 假设 | 验证手段 | 若不成立 |
|---|---|---|---|
| H1 | `/v1/props` 是扁平 JSON，参数用 `x` 加 `xList` 表示 | 协议探测 | 解析器按 extras 兜底，已知控件隐藏 |
| H2 | 当前模式下不可写的参数，其 `xList` 为空或只有一项 | 协议探测 + 机身切换 Av/Tv/M | 改为按 `exposureMode` 查静态可写表 |
| H3 | 写入格式是 query、form、JSON 三者之一 | 写入格式探测 | 写入功能全部禁用，只读遥控 |
| H4 | `/v1/changes` 是 WebSocket 端点，推送内容是 props 的局部 JSON | 探测握手 + 监听 10 秒 | 永久轮询 |
| H5 | 驱动模式通过 `shootMode` 设置 | 探测 `shootModeList` | 改为 `captureMode`，仍不行则隐藏原生驱动 |
| H6 | 间隔、张数等原生驱动参数不能通过 webapi 写入 | 探测 extras | 若能写，则在子选项里提供设置 |
| H7 | `/v1/photos/{dir}/{file}/info` 含拍摄时间 | 探测 | 改用拍摄完成事件时间（弱匹配） |
| H8 | Live View 显示机内 effect 效果 | 真机目测 | 配方条提示「取景不含配方效果」 |

所有依赖 H1–H8 的代码在注释和诊断中标为 `firmware-derived / hardware-unverified`。

## 3. 实现顺序与门禁

1. **A1**：协议层、状态同步、协议探测、拍照/专业模式、全屏拍摄页框架。
2. **A2**：在 A1 引擎上增加原生驱动和程序拍摄。
3. **A3**：在 A1/A2 上增加组合配方、标记、图库联动。

每个子项目单独出可安装 APK，标为「已开发 / 待真机门禁」。真机拿到后先执行协议探测，按结果修正 H1–H8，再执行 §15 的验证清单。

## 4. 模块与职责

### 4.1 Dart `lib/camera/`（不依赖 UI）

| 模块 | 职责 |
|---|---|
| `protocol/props_parser.dart` | 宽容解析 props：已知键转强类型；其余符合 `x` + `xList` 的键进入 extras；缺失不报错；同时输出「键名 → 类型」快照供探测使用 |
| `protocol/protocol_profile.dart` | 协议画像模型与持久化：写入格式、WebSocket 可用性、探测时间、固件版本 |
| `params/camera_param.dart` | `ParamKey` 枚举、`CameraParam`、显示格式化 |
| `params/param_writer.dart` | 串行写入队列、同参数合并、待确认状态、写入格式回退 |
| `sync/camera_state.dart` | 不可变的 `CameraState` |
| `sync/camera_state_controller.dart` | Riverpod Notifier，唯一的相机状态源 |
| `sync/change_stream.dart` | WebSocket 订阅与轮询兜底，对外只暴露「局部 props 更新」流 |
| `capture/capture_tracker.dart` | 识别拍摄完成，产出 `CaptureRecord` |
| `program/program_runner.dart` | 程序拍摄执行器 |
| `program/bracket_program.dart` | 自定义包围、配方包围的步骤生成 |
| `program/ramp_program.dart` | 计划渐变、测光渐变的步骤生成 |
| `program/live_meter.dart` | 从 Live View 帧计算亮度（实验） |
| `recipe/combo_recipe.dart` | 组合配方模型 |
| `recipe/recipe_store.dart` | 组合配方、拍摄标记、程序日志的 SQLite 存取 |
| `recipe/recipe_session.dart` | 当前激活配方与脱离检测 |
| `recipe/tag_matcher.dart` | 标记与 `local_media` 的匹配 |

`CameraApi` 扩展：`putParams(endpoint, Map<String,String>, encoding)`、`photos()`、`photoInfo(dir, file)`、`thumbnail(dir, file)`、`revisions()`、`cancelShoot()`。

### 4.2 Dart `lib/features/shoot/`（按 v3 原型重写）

`shoot_page.dart`（布局与模式切换）；`widgets/`：`top_bar`、`viewfinder`（3:2 画面放在 4:3 区域内，叠加画幅圆点、刻度尺、提示条）、`param_row`、`param_ruler`、`mode_carousel`、`bottom_bar`、`recipe_strip`、`more_grid`、`drive_options`、`program_sheet`、`dim_overlay`。

### 4.3 Dart `lib/diagnostics/protocol_probe.dart` + `lib/features/settings/protocol_probe_page.dart`

### 4.4 Kotlin

- 新增 `device/http/ChangeSocketClient.kt`：只依赖 OkHttpClient 和事件回调，便于用 MockWebServer 单测。`BoundCameraTransport` 用已绑定相机网络的 client 派生一个读超时为 0 的 client 来创建它；同时只允许一个 changes 连接。
- Pigeon `CameraDeviceHostApi` 新增：`openChangeSocket(path)`（相对路径，与 `cameraRequest` 一致）、`closeChangeSocket()`、`setKeepScreenOn(bool)`。
- 事件经现有 `onNativeEvent` 回传：`changes.open`、`changes.message`（payload 为 `{"text": <原文>}`）、`changes.closed`（含 code）、`changes.failure`（含 HTTP status，若有）。
- 屏幕常亮用 `FLAG_KEEP_SCREEN_ON`，不加依赖。

### 4.5 复用

- 组合配方的出图部分直接引用 `export_presets` 中的 `ExportRecipe`。
- `ExportQueueController` 新增 `startEach(List<(LocalMediaItem, ExportRecipe)>)`，每张照片使用各自的出图方案；`start` 保持不变。
- `FakeCameraGateways` 扩展为可编程的模拟相机（props、写入、changes、拍摄完成），供 `GREMOTE_FAKE_CAMERA` 和测试使用。

## 5. 协议层

### 5.1 参数表

| ParamKey | props 键 | 列表键 | 写入端点 | 界面位置 |
|---|---|---|---|---|
| aperture | `av` | `avList` | camera | 专业 F |
| shutter | `tv` | `tvList` | camera | 专业 S |
| iso | `sv` | `svList` | camera | 专业 ISO |
| exposureComp | `xv` | `xvList` | camera | 专业 EV |
| whiteBalance | `WBMode` | `WBModeList` | camera | 专业 WB |
| metering | `meteringMode` | `meteringModeList` | camera | 专业 测光 |
| focusSetting | `focusSetting` | `focusSettingList` | lens | 更多 |
| exposureMode | `exposureMode` | `exposureModeList` | 只读（机身拨盘） | 顶栏 |
| drive | `shootMode` | `shootModeList` | camera | 包围 / 延时 / 更多 |
| effect | `effect` | `effectList` | camera | 配方条 |
| aspectRatio | `aspectRatio` | `aspectRatioList` | camera | 画幅圆点 |
| stillFormat | `stillFormat` | `stillFormatList` | camera | ≡ 设置 |

规则：

- 值一律保存相机原始字符串，选项顺序以相机列表为准；界面原样显示，不做单位换算，避免把 `2`（秒）误显示成 `1/2`。
- 程序拍摄需要数值时才解析：`tv` 接受 `1/N`、`N`、`N.N`，可带结尾的 `"` 或 `s`，单位为秒；`sv` 接受整数或 `auto`；`xv` 接受带符号小数，也接受 `+1/3` 这类分数。列表里只要有一个值无法解析，依赖该参数的程序就进入 refused，并提示「曝光值格式未知，请运行协议探测」。
- `writable` = 列表存在且至少两项，并且该键不是 `exposureMode`。
- 列表缺失的参数：控件隐藏。画幅圆点只在 `aspectRatioList` 存在时显示。
- extras：所有未列入上表、且同时存在 `x` 和 `xList` 的键，在「≡ 设置 → 更多参数」中以通用选择器展示，写入端点固定为 camera。

### 5.2 协议画像

```text
ProtocolProfile {
  firmware: String           // 来自 BLE 或 props
  writeEncoding: query | form | json | unknown
  webSocket: supported | unsupported | unknown
  probedAt: DateTime?
}
```

- 存于 `app_kv` 表，键为 `protocolProfile:<firmware>`。
- 没有画像时，第一次写入依次尝试 query → form → json；判定成功的条件：HTTP 2xx，且 JSON 中没有 `errCode`，或 `errCode == 200`。第一个成功的格式写入画像。三种都失败时，标记 `writeEncoding = unknown`，本次连接禁用写入，界面显示「参数只读」。
- 格式定义：query 为 `PUT /v1/params/camera?av=2.8`；form 为 body `av=2.8`，`Content-Type: application/x-www-form-urlencoded`；json 为 body `{"av":"2.8"}`，`Content-Type: application/json`。

### 5.3 变化同步

- 连接进入 ready 后，Dart 调用 `openChangeSocket("ws://<host>/v1/changes")`。
- 收到 `changes.message` 时按 props 解析为局部更新，再合并到 `CameraState`。消息中若含 `captureId` 或 `state`，同时转发给 `CaptureTracker`。
- 断线后按 1、2、4、8 秒退避重连，最长 30 秒。同一次连接内握手连续失败 3 次，则画像写 `webSocket = unsupported`，本次连接改为轮询；下次连接重新尝试。
- 轮询：仅在拍摄页可见、app 在前台、且 WebSocket 不可用时，每秒执行一次 `GET /v1/props`。
- 全量刷新：写入成功后、WebSocket 重连成功后、app 回到前台时，各执行一次 `GET /v1/props`。
- 离开拍摄页时，WebSocket 保持连接（不发轮询），以便首页显示电量、剩余张数；断开相机时关闭。

## 6. 状态与写入

### 6.1 CameraState

```text
CameraState {
  params: Map<ParamKey, CameraParam>
  extras: Map<String, CameraParam>
  battery: int?          hot: bool?
  remain: int?           liveState: String?
  syncMode: webSocket | polling | offline
  writesEnabled: bool
  pending: Map<ParamKey, PendingWrite>
  updatedAt: DateTime
}
CameraParam { key, current: String?, options: List<String>, writable: bool }
PendingWrite { target: String, startedAt: DateTime }
```

### 6.2 写入生命周期

```text
idle ──拨动──▶ pending(target) ──回读等于 target──▶ idle（成功）
                    │──回读不等于 target──▶ idle + 提示「相机调整为 X」
                    │──HTTP/errCode 失败──▶ idle（恢复原值）+ 提示 errMsg
                    └──3 秒无确认──▶ idle（以最新回读为准）+ 提示「相机未响应」
```

- 全局只有一个写请求在途。每个参数最多再排队一个值，新值覆盖旧值（拨盘连续拖动只发最后的值）。
- 刻度尺拖动时，界面立即显示目标值并带「待确认」动画，但 `CameraState.params` 只由相机回读更新。
- 回读来源：先看写入响应体，响应体里有该键就以它为准；否则立即做一次全量刷新，以刷新结果为准。
- 拨盘停止操作 2 秒后收起。

## 7. 拍摄完成识别

### 7.1 CaptureRecord

```text
CaptureRecord {
  dir: String
  baseName: String               // R0001234
  files: List<String>            // R0001234.JPG、R0001234.DNG
  capturedAt: DateTime
  timeSource: camera | phone
  effect: String?
  source: app | body | program
  programRunId: String?
}
```

### 7.2 识别流程

1. **触发**：app 快门的 shoot 响应；changes 消息中的 `captureId` 或 `state` 变化；轮询中 `remain` 减少。
2. **确认文件**：调用 `GET /v1/photos`，与上一次缓存的列表做差，新出现的文件按去掉扩展名后的文件名分组。列表缓存在连接 ready 时初始化。
3. **拍摄时间**：读取 `GET /v1/photos/{dir}/{file}/info` 中的时间字段（H7），此时 `timeSource = camera`；读不到则用触发时刻的手机时间，`timeSource = phone`。
4. **超时**：从触发开始等待 `max(10 秒, 快门秒数 × 2 + 5 秒)`，期间每秒做一次列表差分；超时未出现新文件，则记诊断事件并放弃本次识别。
5. 拍摄页左下角缩略图在识别完成后刷新，内容来自 `thumbnail(dir, file)`，只保存在内存中。

## 8. 驱动模式与程序拍摄

### 8.1 相机原生驱动

- 只显示 `shootModeList` 中存在的值，按用途归入模式：
  - 包围：`bracket*`、`dofBracket*`
  - 延时：`interval*`、`intervalComp*`、`intervalMovie*`
  - 更多：连拍、自拍、遥控变体
- 选中即写入 `shootMode`。之后按快门，由相机执行整个序列。
- 进度：根据 `CaptureTracker` 累计本次序列的张数；相机报告 `state` 时同时显示。
- 张数、间隔等原生参数（H6）默认不可设置，子选项下方提示「张数与间隔在机身菜单中设置」；若探测发现 extras 中有对应字段，则改为在子选项中提供设置。

### 8.2 程序拍摄执行器

状态：

```text
idle → preparing → running(i) → completed
          │            │  ▲
          ▼            ▼  │
       refused      paused(reason) ──继续──┘
                       └──终止──▶ aborted
```

- **preparing**：校验前置条件（见各程序），记录原始参数快照，把 `shootMode` 写为单张。条件不满足进入 refused，并给出原因（例如「请把机身拨盘转到 M 档」）。
- **每一步**：写入本步参数（只写有变化的键）并等待写入成功 → 调用 shoot（`af=off`，只有第一张可选 `af=camera`）→ 等待 `CaptureTracker` 确认 → 记录日志 → 等待下一步。
- **计时**：间隔类程序的第 i 张计划时刻为「开始时间 + i × 间隔」。若上一张超时导致错过计划时刻，则立即拍摄，并在日志中记一次 overrun。
- **失败**：单步失败（写入被拒、被相机修正、拍摄失败、识别超时）等待 1 秒后重试一次；仍失败则进入 `paused(failure)`。
- **暂停**：用户点暂停、app 进入后台、相机断开时进入 paused。恢复后不自动继续，必须由用户点「继续」。
- **结束**：完成或终止时，把参数恢复为原始快照，恢复失败只提示，不重试。
- **屏幕**：running 和 paused 状态下调用 `setKeepScreenOn(true)`，其他状态为 false。
- **暗屏遮罩**：95% 不透明的黑色，只显示一行进度，点击后移除遮罩。
- 同时只能有一个程序在运行。运行中模式轮播锁定，只允许操作暂停、停止、±⅓ EV 微调（仅渐变程序）、暗屏。

### 8.3 程序定义

**自定义包围**
- 变量：EV、ISO、白平衡、快门（仅 M 档）、光圈（仅 Av / M 档）。
- 参数：中心值（默认当前值）、张数 2–15、步长（按选项列表的索引计）。
- 取值超出列表范围的帧会被丢弃，开始前提示实际张数。
- 连续拍摄，两张之间没有额外等待。

**配方包围**
- 选择 2–8 个组合配方，按顺序每张写一次 `effect` 再拍。
- 每张的标记使用本帧对应的配方，优先于当前会话的配方。
- 前置条件：`effect` 可写。

**计划渐变延时**
- 前置条件：`exposureMode == M`，`tv`、`sv` 均可写。
- 参数：间隔 2–600 秒，张数或总时长，起始曝光 (tv, sv)，结束曝光 (tv, sv)，快门上限（默认 `min(间隔 − 1 秒, 30 秒)`）。
- 算法：在 EV 空间做线性插值。每一帧的目标 EV 先用快门实现，按 `tvList` 取最近值；快门达到上限后再提高 ISO，按 `svList` 取最近值。
- 微调：运行中 ±⅓ EV 会平移剩余所有帧的目标 EV。

**测光渐变延时（实验）**
- 默认关闭，在「≡ 设置 → 实验功能」中开启；Gate 1 的 30 分钟 Live View 温度测试通过之前，开启时会显示警告。
- 前置条件与计划渐变相同，并且 Live View 必须保持运行。
- 每帧拍摄前取最近一帧 Live View，用 `dart:ui` 按 64 像素宽解码，计算平均亮度（与 ▥ 直方图共用 `LiveFrameAnalyzer`）。C++ 的 `decodePreview` 只接受文件描述符，不适用于内存中的 Live View 帧。
- 以第一帧亮度为目标，误差 `ΔEV = log2(目标 / 当前)`。死区 1/6 EV；每帧最多调整 ⅓ EV。
- 和计划渐变共用执行器与曝光量化逻辑。

## 9. 组合配方与标记

### 9.1 模型

```text
ComboRecipe {
  id: String
  name: String（≤ 24 字符）
  effect: String?               // 相机原始值；null 表示不改机内配方
  exportPresetId: String?       // 引用 export_presets；null 表示不自动出图
  sort: int
  createdAt: DateTime
}
```

- 内置一条只读的「原厂」，含义是不改 effect、不打标记。
- 新建时，effect 从 `effectList` 中选择，出图方案从已保存的 `export_presets` 中选择，也可以在这里新建。
- 配方条缩略图：内置样张 `assets/images/street_moment.jpg` 套用该配方的 LUT 后生成，缓存在本地；机内 effect 名称以文字叠加在缩略图上。

### 9.2 会话

- 在配方条点选配方 R：若 R.effect 不为空，写入 effect，确认成功后会话进入 `active(R)`；写入失败则保持原会话。
- 每次状态更新时检查：若 `active(R)` 下相机 effect ≠ R.effect，进入 `detached(R)`，取景提示条和配方图标显示「已脱离」。
- 只有 `active` 状态下产生的 `CaptureRecord` 才会写入标记（配方包围除外，它按帧标记）。
- 会话不跨连接保留；重新连接后为「原厂」。

### 9.3 与本地照片匹配

- 标记表按 `(baseName, capturedAt, timeSource)` 保存，不依赖下载流水线。
- 匹配条件：`local_media.display_name` 去掉扩展名后等于 `baseName`，并且：
  - `timeSource = camera`：`|date_taken − capturedAt| ≤ 2 秒`，视为强匹配，自动关联；
  - `timeSource = phone`：两者相差 12 小时以内，视为弱匹配，在图库中显示「待确认」，由用户确认后才关联。
- 同一 baseName 的 JPG 和 DNG 共享同一个标记。
- 匹配在图库加载时实时计算，不写入外键。

### 9.4 图库与导出

- 图库网格上，带强匹配标记或已确认标记的照片显示配方角标；顶部增加筛选标签「按配方」。
- 多选后新增操作「按配方导出」：每张照片使用其配方引用的 `ExportRecipe`，通过 `startEach` 进入导出队列；没有标记或配方没有出图方案的照片跳过，并在开始前提示跳过的数量。

## 10. 界面

### 10.1 全屏

- `/shoot` 保留在 `StatefulShellRoute` 中；当前分支是拍摄页时，`GRemoteShell` 隐藏底部导航，并切换为沉浸式状态栏。
- 系统返回键或返回手势回到 `/home`。点击左下角缩略图进入 `/library`。

### 10.2 布局（自上而下，复刻 HyperOS 相机）

1. **状态栏**：时间；右侧显示 GR 电量。
2. **顶栏**：剩余张数、⏱ 自拍定时（拍照模式；按「关 → 2 秒 → 10 秒」循环，实际写入 `shootMode` 的 `single / self2s / self10s`，只显示列表中存在的值；与驱动模式共用 `shootMode`，后选的覆盖先选的）或 ▥ 直方图（专业模式，根据 Live View 帧计算）、◍ 组合配方（激活时为金色，脱离时为灰色并带提示点）、机身档位（只读）、≡ 设置。程序运行中，左侧改为进度，右侧改为 ☾ 暗屏。
3. **取景区**：宽度占满屏幕，高度为宽度的 4/3；GR 的 3:2 画面在其中垂直居中，上下留出黑边。叠加层：
   - 对焦框：点击画面调用 `focus`；
   - 画幅圆点（拍照模式，下方黑边内）；
   - 刻度尺（专业模式，下方黑边内）：当前值显示在刻度上方，左侧「A」按钮仅在选项中有 `auto` 时显示；
   - 配方条（下方黑边内）；
   - 提示条（上方）：配方名、下一张倒计时等。
4. **参数行**（专业模式）：WB · F · S · ISO · EV · 测光；不可写的项灰显，点击后提示原因。
5. **子选项**（包围 / 延时模式）：药丸形按钮；手机编排的项带「手机」标注。
6. **模式轮播**：更多 · 延时 · 包围 · 拍照 · 专业，默认停在拍照；左右滑动或点击切换，当前模式居中显示。
7. **底部三件套**：左侧缩略图，中间快门（按下等于半按，抬起拍摄；程序运行中变为红色方块，即停止），右侧圆形副键（AF 半按；程序运行中为暂停 / 继续）。
8. **更多宫格**：分为「相机原生 / 手机编排 / 工具」三组；只显示可用项；工具组包括协议探测。不做 ✎ 自定义轮播：宫格里的项本身就属于包围、延时或拍照模式，钉到轮播会产生「模式里套模式」的歧义。
9. **程序抽屉**：在包围或延时模式下选中手机编排的项后，从底部上拉，填写 §8.3 中的参数，点「开始」执行。

### 10.3 视觉与横屏

- 拍摄页使用纯黑背景；强调色使用 `GRemoteColors.gold`，替代小米的黄色。
- 横屏：取景区占满屏幕，模式轮播和底部三件套移到右侧并竖向排列，参数行移到左侧。

## 11. 协议探测

入口：「首页 → 设置 → 诊断 → 协议探测」，以及更多宫格中的「协议探测」。

1. **只读探测**（默认执行）：`ping`、`props`、`debug/revisions`、`photos`（只统计数量）、`/v1/changes` WebSocket 握手并监听 10 秒。
2. **写入格式探测**（需要用户确认）：读取当前 `xv`，用 query、form、json 三种格式依次写入**同一个值**，每次之后回读确认值没有变化，并记录每种格式的结果。
3. **结果**：生成协议画像并保存；页面展示键名、类型、各列表的取值、路由状态、WebSocket 结果、写入格式结果。
4. **导出**：在 `gremote-diagnostics/1` 中加入 `protocolProfile` 段。脱敏规则：`ssid`、`serialNo`、`macAddress`、`key` 只保留类型；文件名只保留数量；枚举列表保留原值。

## 12. 存储

`GRemoteDatabase.version` 升到 2，`onUpgrade` 从 1 到 2 时新建：

```sql
CREATE TABLE app_kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE combo_recipes (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, effect TEXT,
  export_preset_id TEXT, sort INTEGER NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE capture_tags (
  id INTEGER PRIMARY KEY, base_name TEXT NOT NULL, dir TEXT NOT NULL,
  captured_at INTEGER NOT NULL, time_source TEXT NOT NULL,
  combo_recipe_id TEXT NOT NULL, effect TEXT, program_run_id TEXT,
  confirmed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
CREATE INDEX capture_tags_name ON capture_tags(base_name);
CREATE TABLE program_runs (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL, config_json TEXT NOT NULL,
  state TEXT NOT NULL, frames_done INTEGER NOT NULL,
  started_at INTEGER NOT NULL, ended_at INTEGER, log_json TEXT NOT NULL);
```

- 新安装时 `onCreate` 直接建出 v2 的完整结构。
- 删除组合配方时，其标记保留，图库中显示为「已删除的配方」，不参与按配方导出。
- 程序日志只保留最近 50 条。

## 13. 错误处理

| 场景 | 行为 |
|---|---|
| props 解析失败 | 保留上一次状态，`syncMode` 不变，记诊断事件；连续 5 次失败后提示「相机状态异常」 |
| 写入格式全部失败 | 本次连接只读，参数行显示「只读」标记，提示用户运行协议探测 |
| 写入被拒 | 恢复为回读值，以 toast 显示相机返回的 `errMsg` |
| 相机修正了写入的值 | 显示「相机调整为 X」 |
| `hot == true` | 顶栏显示过热图标；禁止开始新程序；运行中的程序进入 paused |
| `remain == 0` 或无可写存储 | 快门和程序开始按钮禁用，提示存储不可用 |
| WebSocket 断开 | 自动退避重连，期间轮询，顶栏不打扰用户 |
| Wi‑Fi 断开 | 沿用现有连接状态机；程序进入 paused |
| 拍摄识别超时 | 记诊断事件；程序中按单步失败处理 |
| 物理拨盘导致程序前置条件失效（如离开 M 档） | 程序进入 paused 并提示原因 |

所有诊断事件沿用 `DiagnosticRedactor`，HTTP body 不进入日志，只记录键名。

## 14. 测试

**Dart 单元测试**
- `props_parser`：固件推导样例（新增 `test/fixtures/props_gr3_derived.json`）、键缺失、类型异常、extras 识别；现有 `props.json` 继续通过。
- `param_writer`：串行发送、同参数合并、三种格式回退、确认 / 修正 / 拒绝 / 超时四种结果。
- `change_stream`：WebSocket 消息合并、失败 3 次降级为轮询、触发全量刷新的时机。
- `capture_tracker`：列表差分、RAW+JPEG 分组、超时、两种时间来源。
- `program_runner`：用 `fake_async` 覆盖计划时刻、overrun、重试后暂停、后台暂停、结束时恢复参数。
- `ramp_program`：EV 插值、快门上限后提 ISO、量化取最近值、微调平移；`live_meter` 的死区与步长限制。
- `bracket_program`：越界帧丢弃、配方包围逐帧标记。
- `recipe_session`：激活、脱离、配方包围优先于会话。
- `tag_matcher`：强匹配、弱匹配、文件名循环导致的重名。
- 数据库：从 v1 升级到 v2，以及新安装直接建 v2。

**Widget 测试**
- 拍摄页五种状态（拍照、专业、延时执行中、配方条、更多），以及进入拍摄页时 Tab 栏隐藏。
- 不可写参数灰显、刻度尺「A」按钮按条件显示。

**集成测试**
- 扩展 `integration_test/mock_camera_flow_test.dart`：基于模拟相机走一遍「连接 → 专业模式改 ISO → 配方包围 3 张 → 图库按配方导出」。

**Kotlin**
- `BoundCameraTransport` 的 WebSocket：新增 `testImplementation "com.squareup.okhttp3:mockwebserver:4.12.0"`，覆盖握手、消息转发、关闭与失败事件。

## 15. 真机验证清单（追加到 Gate 1 之后）

| 检查项 | 记录内容 |
|---|---|
| 协议探测导出 | `protocolProfile` 全文（已脱敏） |
| H1–H8 | 每条记录 pass、fail 或 unsupported |
| 专业模式：Av / Tv / M 档下各参数的可写性 | 和 H2 对照 |
| 写入延迟 | 从拨盘停止到相机回读的时间，取 20 次中位数 |
| WebSocket 事件延迟 | 机身改参数到 app 显示的时间 |
| 机身快门触发标记 | 10 张中被识别的张数 |
| 配方包围 3 张 | 文件、effect、标记三者是否一致 |
| 计划渐变 60 张 / 间隔 5 秒 | overrun 次数、温度、是否断连 |
| 测光渐变（实验） | 和计划渐变对比是否闪烁 |
| 图库强匹配 | 用官方 app 导入后的匹配率 |
