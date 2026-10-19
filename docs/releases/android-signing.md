# Android 正式签名

正式构建使用 `android/key.properties` 指向的专用密钥。配置、密钥目录均被 Git 忽略，文件权限应为 600，目录 700。请将密钥及密码配置备份到你自己的加密存储；丢失密钥将无法继续为既有安装签发更新。

当前本机密钥：`android/release-signing/gremote-release.jks`；别名 `gremote-release`。密码只保存在本机忽略的配置中，不写入文档或聊天。

配置字段：storeFile（相对 android/）、storePassword、keyAlias、keyPassword。`bash scripts/build_android.sh --release` 运行完整构建检查；缺少任何字段或密钥时正式任务会失败，不会回退 debug 签名。debug 构建继续使用调试签名。

v1.0.0 使用旧 debug 签名，v1.0.1 开始使用专用正式密钥。两者不能直接覆盖升级。不要直接卸载有重要数据的旧安装；先导出需要保留的作品，本地配方和记录也应单独保留。Android 系统不允许不同证书直接替换相同 applicationId。

发布检查：核对包名 com.izhaoo.gremote、版本号与 versionCode、apksigner verify 的证书信息、APK SHA-256；仅将 APK、SHA256SUMS.txt 与发布说明上传 GitHub。
