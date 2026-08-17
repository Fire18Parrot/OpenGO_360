# GoControl for iOS

SwiftUI + CoreBluetooth port of the Android app. Targets **iOS 17.0+**, so it runs on
iOS 18.x.

## Build

**Requires a Mac with Xcode 15 or newer.** Nothing here can be compiled on Linux.

### With XcodeGen (recommended)

```sh
brew install xcodegen
cd ios
xcodegen generate
open GoControl.xcodeproj
```

Then set your signing team on the GoControl target and run on a device.

### Without extra tools

1. Xcode → File → New → Project → iOS → App
   - Product Name: `GoControl`, Interface: SwiftUI, Language: Swift
   - Delete the generated `ContentView.swift` and `GoControlApp.swift`
2. Drag the eight files from `ios/GoControl/` into the target
3. Target → General → Minimum Deployments → iOS 17.0
4. Target → Info → add **`Privacy - Bluetooth Always Usage Description`**
   (`NSBluetoothAlwaysUsageDescription`) with any user-facing string.
   **Without this key the app traps the instant `CBCentralManager` is created.**

### Must run on real hardware

The Simulator has no Bluetooth stack. `CBCentralManager` reports `.unsupported` there and
the UI will sit on "Bluetooth LE not supported". Use a physical iPhone.

## Layout

| File | Ported from |
|---|---|
| `GoCore.swift` | `GoCore.kt` — wire protocol, unchanged semantics |
| `BleClient.swift` | `BleClient.kt` — Android GATT → CoreBluetooth |
| `Theme.swift` | `Palette` / `GoTheme` from `MainActivity.kt` |
| `Components.swift` | `Card`, `Label`, `CameraGlyph`, `ActionCircle`, `Tele`, `RoundBtn`, `Seg` |
| `ConnectScreen.swift` | `ConnectScreen` composable |
| `Panes.swift` | `ControlPane`, `FilesPane`, `ActivityPane`, `SettingsSheet` |
| `AppRoot.swift` | `AppRoot` + `MainScaffold` from `Ui.kt` |
| `GoControlApp.swift` | `MainActivity` lifecycle |

`GoCore.swift` stays the single source of truth for the protocol, exactly as
`GoCore.kt` does on Android — keep the two in step.

## Platform differences, and why

| Android | iOS | Reason |
|---|---|---|
| Manual CCCD descriptor write | `setNotifyValue(true:for:)` | CoreBluetooth writes the CCCD itself |
| `requestMtu(517)` | nothing | iOS negotiates the ATT MTU; read it back via `maximumWriteValueLength(for:)` |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` / `ACCESS_FINE_LOCATION` | `NSBluetoothAlwaysUsageDescription` | iOS has one Bluetooth prompt and needs no location permission for BLE |
| `dev.address` (MAC) | `peripheral.identifier` | iOS never exposes the hardware address; this UUID is per-install |
| `WRITE_TYPE_DEFAULT` | `.withResponse` | Same thing — a GATT Write Request |
| — | peripheral held in a property | iOS drops the connection mid-handshake if the `CBPeripheral` isn't retained |

Scanning is unfiltered and matches on the `"GO "` name prefix, same as Android, because the
GO 1 does not advertise service `be80` in its advertisement packet.

## What has been verified, and what has not

**Verified.** The protocol layer was cross-checked against the real `GoCore.kt`: the Kotlin
was compiled and run to produce ground truth over 37 vectors — every command frame, varint
edge cases (0, 127, 128, 300, 2³²), nested and flat battery decoding, storage, capture
status, capture-stopped with nested URI, temperature, the notification/reply split at code
8192, fragmented reassembly across chunk boundaries, type-5 keepalive skipping, noise
resync, and two frames arriving in one chunk. A Python transcription of `GoCore.swift`
reproduced all 37 byte-for-byte.

**Not verified.** None of this Swift has been compiled — there is no Swift toolchain or
Xcode on the Linux machine it was written on. Expect to fix ordinary compile errors on
first build. The BLE and UI layers have never been exercised against a camera; only the
protocol logic has been tested.
