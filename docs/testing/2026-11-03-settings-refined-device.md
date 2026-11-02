# 已确认样式落地与设备记录

视觉稿：`gr-camera-settings-refined.html`。用户已确认，所有修改留在develop；未push或部署。

## 实现

- 首页恢复原固定街景/标语，删除封面相册读取、轮播及管理入口；照片、导入记录和原保存数据不删除。
- 拍摄设置分组、直方图开关、明确的定时选择、实时格式/对焦/画幅、更多参数。完整驱动模式保留，连拍等仍使用原wire值，AF与快门分开。
- 紧凑十槽和常驻装卷操作；空槽不列默认参数，确认页参数折叠，保留覆盖胶卷名称及所有冲突/unknown/readback/receipt保护。
- 扩展按功能/效果/水印/焦距/画幅默认折叠，21字段与Half完整保留，逐字段确认；GET失败不再误报“操作未完成”，真实pending继续提示核对。
- 支持减少动态效果及320px/横屏/大字体，参数栏高度随文字缩放防溢出。

## 验证

最终完整Flutter测试575通过，3项原有条件跳过；flutter analyze无问题；Android arm64 Debug APK构建成功。

新鲜独立只读审查：Critical0、Important2、Minor0。两项均补RED→GREEN回归后修复：

1. “更多参数”遗漏完整驱动模式：恢复并验证continuousH原wire值、不拍照。
2. 选中槽位与controller实际准备槽位可能不同：只读投影提供实际目标、配方和使用选项，异步准备固定输入，最终确认时再校验准备身份；验证已存在胶卷、第一空槽、准备中选择变更与旧回调均不会写错槽。

审查未判断真机兼容性、性能、照片处理及精确视觉一致性。目标测试与全量记录位于 `dist/verification/settings-refined/`。

## APK与安装

候选：`dist/gremote-settings-refined-1.2.0-dev+13-arm64-debug.apk`，包名com.izhaoo.gremote，versionCode13，versionName1.2.0-dev，minSdk26，targetSdk34。

SHA256：`237eaf8743af3144c217b73697c21d3a9eb8dde02643d4ab767ca303b44142f3`

本轮早些时候v12已经通过`adb install -r`安装，未清除App数据；确认手机上的versionCode12。实际修图测试遇到系统指纹界面后停止，用户随后明确延期修图验收，不得声称照片预览/导出已真机通过。

v13早先安装因USB掉线失败；用户重新连接后 `adb install -r` 返回 Success，启动 Status ok；随后读取包信息确认versionCode13、versionName1.2.0-dev，lastUpdateTime=2026-11-03 00:31:58。未清除App数据。已检查真机首页固定图，不包含用户相册轮播。

## 相机只读采集与诊断纠正

没有刷相机固件、改SD脚本、保存机内设置或确认装卷。机型按用户提供的GRIII街拍版、基于2.10改造处理。

手机回到192.168.0.0/24后，签名capabilities确认 model=GR III、slotCount=10、stateSchema=2，buildId前缀03db1c70、rendererHash前缀80a4d357。第一次state/extensions capabilities/extensions state均503 busy。用户回取景后再次采集，capabilities仍200，其余均503 bridgeUnavailable。记录分别位于本地忽略目录dist/verification/settings-refined/camera-readonly-audit.jsonl与camera-readonly-viewfinder.jsonl，不将旧快照当作当前状态。

单次GET策略有误：源码linux_target.c的READ是异步邮箱操作，初次返回busy，需在同一端点及时继续轮询消费结果；3000ms超时先于结果检查，超时会设置当前Linux adapter的failed标记。第一次单读后改查其他端点、等待人工回复，符合此临时会话失效路径。离线fixture复现，但无法从HTTP证明物理设备内的failed字段，因此不宣称唯一原因。已告知用户并停止旧脚本，没有清锁、杀相机服务或重载Hook。

App既有CompanionClient已串行并对busy以250ms间隔最多重读3次，基础及扩展签名轮询测试通过；本次没有改变请求/写入协议。新的只读脚本按端点连续轮询、每次新seq/nonce、验证响应签名/会话，认证或非busy错误立即停止，忙碌有次数与时间上限。离线4项校验覆盖同端点顺序、忙碌上限、认证与签名失败停止。未把离线结果当作机身恢复成功。

已请求用户在相机空闲时正常关机开机、手机连相机Wi-Fi并重新接USB，暂不打开GRemote；准备好后停止App后台请求再采集，防止两套客户端并发。本次USB掉线前的停止App命令失败，没有声称已停止。尚未取得恢复后的状态，机内设置功能仍待实测。

## 胶卷库同步修复

用户补报“同步失败，已保留本地胶卷库”。官网实际catalog共56款，新增322–326号超出App原有浏览上限321；官网下载包rendererHash为7595208a…，与App/配套机身80a4d357…不同，原逻辑整包拒绝。手机curl已确认官网catalog HTTP200，不将联网推断为同步成功。

修复：浏览ID接受有效uint32；下载包继续校验结构、CRC、ID集合、所有记录renderer一致、ZIP和大小上限，缓存原子替换。经完整验证的新库可以浏览，快照显式记录renderer与机身兼容性；不匹配版本与本地未知ID禁止从该详情装卷，不修改CameraFilmCatalog、CameraFilmRecipe或controller硬门禁，不向相机上传该下载包。网络/超时/HTTP/格式错误显示具体原因，失败保留旧缓存。

电脑端真实官网完整同步及缓存回读56款已通过，cameraCompatible=false，pack SHA256=aae7dac231967673dd065f47705bee2f547642023d844d67929b2c0cfa62d92e。此为host网络/缓存结果，尚非手机App同步验收。

独立只读代码审查：Critical0、Important0、Minor1（未知ID卡片可用样式与详情不一致，随后补回归修复）。测试和后续APK/安装结果继续追加，未经验证不报告已安装。

最终验证：Flutter完整测试580通过、3项既有条件跳过；analyze无问题；arm64 Debug构建成功。未知ID卡片灰态回归先RED后GREEN，独立审查的Minor已修复。真实官网同步和缓存回读成功，手机App同步尚待USB恢复后安装验证。

v14候选：dist/gremote-settings-sync-1.2.0-dev+14-arm64-debug.apk。SHA256：0187f78708a80c9e4fea5942b5cbf8aba82757267caceadfbc3273e6c2f3134f。最后ADB设备列表为空；v14未安装，手机仍以上一次确认的v13为准。
