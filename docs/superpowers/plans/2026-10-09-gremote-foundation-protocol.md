# gremote Foundation and Stock Protocol Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an installable Android proof APK that establishes the gremote visual shell and proves GR III 2.10 BLE discovery/pairing, camera identity, Wi-Fi handoff, network-bound HTTP probing, Live View parsing, shutter operation, and diagnosable connection state on Xiaomi 14.

**Architecture:** Flutter owns UI, domain models, connection orchestration, HTTP semantics, and multipart parsing. Kotlin owns BLE GATT and an OkHttp transport whose sockets are explicitly bound to the camera Wi-Fi `Network`; generated Pigeon APIs are the only platform boundary. Every hardware dependency implements a Dart interface with a deterministic fake so unit/widget tests run without a camera.

**Tech Stack:** Flutter 3.24.5, Dart 3.5.4, Riverpod 2.6, GoRouter 14.6, Pigeon 22.7, Kotlin, Android SDK 34, JDK 17, OkHttp 4.12, JUnit, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-09-gremote-design.md`

---

## Plan Boundary

This is implementation gate 1. It does not implement media downloads, GPS sessions, production remote-control modes, RAW editing, recipes, or firmware mutation. It must end with a real Xiaomi 14 + GR III evidence report. Later plans are written only after that report fixes the observed BLE payloads, AP behavior, camera IP/port, HTTP JSON, Live View frame rate, and thermal limits.

Command convention: every command block runs from the `gremote/` directory unless it explicitly changes directory. Git commands use `git -C ..` because the Git repository root is the parent directory.

Successful output:

- branded four-tab Flutter shell;
- deterministic mock-camera mode for development and tests;
- real BLE scan, pair/connect, identity/battery read, camera wake, SSID/passphrase read, AP enable;
- Android camera-network request with explicit user consent;
- camera-network-bound `/v1/ping` and `/v1/props` requests;
- Live View JPEG stream rendered from the real camera;
- one AF shutter action;
- sanitized diagnostic export;
- arm64 debug/release test APK and completed hardware checklist.

## Locked File Structure

```text
gremote/
├── pubspec.yaml
├── analysis_options.yaml
├── lib/
│   ├── main.dart                         # bootstrap only
│   ├── app/
│   │   ├── app.dart                     # MaterialApp.router
│   │   ├── bootstrap.dart               # ProviderScope and flavor
│   │   ├── router.dart                  # four-tab StatefulShellRoute
│   │   └── theme/
│   │       ├── app_colors.dart
│   │       ├── app_theme.dart
│   │       └── app_type.dart
│   ├── features/
│   │   ├── home/home_page.dart
│   │   ├── shoot/shoot_page.dart
│   │   ├── library/library_page.dart
│   │   └── darkroom/darkroom_page.dart
│   ├── camera/
│   │   ├── model/camera_identity.dart
│   │   ├── model/camera_snapshot.dart
│   │   ├── protocol/ricoh_uuids.dart
│   │   ├── protocol/ble_codecs.dart
│   │   ├── gateway/ble_gateway.dart
│   │   ├── gateway/wifi_gateway.dart
│   │   ├── gateway/camera_transport.dart
│   │   ├── gateway/native_gateways.dart
│   │   ├── gateway/fake_gateways.dart
│   │   ├── http/camera_api.dart
│   │   ├── http/live_view_parser.dart
│   │   ├── connection/connection_state.dart
│   │   └── connection/connection_controller.dart
│   ├── diagnostics/diagnostic_event.dart
│   ├── diagnostics/diagnostic_store.dart
│   └── platform/
│       ├── camera_permission_gate.dart
│       └── device_api.g.dart              # generated, never edited
├── pigeons/device_api.dart               # platform contract source
├── android/app/src/main/kotlin/com/zhaoo/gremote/
│   ├── MainActivity.kt
│   ├── device/DeviceApi.g.kt             # generated, never edited
│   ├── device/ble/RicohBleManager.kt
│   ├── device/ble/RicohGattIds.kt
│   ├── device/wifi/CameraNetworkManager.kt
│   ├── device/http/BoundCameraTransport.kt
│   └── device/GRemoteDeviceHostApi.kt
├── test/
│   ├── app/router_test.dart
│   ├── camera/ble_codecs_test.dart
│   ├── camera/camera_api_test.dart
│   ├── camera/live_view_parser_test.dart
│   ├── camera/camera_permission_gate_test.dart
│   ├── camera/connection_controller_test.dart
│   └── features/home_page_test.dart
├── test/fixtures/
│   ├── ping.json
│   ├── props.json
│   └── liveview.multipart
├── integration_test/mock_camera_flow_test.dart
├── docs/protocol/gr3-stock-api.md
└── docs/testing/gr3-hardware-gate-1.md
```

## Protocol Constants Used by This Gate

```text
Camera Information service  9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1
Model characteristic        35FE6272-6AA5-44D9-88E1-F09427F51A71
Firmware characteristic     B4EB8905-7411-40A6-A367-2834C2157EA7
Camera service              4B445988-CAA0-4DD3-941D-37B4F52ACA86
Camera Power                B58CE84C-0666-4DE9-BEC8-2D27B27B3211
Battery                     875FC41D-4980-434C-A653-FD4A4D4410C4
Operation Mode              1452335A-EC7F-4877-B8AB-0F72E18BB295
WLAN service                F37F568F-9071-445D-A938-5441F2E82399
Network Type                9111CDD0-9F01-45C4-A2D4-E09E8FB0424D
SSID                        90638E5A-E77D-409D-B550-78F7E1CA5AB4
Passphrase                  0F38279C-FE9E-461B-8596-81287E8C9A81
Shooting service            9F00F387-8345-4BBC-8B92-B87B52E3091A
Operation Request           559644B8-E0BC-4011-929B-5CF9199851E7
Capture Status              B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA
```

Operation Request bytes are `[operationCode, parameter]`, where start is `1`, stop is `2`, no AF is `0`, and AF is `1`. Network Type is `0 = off`, `1 = AP`. Camera Power is `0 = off`, `1 = on`, `2 = sleep`. All UUIDs are additionally verified at runtime from discovered services; absent characteristics produce `unsupported`, not crashes.

---

### Task 1: Create the Flutter Android Skeleton and Pin the Toolchain

**Files:**
- Create: Flutter-generated project files under `gremote/`
- Modify: `pubspec.yaml`
- Modify: `analysis_options.yaml`
- Modify: `android/app/build.gradle`
- Create: `docs/testing/toolchain.md`

- [ ] **Step 1: Record the existing workspace and tool versions**

Run:

```bash
cd gremote
flutter --version
java -version
```

Expected: Flutter `3.24.5`, Dart `3.5.4`; JDK execution must resolve to 17 before Gradle runs. Record the exact outputs in `docs/testing/toolchain.md` without machine usernames or absolute home paths.

- [ ] **Step 2: Generate only the Android Flutter project**

Run:

```bash
flutter create --org com.izhaoo --project-name gremote --platforms android .
```

Expected: command succeeds without replacing `docs/`, `.gitignore`, or `fwdc239b.bin`; Android application ID is `com.izhaoo.gremote`.

- [ ] **Step 3: Replace dependencies with the pinned gate-1 set**

Set the relevant `pubspec.yaml` sections to:

```yaml
environment:
  sdk: ">=3.5.4 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  collection: ^1.18.0
  flutter_riverpod: ^2.6.1
  go_router: ^14.6.2
  http: ^1.2.2
  meta: ^1.15.0
  path_provider: ^2.1.5
  permission_handler: ^11.3.1
  phosphor_flutter: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  mocktail: ^1.0.4
  pigeon: ^22.7.2
```

Run `flutter pub get`. Expected: dependency resolution succeeds and `pubspec.lock` is created.

- [ ] **Step 4: Pin Android requirements**

In `android/app/build.gradle`, require `compileSdk 34`, `minSdk 26`, `targetSdk 34`, Java/Kotlin JVM 17, and arm64 release output. Do not embed signing credentials. Keep debug signing until the final release plan.

- [ ] **Step 5: Verify the generated baseline**

Run:

```bash
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Expected: analyze and tests pass; `build/app/outputs/flutter-apk/app-debug.apk` exists.

- [ ] **Step 6: Commit the skeleton**

```bash
git -C .. add gremote
git -C .. commit -m "chore: scaffold gremote Flutter Android app"
```

### Task 2: Implement the Editorial Navy-and-Gold App Shell

**Files:**
- Create: `lib/app/app.dart`
- Create: `lib/app/bootstrap.dart`
- Create: `lib/app/router.dart`
- Create: `lib/app/theme/app_colors.dart`
- Create: `lib/app/theme/app_theme.dart`
- Create: `lib/app/theme/app_type.dart`
- Create: four page files under `lib/features/`
- Modify: `lib/main.dart`
- Create: `test/app/router_test.dart`

- [ ] **Step 1: Write the failing shell test**

Create a widget test that pumps `GRemoteApp` and asserts four destinations and the default editorial home copy:

```dart
testWidgets('shows the four-tab shell', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: GRemoteApp()));
  expect(find.text('首页'), findsOneWidget);
  expect(find.text('拍摄'), findsOneWidget);
  expect(find.text('图库'), findsOneWidget);
  expect(find.text('暗房'), findsOneWidget);
  expect(find.text('Ready to Snap'), findsOneWidget);
});
```

- [ ] **Step 2: Run the test to verify RED**

Run `flutter test test/app/router_test.dart`.
Expected: FAIL because `GRemoteApp` and routes do not exist.

- [ ] **Step 3: Implement theme tokens**

Define immutable colors:

```dart
abstract final class GRemoteColors {
  static const night = Color(0xFF050D16);
  static const navy = Color(0xFF071827);
  static const raised = Color(0xFF0C2033);
  static const gold = Color(0xFFC8A65E);
  static const goldSoft = Color(0xFFE8D29B);
  static const text = Color(0xFFE7EDF4);
  static const muted = Color(0xFF8CA0B4);
}
```

Use a serif display TextStyle, system Chinese sans-serif body, and monospace numeric style. Do not fetch Google Fonts at runtime.

- [ ] **Step 4: Implement the four-tab StatefulShellRoute**

Use `StatefulShellRoute.indexedStack`; each branch owns a `NavigatorKey`. `HomePage` contains `Ready to Snap`, connection status, a camera summary area backed by deterministic fake state, and connect CTA. Other pages display branded empty states, not unfinished controls.

- [ ] **Step 5: Verify theme and navigation**

Run `flutter test test/app/router_test.dart && flutter analyze`.
Expected: PASS and no analyzer findings.

- [ ] **Step 6: Commit the shell**

```bash
git -C .. add gremote/lib gremote/test/app
git -C .. commit -m "feat: add gremote editorial app shell"
```

### Task 3: Define Typed Platform Contracts and Generate Pigeon Code

**Files:**
- Create: `pigeons/device_api.dart`
- Generate: `lib/platform/device_api.g.dart`
- Generate: `android/app/src/main/kotlin/com/zhaoo/gremote/device/DeviceApi.g.kt`
- Create: `lib/camera/gateway/ble_gateway.dart`
- Create: `lib/camera/gateway/wifi_gateway.dart`
- Create: `lib/camera/gateway/camera_transport.dart`
- Create: `test/camera/platform_contract_test.dart`

- [ ] **Step 1: Define boundary DTOs and APIs**

The Pigeon source must define:

```dart
import 'dart:typed_data';

import 'package:pigeon/pigeon.dart';

class NativeBleDevice {
  String? id;
  String? name;
  int? rssi;
}

class NativeCameraBootstrap {
  String? model;
  String? firmware;
  int? batteryLevel;
  bool? acPowered;
  String? ssid;
  String? passphrase;
}

class NativeHttpResponse {
  int? statusCode;
  Map<String?, String?>? headers;
  Uint8List? body;
}

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/platform/device_api.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/com/zhaoo/gremote/device/DeviceApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.izhaoo.gremote.device'),
))
@HostApi()
abstract class CameraDeviceHostApi {
  int androidSdkInt();
  @async List<NativeBleDevice?> scan(int timeoutMs);
  @async void connectBle(String deviceId);
  @async void disconnectBle();
  @async NativeCameraBootstrap readBootstrap();
  @async void setCameraPower(int value);
  @async void setNetworkType(int value);
  @async void writeOperationRequest(Uint8List value);
  @async void connectCameraWifi(String ssid, String passphrase);
  @async NativeHttpResponse cameraRequest(
    String method,
    String url,
    Map<String?, String?> headers,
    Uint8List? body,
  );
  @async void startLiveView(String url);
  @async void stopLiveView();
}

@FlutterApi()
abstract class CameraDeviceFlutterApi {
  void onLiveViewChunk(Uint8List bytes);
  void onNativeEvent(String type, String jsonPayload);
}
```

- [ ] **Step 2: Generate and format bindings**

Run:

```bash
dart run pigeon --input pigeons/device_api.dart \
  --dart_out lib/platform/device_api.g.dart \
  --kotlin_out android/app/src/main/kotlin/com/zhaoo/gremote/device/DeviceApi.g.kt \
  --kotlin_package com.izhaoo.gremote.device
dart format pigeons lib/platform/device_api.g.dart
```

Expected: generated Dart and Kotlin compile; no manual edits in generated files.

- [ ] **Step 3: Define Dart gateway interfaces**

`BleGateway` exposes `scan`, `connect`, `disconnect`, `readBootstrap`, power/network writes, operation requests, and an event stream. `WifiGateway` exposes `connect`. `CameraTransport` exposes small requests plus a byte-chunk Live View stream. Methods return domain types, never generated Pigeon DTOs; adapters reject missing required Pigeon fields with a typed `nativeContractViolation` error.

- [ ] **Step 4: Add a boundary smoke test**

Create a compile-time test using fake implementations and assert that a bootstrap containing `RICOH GR III`, `2.10`, battery `80`, and an SSID maps without exposing passphrase through `toString()`.

- [ ] **Step 5: Verify and commit**

Run `flutter test && flutter analyze`, then:

```bash
git -C .. add gremote/pigeons gremote/lib/platform gremote/lib/camera/gateway gremote/test/camera/platform_contract_test.dart gremote/android/app/src/main/kotlin/com/zhaoo/gremote/device/DeviceApi.g.kt
git -C .. commit -m "feat: define typed camera device contracts"
```

### Task 4: Add GR III BLE UUIDs and Binary Codecs

**Files:**
- Create: `lib/camera/protocol/ricoh_uuids.dart`
- Create: `lib/camera/protocol/ble_codecs.dart`
- Create: `lib/camera/model/camera_identity.dart`
- Create: `lib/camera/model/camera_snapshot.dart`
- Create: `test/camera/ble_codecs_test.dart`
- Create: `docs/protocol/gr3-stock-api.md`

- [ ] **Step 1: Write codec tests first**

Cover UTF-8 values with trailing NUL, battery bytes, operation request, and strict malformed lengths:

```dart
test('decodes battery level and source', () {
  expect(decodeBattery(Uint8List.fromList([82, 0])),
      const CameraBattery(level: 82, acPowered: false));
});

test('encodes AF shutter start', () {
  expect(encodeOperationRequest(start: true, autoFocus: true), [1, 1]);
});

test('rejects a one-byte battery payload', () {
  expect(() => decodeBattery(Uint8List.fromList([82])),
      throwsA(isA<FormatException>()));
});
```

- [ ] **Step 2: Run RED**

Run `flutter test test/camera/ble_codecs_test.dart`.
Expected: FAIL because codecs are absent.

- [ ] **Step 3: Implement constants and strict codecs**

Copy the UUID table from this plan into `RicohGattIds`; normalize to lowercase only for comparison. Decode strings as UTF-8 after removing trailing NUL bytes. Validate all fixed-width payload lengths. Redact `ssid`, `passphrase`, serial, and device ID from `toString()`.

- [ ] **Step 4: Write protocol evidence**

In `docs/protocol/gr3-stock-api.md`, record each UUID, read/write/notify property, byte format, source (`fwdc239b.bin` executable evidence or public reverse-engineering reference), and verification state `firmware-confirmed`, `hardware-unverified`, or `hardware-verified`.

- [ ] **Step 5: Run GREEN and commit**

Run `flutter test test/camera/ble_codecs_test.dart && flutter analyze`.
Expected: PASS.

```bash
git -C .. add gremote/lib/camera/model gremote/lib/camera/protocol gremote/test/camera/ble_codecs_test.dart gremote/docs/protocol
git -C .. commit -m "feat: model GR III BLE protocol"
```

### Task 5: Implement the Kotlin BLE Gateway

**Files:**
- Create: `android/app/src/main/kotlin/com/zhaoo/gremote/device/ble/RicohGattIds.kt`
- Create: `android/app/src/main/kotlin/com/zhaoo/gremote/device/ble/RicohBleManager.kt`
- Create: `android/app/src/main/kotlin/com/zhaoo/gremote/device/GRemoteDeviceHostApi.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/zhaoo/gremote/MainActivity.kt`
- Modify: `android/app/build.gradle`
- Create: `android/app/src/test/kotlin/com/zhaoo/gremote/device/ble/GattOperationQueueTest.kt`

- [ ] **Step 1: Add Android BLE permissions**

Manifest requirements:

```xml
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="32" />
```

Request runtime permissions from Flutter before calling scan; Kotlin returns a typed `permissionDenied` error rather than launching UI.

- [ ] **Step 2: Write the failing GATT queue tests**

Using JUnit 4.13.2 and `kotlinx-coroutines-test`, assert that the queue serializes two operations, ignores a callback for the wrong UUID, resumes on the matching callback, maps timeout to `bleTimeout`, and cancels all pending work on disconnect.

Run `./gradlew app:testDebugUnitTest --tests '*GattOperationQueueTest'`.
Expected: FAIL because the queue does not exist.

- [ ] **Step 3: Add a unit-testable GATT operation queue**

Implement one in-flight operation with `CompletableDeferred`, 8-second timeout, and callback matching by characteristic UUID. On timeout, clear the operation and return `bleTimeout`. Never issue parallel reads/writes to Android GATT.

- [ ] **Step 4: Implement filtered scan and connect**

Scan for the known Camera Information/Camera service UUIDs when advertised; retain named `RICOH` candidates when service UUIDs are omitted. Deduplicate by address, keep strongest RSSI, stop at timeout. Connect using LE transport, request MTU 247, discover services, and verify model characteristic exists.

- [ ] **Step 5: Implement bootstrap reads and writes**

Read model, firmware, battery, SSID, and passphrase sequentially. Write Camera Power, Network Type, and Operation Request using characteristic-supported write mode. Enable battery/capture notifications only after writing CCCD succeeds.

- [ ] **Step 6: Register the host API**

`MainActivity.configureFlutterEngine` creates one `GRemoteDeviceHostApi`, registers Pigeon handlers, returns `Build.VERSION.SDK_INT` from `androidSdkInt()`, and unregisters/closes BLE in `cleanUpFlutterEngine`. No static Activity references.

- [ ] **Step 7: Verify native compilation**

Run:

```bash
./android/gradlew -p android app:testDebugUnitTest
flutter build apk --debug --target-platform android-arm64
```

Expected: Kotlin unit tests pass, generated Pigeon code compiles, and APK builds without camera hardware.

- [ ] **Step 8: Commit BLE gateway**

```bash
git -C .. add gremote/android gremote/lib
git -C .. commit -m "feat: add GR III Android BLE gateway"
```

### Task 6: Implement Explicit Camera Wi-Fi Binding and Native HTTP Transport

**Files:**
- Create: `android/app/src/main/kotlin/com/zhaoo/gremote/device/wifi/CameraNetworkManager.kt`
- Create: `android/app/src/main/kotlin/com/zhaoo/gremote/device/http/BoundCameraTransport.kt`
- Create: `android/app/src/main/res/xml/network_security_config.xml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle`
- Modify: `android/app/src/main/kotlin/com/zhaoo/gremote/device/GRemoteDeviceHostApi.kt`
- Create: `android/app/src/test/kotlin/com/zhaoo/gremote/device/wifi/CameraProbeOrderTest.kt`

- [ ] **Step 1: Add dependencies and network permissions**

Add Internet, network-state, Wi-Fi-state, and change-Wi-Fi-state permissions. Add OkHttp `4.12.0`. Do not enable cleartext globally; create `network_security_config.xml` with `cleartextTrafficPermitted="false"` at the base and explicit cleartext domains `192.168.0.1` and `192.168.1.1`, then reference it from the application manifest.

- [ ] **Step 2: Write the failing camera probe-order test**

Extract endpoint selection behind a small `CameraProbe` interface. Assert it probes `192.168.0.1` first, falls through only on connection/404 failure, accepts valid JSON from `192.168.1.1`, and stops immediately on cancellation.

Run `./gradlew app:testDebugUnitTest --tests '*CameraProbeOrderTest'`.
Expected: FAIL because `CameraProbe` does not exist.

- [ ] **Step 3: Implement NetworkSpecifier connection**

Build a `WifiNetworkSpecifier` with exact SSID and WPA2 passphrase, then request `NET_CAPABILITY_NOT_INTERNET` transport Wi-Fi. Resolve only after `onAvailable`; return `wifiUserRejected`, `wifiTimeout`, or `wifiLost` as distinct errors. Keep one active `NetworkCallback` and unregister it on disconnect.

- [ ] **Step 4: Build a network-bound OkHttpClient**

When a `Network` becomes available:

```kotlin
OkHttpClient.Builder()
  .socketFactory(network.socketFactory)
  .dns { hostname ->
    if (hostname == "camera.m10v") listOf(InetAddress.getByName(cameraIp))
    else network.getAllByName(hostname).toList()
  }
  .connectTimeout(3, TimeUnit.SECONDS)
  .readTimeout(8, TimeUnit.SECONDS)
  .build()
```

Never call `bindProcessToNetwork`; non-camera traffic must retain the default network.

- [ ] **Step 5: Probe the camera endpoint**

Probe `http://192.168.0.1/v1/ping`, then `http://192.168.1.1/v1/ping`. Accept only HTTP success with valid JSON. Persist the successful base URL for the connection lifetime, not across camera identities.

- [ ] **Step 6: Implement bounded requests and Live View chunks**

Small requests cap response body at 2 MiB. Live View uses a dedicated call; copy chunks no larger than 32 KiB to `CameraDeviceFlutterApi.onLiveViewChunk`. On stop or Wi-Fi loss, cancel the OkHttp call and send a native event. Never log passphrase, Authorization, or response image bytes.

- [ ] **Step 7: Build and commit**

Run:

```bash
./android/gradlew -p android app:testDebugUnitTest
flutter build apk --debug --target-platform android-arm64
```

Expected: camera probe-order tests and native compilation PASS.

```bash
git -C .. add gremote/android
git -C .. commit -m "feat: bind camera HTTP to Android Wi-Fi network"
```

### Task 7: Implement the Stock HTTP API and Multipart Live View Parser

**Files:**
- Create: `lib/camera/http/camera_api.dart`
- Create: `lib/camera/http/live_view_parser.dart`
- Create: `test/camera/camera_api_test.dart`
- Create: `test/camera/live_view_parser_test.dart`
- Create: fixtures under `test/fixtures/`

- [ ] **Step 1: Write API request tests with a fake transport**

Assert:

```dart
await api.ping();
verify(() => transport.request(
  method: 'GET', path: '/v1/ping', headers: any(named: 'headers'))).called(1);

await api.shoot(autoFocus: true);
verify(() => transport.request(
  method: 'POST', path: '/v1/camera/shoot',
  headers: any(named: 'headers'),
  body: any(named: 'body'))).called(1);
```

The client must add `Accept: application/json`, reject non-2xx with typed `CameraApiException`, and preserve camera `errCode`/`errMsg` without leaking response bytes.

- [ ] **Step 2: Write multipart split-boundary tests**

Build a fixture containing two minimal JPEG frames with boundary `--boundary`; feed it in chunks that split the boundary, headers, content-length digits, and JPEG bytes. Assert two exact frame byte arrays. Add malformed header, oversized frame (> 4 MiB), truncated frame, and stream reset cases.

- [ ] **Step 3: Run RED**

Run:

```bash
flutter test test/camera/camera_api_test.dart test/camera/live_view_parser_test.dart
```

Expected: FAIL because API/parser do not exist.

- [ ] **Step 4: Implement API semantics**

Implement `ping`, `props`, `startLiveView`, `stopLiveView`, `focus(x,y)`, and `shoot(autoFocus)`. Keep JSON models tolerant of unknown fields but strict about required field types. Base URL belongs to transport; endpoint methods receive relative paths only.

- [ ] **Step 5: Implement a bounded streaming parser**

Use a rolling byte buffer with a maximum of 5 MiB. Prefer `Content-Length`; if absent, locate the next boundary. Validate JPEG SOI/EOI before emitting. On malformed data, drop through the next complete boundary and emit a diagnostic event rather than terminating the entire stream.

- [ ] **Step 6: Run GREEN and commit**

Run the focused tests and `flutter analyze`.
Expected: PASS.

```bash
git -C .. add gremote/lib/camera/http gremote/test/camera gremote/test/fixtures
git -C .. commit -m "feat: add GR III stock HTTP and Live View parsing"
```

### Task 8: Build the Connection State Machine with Deterministic Fakes

**Files:**
- Create: `lib/camera/connection/connection_state.dart`
- Create: `lib/camera/connection/connection_controller.dart`
- Create: `lib/camera/gateway/native_gateways.dart`
- Create: `lib/camera/gateway/fake_gateways.dart`
- Create: `lib/platform/camera_permission_gate.dart`
- Create: `test/camera/camera_permission_gate_test.dart`
- Create: `test/camera/connection_controller_test.dart`

- [ ] **Step 1: Define exhaustive state and failure types**

Use sealed classes for `idle`, `scanning`, `deviceChoice`, `pairing`, `bleReady`, `waking`, `apStarting`, `wifiRequesting`, `wifiBound`, `probing`, `ready`, and `failed`. `ConnectionFailure` includes stage, stable code, retryable flag, user action, and redacted detail.

- [ ] **Step 2: Write permission-gate tests**

Wrap `permission_handler` behind `CameraPermissionAdapter`. Assert SDK 33+ requests Bluetooth Scan, Bluetooth Connect and Nearby Wi-Fi; SDK 31–32 additionally requests foreground location for Wi-Fi discovery; SDK 29–30 requests foreground location. Denied and permanently denied states must map to different repair actions. Production reads SDK through `CameraDeviceHostApi.androidSdkInt()`.

- [ ] **Step 3: Write orchestration tests**

Tests must assert exact call order:

```text
scan → connectBle → readBootstrap → setCameraPower(1)
→ setNetworkType(1) → connectCameraWifi → ping → props → ready
```

Also cover scan empty, unsupported model, wrong firmware warning, BLE timeout, user rejecting Wi-Fi, native HTTP probe failure, Wi-Fi loss, cancellation, and retry from the failed stage. Assert no passphrase appears in state/debug strings.

- [ ] **Step 4: Run RED**

Run:

```bash
flutter test test/camera/camera_permission_gate_test.dart \
  test/camera/connection_controller_test.dart
```

Expected: FAIL because the permission gate and controller do not exist.

- [ ] **Step 5: Implement the permission gate and controller**

Before scanning, request the SDK-specific permission set through `CameraPermissionAdapter`; never call BLE/Wi-Fi after denial. Use a Riverpod `Notifier<ConnectionState>`. Each attempt owns a generation ID; asynchronous completion from an older attempt is ignored. `cancel()` increments generation and closes current gateways. Retryable failures expose `retry()`; user-action failures expose a structured instruction.

- [ ] **Step 6: Add mock-camera flavor**

`--dart-define=GREMOTE_FAKE_CAMERA=true` wires fakes that transition in deterministic 150 ms steps, emit fixture Live View frames, and simulate shutter state. Production defaults to native gateways.

- [ ] **Step 7: Verify and commit**

Run `flutter test && flutter analyze`.
Expected: PASS.

```bash
git -C .. add gremote/lib/camera gremote/lib/platform/camera_permission_gate.dart gremote/test/camera
git -C .. commit -m "feat: orchestrate GR III connection states"
```

### Task 9: Connect the Home and Shoot UI to Real State

**Files:**
- Modify: `lib/features/home/home_page.dart`
- Modify: `lib/features/shoot/shoot_page.dart`
- Create: `lib/features/home/widgets/connection_card.dart`
- Create: `lib/features/shoot/widgets/live_view_surface.dart`
- Create: `lib/features/shoot/widgets/shutter_button.dart`
- Create: `test/features/home_page_test.dart`
- Create: `integration_test/mock_camera_flow_test.dart`

- [ ] **Step 1: Write widget tests for meaningful states**

Cover idle, scanning, Wi-Fi user confirmation, ready, retryable failure, and unsupported firmware warning. Assert passwords and full BLE IDs are absent. Shoot page must disable shutter until `ready` and render the newest JPEG frame.

- [ ] **Step 2: Run RED**

Run `flutter test test/features/home_page_test.dart`.
Expected: FAIL because state-connected widgets are absent.

- [ ] **Step 3: Implement the editorial connection card**

Show the current stage in Chinese, one primary action, and concise repair guidance. Ready state shows model, firmware, battery and a gold “进入实景遥控” action. A long press opens sanitized diagnostics; normal users never see stack traces.

- [ ] **Step 4: Implement Live View and AF shutter**

Use `Image.memory(frame, gaplessPlayback: true, filterQuality: FilterQuality.low)`. Keep only the latest frame to enforce backpressure. Press starts operation request `[1,1]`; release sends `[2,1]`. If BLE operation request is unsupported, fall back to HTTP `POST /v1/camera/shoot` and record which path succeeded.

- [ ] **Step 5: Add rotation behavior**

All normal routes remain portrait. On entering Shoot, allow portrait and landscape; restore portrait on dispose. In landscape, hide bottom navigation and show an overlay back action. Respect system reduced-motion settings.

- [ ] **Step 6: Add and run the mock-camera integration flow**

The integration test launches with `GREMOTE_FAKE_CAMERA=true`, taps connect, waits for ready, enters Shoot, observes a JPEG frame, presses/releases shutter, returns home, and asserts the final camera status remains ready.

Run:

```bash
flutter test
flutter test integration_test/mock_camera_flow_test.dart \
  --dart-define=GREMOTE_FAKE_CAMERA=true
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=GREMOTE_FAKE_CAMERA=true
```

Expected: unit/widget/integration tests pass and mock APK builds.

```bash
git -C .. add gremote/lib/features gremote/test/features gremote/integration_test
git -C .. commit -m "feat: add connection and Live View proof UI"
```

### Task 10: Add Sanitized Diagnostics and Hardware Evidence Capture

**Files:**
- Create: `lib/diagnostics/diagnostic_event.dart`
- Create: `lib/diagnostics/diagnostic_store.dart`
- Create: `lib/diagnostics/diagnostic_redactor.dart`
- Create: `test/diagnostics/diagnostic_redactor_test.dart`
- Create: `docs/testing/gr3-hardware-gate-1.md`

- [ ] **Step 1: Write redaction tests**

Input events must include fake SSID, passphrase, MAC, serial, absolute path, GPS, and HTTP body. Assert export replaces them with stable redaction tokens and keeps stage, monotonic timestamp, duration, firmware, status code, endpoint path, exception code, and retry count.

- [ ] **Step 2: Run RED**

Run `flutter test test/diagnostics/diagnostic_redactor_test.dart`.
Expected: FAIL.

- [ ] **Step 3: Implement bounded event storage**

Keep the latest 2,000 structured events in memory and persist only the latest 500 non-sensitive events in app storage. Export JSON with schema `gremote-diagnostics/1`. Never accept arbitrary map values; every event field passes a key-specific redactor.

- [ ] **Step 4: Write the gate-1 hardware checklist**

The checklist contains exact result fields for:

- phone HyperOS/Android build and gremote commit;
- GR III firmware displayed by BLE;
- scan name/service UUIDs;
- pairing prompts and reconnect after force-stop;
- raw byte lengths (not secrets) for all bootstrap characteristics;
- AP enable time and system Wi-Fi consent behavior;
- successful camera IP and HTTP status/JSON key names;
- Live View resolution, measured FPS, 5/15/30-minute temperature and disconnects;
- BLE and HTTP shutter behavior;
- app background/foreground and cellular coexistence;
- sanitized diagnostic export hash.

Every row uses `pass`, `fail`, `unsupported`, or `not-run`; no blank status is accepted.

- [ ] **Step 5: Run GREEN and commit**

Run `flutter test && flutter analyze`.
Expected: PASS.

```bash
git -C .. add gremote/lib/diagnostics gremote/test/diagnostics gremote/docs/testing
git -C .. commit -m "feat: add sanitized protocol diagnostics"
```

### Task 11: Run the Xiaomi 14 + GR III Gate and Produce the Test APK

**Files:**
- Modify: `docs/testing/gr3-hardware-gate-1.md`
- Modify: `docs/protocol/gr3-stock-api.md`
- Create: `scripts/build_android.sh`

- [ ] **Step 1: Add a deterministic APK build script**

The script must locate JDK 17 and Android SDK without committing local paths, run `flutter pub get`, `flutter analyze`, `flutter test`, and build `android-arm64`. It copies output to:

```text
dist/gremote-0.1.0+1-arm64-<debug|release>-<YYYYMMDD-HHMMSS>.apk
```

It fails on any command and prints SHA-256 of the APK.

- [ ] **Step 2: Execute the full software gate**

Run:

```bash
./scripts/build_android.sh --debug
```

Expected: analyze/tests pass, APK exists, and SHA-256 prints. No `fwdc239b.bin`, `.fw`, signing key, passphrase, or `.superpowers` content appears in the APK or Git index.

- [ ] **Step 3: Send the APK for user-operated installation**

The user installs the APK on Xiaomi 14 and runs each item in `docs/testing/gr3-hardware-gate-1.md`. The App exports a sanitized diagnostic JSON. This step does not use Android firmware flashing, ADB automation, or camera firmware mutation.

- [ ] **Step 4: Record observed protocol facts**

Update `docs/protocol/gr3-stock-api.md` with only observed facts: characteristic availability and lengths, camera IP, JSON key names, Live View boundary behavior, shutter path and thermal result. Do not reinterpret failures as support.

- [ ] **Step 5: Fix gate-1 defects with regression tests**

For each failed checklist row, first add a focused test that reproduces the observed payload/state, run it RED, apply the smallest fix, then run GREEN. Repeat until every required row is `pass` or explicitly accepted as `unsupported` by the user.

- [ ] **Step 6: Run final verification**

Run:

```bash
flutter analyze
flutter test
./scripts/build_android.sh --debug
git -C .. diff --check -- gremote
git -C .. status --short -- gremote
```

Expected: all automated checks pass; only gate evidence and intended fixes are pending; proprietary firmware and diagnostics with secrets remain ignored/untracked.

- [ ] **Step 7: Review the completed gate as one change set**

Dispatch exactly one CodeReview agent for the gate-1 implementation. It must review completeness against this plan, BLE/Wi-Fi lifecycle correctness, sensitive-data handling, error recovery, and test coverage. Resolve high-signal findings and rerun Step 6.

- [ ] **Step 8: Commit gate evidence and build tooling**

```bash
git -C .. add gremote/scripts gremote/docs gremote/lib gremote/android gremote/test gremote/integration_test gremote/pubspec.yaml gremote/pubspec.lock
git -C .. commit -m "test: verify gremote stock GR III protocol gate"
```

## Gate Exit Criteria

Do not write the next implementation plan until all are true:

- Xiaomi 14 can scan, pair and reconnect to the user's GR III;
- model and firmware identify the expected camera and 2.10 firmware;
- App can wake the camera and enable AP over BLE;
- Android obtains user-approved camera Wi-Fi and camera requests stay on that network;
- `/v1/ping` and `/v1/props` response shapes are captured and modeled;
- Live View runs for 30 minutes or the observed safe thermal limit is documented and enforced;
- AF shutter works through at least one verified path;
- no passphrase, serial, exact device address, image bytes or exact location appears in logs/diagnostics;
- all tests and analyzer checks pass;
- the test APK hash and completed hardware checklist are recorded.

Evidence from this gate determines the exact contracts for the next plan: full remote shooting, status subscriptions, downloads, GPS, time synchronization and foreground services.
