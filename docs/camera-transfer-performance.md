# 相机原图传输：调查与验证

## 已确认的数据路径

相机图库从 `GET /v1/photos` 读取文件列表，以 `GET /v1/photos/<dir>/<file>?size=thumb` 请求缩略图。保存原图走 Android `BoundCameraTransport.downloadPhoto`，使用绑定相机 Wi-Fi Network 的 OkHttp 客户端请求 `?size=full`，直接流式写入 MediaStore；原图不经过 BLE，也不转换成 Dart 的全量字节数组。BLE 负责连接/操作，不是原图吞吐瓶颈。

旧实现已经使用 OkHttp `newBuilder()`，它共享连接池和 dispatcher，因此没有证据指向“每张图都重新建立独立连接池”。当前把下载客户端放到 transport 生命周期内，保留原有共享连接能力。普通 HTTP JSON/缩略图响应的 2MiB 上限不限制原图；原图一直使用流式写入。

## 代码里可复现的成本与处理

- 每个新建图库 tile 原来立即启动缩略图请求，滚动时没有并发限额；保存原图不会等待或暂停这些请求。现在缩略图最多同时 2 个，批量原图开始前等待正在运行的缩略图完成，整个批次期间暂停排队缩略图。测试验证执行次序。原图仍为逐文件传输，失败继续下一张。
- Kotlin `InputStream.copyTo` 默认 8KiB 缓冲。现在用固定 64KiB 缓冲，不全量加载照片。纯 JVM 的 1MiB+13 字节夹具逐字节验证数据一致性，写调用由默认的 129 次减少到 17 次；这只证明调用数下降，不证明实际相机传输速度提高。
- 列表刷新在保存期间禁用；缩略图/选择/已保存标记在连接失效时作废。已排队但尚未开始的缩略图检查会话代次，防止重连后向另一会话请求旧文件。批量操作也检查会话代次，旧回调不能修改新连接的图库。
- OkHttp 4.12 `Dispatcher.cancelAll()` 包含同步调用（已检查本地 jar 字节码）。额外的 PhotoTransferCalls 关闭标记防止 disconnect 的取消快照之后又启动新的原图调用。每次 Wi-Fi 绑定创建新的 BoundCameraTransport，新的 registry 从打开状态开始。
- live view 在拍摄页面 detach 时结束，连接流程取消也会 stopLiveView；没有证据表明图库正常进入时仍持续传 live view。暂未更改拍摄/live view 生命周期。

## 固件证据与边界

本仓库 `.fw/webapid.strings` 来自已解出的固件，支持以下推断；它不能替代真机确认：

| 字符串位置（原始提取文件） | 可见证据 | 可得结论 |
| --- | --- | --- |
| 28072–28088 | GET /v1/photos、GET /v1/photos/{}/{}、/info、PUT /transfer | 可见文件列表、原图、元信息、传输状态接口 |
| 28998–29003 | size_for_transfer、full、xs、thumb | 有 full / xs / thumb 尺寸枚举；保存原图保持 full，不降级成缩略图 |
| 27929、28060–28062 | Connection: Keep-Alive、chunked、keep-alive、close | HTTP 栈含连接复用/分块传输字符串；具体响应需真机抓取 |
| 28478–28479 | storageId、after、limit | 列表实现有分页相关字段；现有列表返回契约没有硬件验证，未擅自改分页参数 |

未找到能确认照片端点 Range 请求/分段续传、并行原图数量上限的固件证据。Crow server 的线程符号不代表相机照片转换/存储能安全并行。`PUT /transfer` 是状态相关端点，不能据此当成加速下载接口。没有启用多连接分片或并行原图。

## 真机测量

保存成功后 Android logcat 的 `GRemotePhotoTransfer` 记录 `format`、`bytes`、`elapsedMs`、`bytesPerSecond`，不记录文件名、网络地址或照片内容。elapsed 包括 HTTP 请求和 MediaStore 发布，为整张保存的端到端时间；不是纯无线链路吞吐。

对同一组 JPEG 和 DNG，各运行至少 3 次，记录固件、相机电量、距离、手机型号/剩余空间、文件字节数和每张耗时；分别比较单张、批量以及滚动图库期间的结果。确认手机相册中的文件数量/大小，失败情况下确认不残留 pending/半张图片。没有连接真机，因此目前不能确定用户感知慢的主要硬件因素，也不能宣称具体提速百分比。
