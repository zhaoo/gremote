# GRemote × M10V Film Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现已确认视觉的试卷台、数字胶卷、无线装卷和双向同步，交付可验收的 App 与匹配相机测试包。

**Architecture:** 一个生成式目录/协议合同连接三个独立可测试子系统：手机工作台、相机伴侣服务及 RTOS 桥、端到端同步集成。相机配置只有一个串行提交所有者；手机预览和离线卷管理不依赖无线桥可用。消息桥先证明只读往返及生命周期，再开放写入。

**Tech Stack:** Flutter/Dart/Riverpod/SQLite、C/C++ FFI、Android Kotlin/Pigeon、Node.js ≥20、Python/LLVM ARM、TTL/lcmd；GRKit 仅作启动和目标适配参考。

**Spec:** [已确认规格](../specs/2026-10-21-integrated-film-workbench-design.md)。2026-10-21 用户确认：“规格没问题，按这个方案继续，先把实施计划做好再推进开发。”

## Global Constraints

- “后续实现均在 develop；不覆盖已有改动”；GRemote 在当前干净 develop 实施，不额外创建偏离约定的开发分支。
- M10V 在隔离 `daily/film-companion` 分支实施，原 main 脏工作区保持原样；先记录并安全复制需要的已修改基线，不能只取旧 HEAD。
- “首个设备验收目标为 GR III 2.10 + Android”；保留 iOS 工程可构建性，不承诺未验收机型。
- “预览长边初始上限 960”，降级 640；“最多一个执行任务、一个待执行任务”；“缓存预算上限 48 MiB”。
- “JSON 请求上限 16 KiB”；“二进制分块最大 16 KiB、单胶卷记录上限 12,288 字节”；“服务总暂存预算 64 KiB”；并发写操作仅一个；端口 18743。
- “活跃工作台状态最多每 2 秒刷新一次”；后台停止轮询；拍摄、原图传输或相机忙时推迟写操作。
- “新增数据库 v4”，保留 v1–v3 记录；“同一时刻全 App 最多一个 open 胶卷”；RAW+JPEG 一组占一张；每页联系印样最多 24 张。
- “槽位协议值 0–4，展示为 01–05”；浏览不写入；未安装组件显示“相机暂不支持无线装卷”；超时显示“结果待核对”。
- 保留既有胶卷 ID、104 字节 M10V5A/B、历史迁移、RAW 安全、按张快照、菜单与其他工具；已有 A/B 已知问题不混入本需求。
- 中文展示，协议值不翻译；对焦与快门分开；原片不覆盖；未完成效果不显示完成；不能把 fake 服务、构建或 ARM 结果当成设备验收。
- 开发回归 → 带 SHA-256/source fingerprint 的测试包 → 用户验证 → main/GitHub/宝塔；本计划不启动设备脚本、写卡、刷机或生产发布。

## Review Focus

1. 卡格式化、编号复用及两台相机同名照片不能重复关联；A2/A4 测 camera/storage epoch 与延迟 RAW。
2. 操作已提交但 ACK 丢失，甚至相机重启；C2 测 unknown、同 boot 去重与新 boot 重新核对，不自动重放。
3. 自定义 bank 仍被排队照片引用，或脚本所有者退出；B2/B5 测引用保护和生命周期失效，不能释放后访问或复用 bank。
4. 已带 M10V 效果的 JPEG、未知新卷/字段不能被二次套色或旧 schema 覆盖；A3/A6/C2 测默认不叠色和只读降级。
5. 大字模式、320px、减少动画、快速退出后旧帧/旧网络结果返回；A3/A5/C2 测代际丢弃、触控尺寸和焦点返回。

## 拆分、顺序和完成标准

| 子计划 | 独立交付 | 任务 |
| --- | --- | --- |
| [App 工作台](2026-10-21-film-workbench-app.md) | 离线可用的真实预览、数字胶卷、印样和配方卡 | A1–A6 |
| [相机无线桥](2026-10-21-film-workbench-camera.md) | 可识别只读探针，再到受验证写入/上传的相机组件 | B1–B5 |
| [集成与交付](2026-10-21-film-workbench-integration.md) | 真传输、同步 UI、回归及测试包 | C1–C3 |

执行依赖：B1（合同与只读研究先行）→ A1/B2/B3；A1 → A2/A3；A2/A3 → A4/A5/A6；B2+B3 → B4 → B5；A1+B3 → C1；A2+A5+B4+C1 → C2；其余完成 → C3。这些是依赖图，不是自动多代理授权。

阶段完成必须区分：代码实现、离线检查、测试包生成、设备通过、生产发布。B1 未通过时可继续 App 和协议 host 测试，但 B4/B5 的设备写能力保持关闭；整体无线目标仍标记未完成，不以关闭功能冒充完成。

## 跨任务接口字典

所有 Dart 对象为不可变值对象，JSON 使用规范化 key 顺序计算 SHA-256；数字只接受整数范围，不把 bool 当 int。协议真源为 M10V `contracts/companion-v1.json`；App 仅消费生成快照，禁止手改派生目录。

- `FilmRecipe`：`schemaVersion:int, filmId:int, catalogHash:String, rendererHash:String, parameters:Map<String,int>, name:String, customHash:String?`，`fingerprint:String` 不包含显示名称；`fromJson(Map<String,Object?>)` 未知 schema 拒绝。
- `FilmCatalog`：`hash, rendererHash, entries:List<FilmDefinition>`；definition 含 stable ID、名称、图标、可见性和参数 capability。
- `FilmRoll`：`id,name,targetCount,recipeFingerprint,status,createdAt,closedAt`；`RollItem` 含媒体/相机键、配方指纹、confidence、file identities、精选标志。
- `CameraPhotoIdentity`：`instanceId,storageId,storageEpoch,dir,baseName,captureId?,contentHash?`；缺少稳定标识的文件保持候选，不凭名称自动确认。
- `CompanionCapabilities`、`CompanionSnapshot`、`SyncPatch`、`SyncOperation`：字段逐项来自合同；snapshot 的 revision 为不透明值，携带 bootId、schema/catalog/renderer、config、activeSlot、busy、新鲜度。
- `MergeResult`：`merged:Map<String,Object?>, conflicts:List<FieldConflict>, unsupportedFields:Set<String>`；冲突含 fieldPath/base/local/remote；合并不直接写相机。
- `CompanionTransport.request({required String method, required String path, Map<String,String> headers, Uint8List? body}) -> Future<CameraResponse>`，仅固定相机主机/端口；生命周期 `dispose()`。
- `CompanionClient.capabilities()/state()/submit(SyncPatch)/operation(String requestId)` 返回上述值对象；分块接口由 B5 定义并在 C2 消费。

## 文件边界

- `lib/film/{catalog,model,store,preview,capture,export}/`：各自拥有目录、值对象、SQLite、预览调度、文件归档、印样/配方卡。
- `lib/features/film_workbench/`：工作台壳、三个分区、配方/装卷/冲突弹层；不直接访问数据库或 native channel。
- `lib/camera/companion/`：生成合同、解析、API、merge/sync controller、独立 native transport。
- `native/imaging/{vendor/m10v,src/m10v_preview.*}`：冻结的纯算法依赖与 RGBA/Y-CbCr 适配；不含 camera/FS/menu 代码。
- M10V `contracts/`、`native/companion/`、`native/gr3/m10v_companion_*`、`node/gr3-companion-*`：协议、host 网络、目标桥、构建/审计分别拥有，不把 target 地址放 App 或通用服务。
- 所有新增路径在子计划标记 Create；现有文件只修改明确入口。不迁移整个现有大文件或顺手修复无关问题。

## 执行前检查

- [ ] 核对三仓库 revision/dirty；记录 M10V 已跟踪 diff 和相关未跟踪文件的路径/哈希到私有基线清单，不提交固件、照片、配对密钥。
- [ ] 使用可用的原生 worktree 工具创建 M10V 隔离工作区；安全应用所需源码快照并验证哈希。原工作区不 stash、不 reset、不切分支；不把未审阅的并发改动合入生产。
- [ ] Python 测试命令先将 `M10V_PYTHON` 设置为本机 M10V 虚拟环境的 Python 可执行文件并核实可用；隔离 checkout 不假设自带未跟踪 `.venv`，必要 fixture 通过显式只读路径提供，不复制进公开源码。
- [ ] 记录 Flutter、Dart、Node、Python、Clang/LLD、JDK17/Android SDK、Xcode 状态。当前有 Flutter/Dart/Clang/CMake，PATH 无 Cargo；方案使用已有 Node/Python/C 链，不自动安装 Rust，也不以此宣称桥可运行。
- [ ] 在选定工作区运行已有针对性基线检查；已有失败单列根因，不修改断言掩盖，不把历史绿灯当当前结果。没有相机时继续离线，设备项明确 not-run。

## 提交与评审

每任务按红灯→最小实现→绿灯→只提交本任务文件；任务完成后执行其依赖接口测试，最后按 C3 全量回归。共享协议改变需同一个候选绑定 App、服务和固件的 hash。

本计划完成后先由用户审阅并选择执行方式。推荐本会话直接实施：三个子系统的接口和现有 M10V 脏基线关联较紧，单一实现者更易保持一致；如选择逐任务子代理，则按 subagent-driven-development 的任务与评审门槛执行。未选择前不派发代理、不开始产品代码。

## 规格覆盖自查

第1节视觉/入口→A5；第2–3节基线/保护→执行前检查、A1、B1、C3；第4节目录/预览/配方→A1/A3；第5节存储/记录/冲洗→A2/A4/A6；第6.1节桥/lifecycle→B1/B2；第6.2–6.3节传输/认证/API→B3/C1；第6.4节提交/上传/合并→B4/B5/C2；第6.5节状态→A5/C2；第7节模块→本计划文件边界与各任务；第8–9节回归/候选/发布→C3。

实施细化：配置提交和 active tone 激活分两步，写后读回不确定返回 unknown；已同步更新规格相应段落，避免把跨服务提交或未知持久化结果误写成可保证回滚。

## 执行记录（2026-10-21）

- A1–A3/A5/A6：源码与离线验证完成，真实 Flutter 截图见 `docs/design/film-workbench/`。
- C1/C2：Android 传输、保护配对、真实 host HTTP 联调、持久同步状态机与五槽 UI 完成离线检查；iOS 网络显式 unsupported，构建缺 Xcode；实际设备 smoke not-run。
- B1/B2/B4/B5：受限协议、消息桥/事务/上传核心与 host/ARM 证据已具备；真实 RTOS owner/cache/wakeup/lifetime、菜单共用提交域、相机存储/Wi-Fi 适配仍未接通。对应目标任务保持未完成，所有真实能力默认关闭。
- B3：签名 HTTP 与静态 ARM 禁用服务候选完成离线验证，不能视为可安装无线组件。
- C3：离线候选、身份校验打包器、验收与源清单已准备；当前不满足完整无线功能的交付及真机验收门槛，不部署/发布。详细证据与条件跳过见 `docs/testing/film-workbench-acceptance.md`。

独立审查澄清：A4 仅核心实现，未接通真实自动拍摄归档、RAW+JPEG 生产订阅、稳定身份补证与重连找回 UI；保持未完成。当前数字胶卷使用手动本地导入。
