# Gate 1 工具链

- Flutter：3.24.5 stable，framework revision `dec2ee5c1f`
- Dart：3.5.4
- DevTools：2.37.3
- JDK：Homebrew OpenJDK 17（构建时由 `JAVA_HOME` 显式选择）
- Android：compileSdk 34、targetSdk 34、minSdk 26
- ABI：arm64-v8a

## 出图管线新增

- Android NDK：27.0.12077973（SDK 内安装）
- Android SDK CMake：3.22.1
- 主机 CMake：4.0.2（Homebrew），用于 `scripts/build_native_host.sh` 和 CTest
- 主机编译器：Apple clang 17
- libjpeg-turbo：3.0.4，源码位于 `native/third_party/`，来源见 `native/third_party/VERSION.md`

系统默认 `java` 未配置运行时，所有 Android 构建命令必须显式解析 JDK 17；本地绝对路径不得提交到项目配置。
