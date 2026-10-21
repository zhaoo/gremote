# M10V Companion Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付原厂 Wi-Fi 上运行的认证伴侣服务、只读探针、受验证配置提交和自定义胶卷暂存。
**Architecture:** Linux 服务只负责网络/协议，通过版本化有界消息桥请求 RTOS 配置所有者；原 M10V 存档/成像继续拥有状态与图像。
**Tech Stack:** freestanding C/ARM Linux syscall、M10V C、Node/Python 构建审计、TTL/lcmd。
**Spec:** [规格](../specs/2026-10-21-integrated-film-workbench-design.md)。

## Global Constraints

[总计划](2026-10-21-film-workbench.md)的全部约束和接口适用。以下文件路径均相对隔离的 M10V checkout；不能在原 main 脏工作区实施。端口 18743、JSON/块 16 KiB、单记录 12,288、服务总暂存 64 KiB；不写照片卷，不从 Linux 调 RTOS 地址，不在 capture Hook 保存配置。

## Review Focus

未知官方构建或已占用 Hook 必须拒绝 → B1/B2；TTL 所有者消失/缓存迟到不得访问释放区 → B2；丢 ACK/重复负载不能二次提交 → B3/B4；本地菜单并发/写后读回失败不谎报回滚 → B4；捕获引用 custom bank 时不可覆写 → B5。

## B1：合同真源、目标证据与只读探针设计

**Files:** Create `contracts/companion-v1.json`、`contracts/companion-v1-fixtures.json`、`node/gr3-companion-contract.mjs`、`node/gr3-companion-contract.test.mjs`、`scripts/analyze_gr3_companion_owner.py`、`tests/test_gr3_companion_owner.py`、`docs/research/gr3-companion-owner.md`。

**Interfaces:** `companionContract() -> {protocol:1,limits,errors,fields,capabilities}`、`canonicalRecipe(value) -> {canonicalJson,sha256}`；分析器 `--firmware PATH --out DIR` 输出官方 SHA、preimage、调用者/所有者/唤醒/忙态/销毁路径证据和 `read_enabled/write_enabled` 结论。官方基线 SHA 必须为 d6a3c9c288d784080e7b283222ecdd8752adfeed6faa36dab44f73115354bfd4；A1 消费此合同，B2 消费 target 证据。

- [ ] 写失败测试：合同 protocol=1、slots=5、所有规格限额/错误码一致；规范化 bool/越界/EI/未知字段拒绝；分析器对错误 SHA、改动 preimage、缺少消费线程/生命周期证据输出拒绝，不能默认 ready。 代表用例 `test_unknown_firmware_fails_closed` 的核心断言：`assert report["write_enabled"] is False`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `node --test node/gr3-companion-contract.test.mjs` 和 `"${M10V_PYTHON}" -m unittest tests.test_gr3_companion_owner`，确认缺失接口红灯。
- [ ] 实现真源/fixtures；按现有 controller/FS/队列调用点定向读取官方输入，定位可以在非拍摄上下文处理请求的所有者与唤醒路径。证据不足时输出具体 unsupported reason；不虚构地址，也不为通过探针取消 guard。
- [ ] 重跑两条命令和分析器；人工核对报告的函数、ABI、所有者构造/析构及拍摄 busy 分支。保存 dirty/source fingerprint；尚无硬件只可标 static/ARM evidence。
- [ ] 提交 `feat: define companion contract and verified target evidence`。本任务不安装脚本或刷机；只读能力的设备通过在 B2/C3 单列。

## B2：有所有者的消息桥与只读往返

**Files:** Create `native/companion/{mailbox.h,mailbox.c,target_adapter.h}`、`native/gr3/m10v_companion_target.c`、`scripts/build_gr3_companion_probe.py`、`tests/{test_companion_mailbox,test_gr3_companion_probe}.py`；Modify `scripts/build_gr3_m10v_library.py`、`node/gr3-m10v-native-build.mjs`，只增加默认关闭的伴侣选项。

**Interfaces:** `m10v_companion_mailbox` 含 magic/protocol/capacity/ownerGeneration/requestSequence/responseSequence/校验及有界 payload；`int m10v_companion_exchange(m10v_companion_mailbox*,const m10v_companion_request*,m10v_companion_response*)`；target vtable `snapshot(ctx,out)`、`is_busy(ctx)`、`wake_owner(ctx)`、`is_owner_alive(ctx,generation)`。只读命令 `READ_CAPABILITIES/READ_STATE/PING`，写命令在此阶段返回 disabled。

- [ ] 写失败测试：短包/坏 CRC/错目标/过期 generation/已释放所有者/重入拒绝；发布/读回顺序及序号匹配；模拟缓存未同步时不能消费新请求；TTL array 地址/长度/重叠验证；只读命令不能触发任何存档写入。 代表用例 `test_released_owner_rejects_mailbox_request` 的核心断言：`assert response["code"] == "bridgeUnavailable"; assert journal_writes == 0`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `"${M10V_PYTHON}" -m unittest tests.test_companion_mailbox tests.test_gr3_companion_probe` 确认红灯。
- [ ] 实现 owner 驻留分配、cache adapter 与生成 target guard，在 B1 证实的任务入口消费；使用 GRKit 启动/校验方法但不安装其第二套 Hook。TTL 只追加本功能 include，并保持 owner 驻留；失效时停用桥，不强杀后重装。
- [ ] 重跑用例并从最终 probe 包反解审计：只读 roundtrip、无写入、目标 ABI、非目标字节、关闭后的原功能保持。硬件只读探针单独生成 buildId/hash，未运行设备不能标 camera_passed。
- [ ] 提交 `feat: add owned read-only companion mailbox and probe package`；只有所需缓存/线程/lifecycle 证据成立才允许 B4 接通目标写入。

## B3：认证 HTTP 服务与有界请求处理

**Files:** Create `native/companion/{http_server,http_parser,auth,operations,linux_io}.{h,c}`、`scripts/build_companion_service.py`、`tests/test_companion_http.py`、`node/gr3-companion-build.mjs`；Consume B1 合同和 B2 exchange。

**Interfaces:** `m10v_companion_serve(const m10v_companion_server_config*,const m10v_companion_backend*) -> int`；backend `exchange(ctx,request,response)`。路径、状态及对象严格使用规格第 6.3 节；认证头 `X-M10V-KeyId/Nonce/Boot/Session/Seq/Signature`。签名为 HMAC-SHA256(key, method + LF + path + LF + bootId + LF + sessionId + LF + decimal(sequence) + LF + nonce + LF + hex(SHA256(body)))；nonce 为 128-bit，签名常量时间比较。仅 capabilities 引导请求允许 bootId/sessionId 为空、sequence=0；服务返回 bootId 和新的128-bit sessionId，其余请求必须匹配当前 boot/session，并递增64-bit sequence。每会话用高水位和64位滑动窗口拒绝旧请求，不能仅靠可淘汰的 nonce LRU 防写重放。

- [ ] 写失败 host HTTP 测试：未认证/签名错误/重复 nonce/错误 boot/session、超过窗口的旧签名重放、16KiB+1、chunked/冲突长度/畸形 JSON/未知路径拒绝；请求 ID 相同同负载复用收据、不同负载拒绝；仅一个 pending write；backend 不响应有超时且服务仍能读状态；不支持 redirects 或任意文件路径。 代表用例 `test_duplicate_request_does_not_commit_twice` 的核心断言：`assert backend.commit_count == 1`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `"${M10V_PYTHON}" -m unittest tests.test_companion_http`，以 host 编译服务和 fake backend 确认新接口红灯，不连接用户相机。
- [ ] 实现单连接增量解析、有界短读/超时、认证、32 条有界操作摘要收据、128 条引导 nonce 窗口及最多8个会话的序号窗口。HTTP 输入缓冲16KiB、输出16KiB、上传12,288，compact request/receipt 等总暂存静态断言≤64KiB；不复制无限原始 JSON。服务仅绑定核实的相机 Wi-Fi 接口，不开 Shell。
- [ ] 重跑 host HTTP；交叉编译 ARM ELF，审计入口、系统调用 ABI、无动态解释器和所需工具；保存 binary hash。目标 libc/syscall 不能从 macOS host 结果推导可用，实际启动留设备项。
- [ ] 提交 `feat: serve authenticated bounded companion operations`。

## B4：单一提交域、原子配置和正式槽位激活

**Files:** Create `native/companion/{transaction.h,transaction.c}`、`native/gr3/m10v_companion_owner.c`、`tests/{test_companion_transaction,test_gr3_companion_owner_arm}.py`；Modify `native/gr3/m10v_library_camera.c`、必要的 `m10v_library_menu.c/m10v_settings.c`（仅让本地与远程变更进入同一提交域）及 B2 target。

**Interfaces:** `int m10v_companion_apply(const m10v_companion_snapshot *base,const m10v_companion_patch *patch,const m10v_companion_owner_services *io,m10v_companion_result *out)`；services 提供 fresh snapshot、单次 journal store/readback、busy 和 formal tone setter/readback。patch 是最多五槽的字段 mask/有界值；`m10v_companion_revision` 绑定 boot/build/journal sequence/完整配置哈希，不按手机时间排序。

- [ ] 写失败测试：本地菜单与远程在同 revision 竞争只能有一个提交；任一字段非法时零写入；其他槽/全局工具逐字不变；一次配置 patch 仅一次 journal 提交；读回不符/写后 ACK 丢失返回 unknown 并重新核对；序号回绕与坏新页回退；拍摄 busy/已有快照不变。 代表用例 `test_validated_multi_field_patch_uses_one_journal_commit` 的核心断言：`assert journal_writes == 1; assert other_slots_after == other_slots_before`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `"${M10V_PYTHON}" -m unittest tests.test_companion_transaction tests.test_gr3_companion_owner_arm`，记录红灯。
- [ ] 实现临时状态验证后一次提交、完整读回、同 owner 串行化。配置装入与 active tone 是两个受确认的步骤：先 `activateSlot=null` 持久化，再提交单独 `patch=[]/activateSlot=n`；激活失败返回真实已装入状态，不假报整体回滚。不在捕获线程执行，setter 和读回都用已核实原厂路径。
- [ ] 重跑用例并跑 regression 索引中的 settings、SD、capture snapshot、RAW lifecycle 相关模块；确认现有 M10V5A/B/迁移保留，关闭无线扩展后普通候选不变。
- [ ] 提交 `feat: serialize companion configuration commits and verified activation`。

## B5：自定义胶卷分块、bank 生命周期和打包

**Files:** Create `native/companion/{film_upload.h,film_upload.c}`、`node/{gr3-companion-package,gr3-companion-package.test}.mjs`、`tests/test_companion_upload.py`、`scripts/build_gr3_companion_candidate.mjs`；Modify `native/gr3/m10v_sd_camera.c`、`node/gr3-native-library.mjs`、`node/server.mjs`、`web/gr3/studio.js` 及相关导出确认区，仅接入同一构建选项。

**Interfaces:** `m10v_companion_stage_begin(meta,io,out)`、`stage_chunk(uploadId,index,bytes,length,hash)`、`stage_verify(uploadId,io,out)`；meta 含 model/schema/stableId/rendererHash/contentHash/size，size≤12,288。App `CompanionClient.stageFilm(FilmUploadMetadata)/sendFilmChunk(FilmChunk)/verifyFilm(String)` 返回 uploadId/验证收据。`buildCompanionPackage({official,configuration,sourceFingerprint,outputDir}) -> Promise<Receipt>`，不覆盖既有目录。

- [ ] 写失败测试：超限、乱序/重复不同内容、断传、坏哈希、过期 renderer、错误机型拒绝；当前/排队捕获引用 bank 返回 busy；持久化未读回不激活；无卡/短读/空间不足不改变旧卷；打包不含其他机型或用户照片，不覆盖用户 STARTUP。 代表用例 `test_queued_capture_prevents_bank_replacement` 的核心断言：`assert result["code"] == "busy"; assert old_bank_after == old_bank_before`（fixture 在该任务的测试文件中建立）。
- [ ] 运行 `"${M10V_PYTHON}" -m unittest tests.test_companion_upload tests.test_gr3_sd_camera` 和 `node --test node/gr3-companion-package.test.mjs` 确认红灯。
- [ ] 实现相机文件 API 驱动的 staging/完整读回/非活动 bank 引用保护；Linux 不写照片卷。网页与 CLI 使用同一 exporter，生成默认关闭的扩展开关、配对导入文件（每包随机256bit密钥）、恢复说明、receipt、source/config/候选 hash；密钥只在私有产物中。
- [ ] 重跑测试，使用 Python zipfile 独立校验 CRC/manifest/SHA256SUMS 与最终 BIN/服务/SD 文件；现有 SD/custom 与主配置导出测试全过才准备候选。
- [ ] 提交源码 `feat: upload compatible film data and package companion support`；候选与密钥不提交，交付不等于部署或安装。
