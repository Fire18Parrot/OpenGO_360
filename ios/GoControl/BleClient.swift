import Foundation
import CoreBluetooth

/**
 The whole platform-specific surface of the app — the CoreBluetooth counterpart of
 BleClient.kt. Everything protocol-related lives in GoCore; this class only scans,
 connects, writes bytes to be81 and pipes be82 notifications into
 GoCore.NotificationParser.

 Differences from the Android original, all forced by the platform:
   - No CCCD descriptor write. `setNotifyValue(true:for:)` does it for us.
   - No requestMtu(517). iOS negotiates the ATT MTU itself and exposes the result via
     `maximumWriteValueLength(for:)`.
   - No MAC address. `state.address` carries the CoreBluetooth peripheral UUID, which is
     per-install, not a hardware identifier.
   - The peripheral must be strongly retained or iOS tears the connection down mid-handshake.
 */
final class BleClient: NSObject, ObservableObject {

    static let service = CBUUID(string: "0000BE80-0000-1000-8000-00805F9B34FB")
    static let writeCharUUID = CBUUID(string: "0000BE81-0000-1000-8000-00805F9B34FB")
    static let notifyCharUUID = CBUUID(string: "0000BE82-0000-1000-8000-00805F9B34FB")
    static let namePrefix = "GO "

    enum Phase {
        case idle, scanning, found, connecting, ready, failed
    }

    struct CamState {
        var phase: Phase = .idle
        var name: String? = nil
        var address: String? = nil
        var battery: Int? = nil
        var charging: Bool = false
        var freeBytes: UInt64? = nil
        var totalBytes: UInt64? = nil
        var cardState: String? = nil
        /// TemperatureState label ("Normal"/"Alert"/"Warm"/"Hot"), not degrees.
        var tempState: String? = nil
        var tempLevel: Int? = nil
        var captureState: String = "idle"
        var captureTime: UInt64? = nil
        var remainingSec: UInt64? = nil
        var limitSec: UInt64? = nil
        var message: String? = nil
    }

    @Published private(set) var state = CamState()
    /// Newest first, capped at 60 — the Android build did this capping in the UI layer.
    @Published private(set) var logLines: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private let parser = GoCore.NotificationParser()

    private var scanning = false
    /// Set when startScan() is called before the central is powered on.
    private var scanWhenReady = false
    private var scanTimeout: DispatchWorkItem?

    /**
     Battery and storage are options you poll, not pushes — the camera only emits
     8195/8198 when something *changes*, so without this the telemetry tiles stay empty
     forever. See the revision 2 notes at the top of GoCore.
     */
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 10

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self, self.state.phase == .ready else { return }
            self.send(GoCore.cmdGetOptions())
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    override init() {
        super.init()
        // Under LiveContainer there is no debugger to attach, so the Activity pane is the
        // only diagnostic channel. Bundle.main is the *host* bundle when running as a
        // guest, which makes it a reliable way to tell the two environments apart.
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        if bundleID == "com.gocontrol.app" {
            emit("running standalone")
        } else {
            emit("running as guest in \(bundleID)")
        }
        // .main queue keeps every delegate callback on the main thread, so touching
        // @Published state below is safe without extra hops.
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func stateName(_ s: CBManagerState) -> String {
        switch s {
        case .poweredOn:     return "on"
        case .poweredOff:    return "off"
        case .unauthorized:  return "unauthorized"
        case .unsupported:   return "unsupported"
        case .resetting:     return "resetting"
        case .unknown:       return "unknown"
        @unknown default:    return "?"
        }
    }

    private func emit(_ s: String) {
        logLines.insert(s, at: 0)
        if logLines.count > 60 { logLines.removeLast() }
    }

    private func fail(_ message: String) {
        state.phase = .failed
        state.message = message
        emit(message)
    }

    // ------------------------------------------------------------------ scan
    func startScan() {
        guard central.state == .poweredOn else {
            scanWhenReady = true
            switch central.state {
            case .poweredOff:    fail("Bluetooth is off")
            case .unauthorized:  fail("Bluetooth permission denied")
            case .unsupported:   fail("Bluetooth LE not supported")
            default:             break   // .resetting / .unknown — wait for the delegate
            }
            return
        }
        if scanning { return }
        scanning = true
        state = CamState(phase: .scanning)
        emit("scanning for \"\(Self.namePrefix)…\"")

        // The GO 1 does not advertise be80, so we scan unfiltered and match on name,
        // exactly like the Android build.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.state.phase == .scanning {
                self.stopScan()
                self.fail("No camera found")
            }
        }
        scanTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    func stopScan() {
        scanTimeout?.cancel()
        scanTimeout = nil
        guard scanning else { return }
        scanning = false
        central.stopScan()
    }

    // ------------------------------------------------------------------ connect
    private func connect(_ p: CBPeripheral) {
        state.phase = .connecting
        emit("connecting…")
        p.delegate = self
        peripheral = p
        central.connect(p, options: nil)
    }

    func disconnect() {
        stopScan()
        stopPolling()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        writeCharacteristic = nil
        state = CamState(phase: .idle)
        emit("disconnected")
    }

    // ------------------------------------------------------------------ io
    func send(_ frame: Data) {
        guard let p = peripheral, let c = writeCharacteristic else {
            emit("not connected")
            return
        }
        // Frames are 16-32 bytes, well under the negotiated write length, so no chunking.
        p.writeValue(frame, for: c, type: .withResponse)
    }

    private func handle(_ chunk: [UInt8]) {
        for ev in parser.feed(chunk) {
            switch ev {
            case .battery(let percent, let charging):
                state.charging = charging
                if let percent {
                    state.battery = percent
                    emit("battery \(percent)%" + (charging ? " (charging)" : ""))
                }

            case .storage(let cardState, let free, let total):
                if let free { state.freeBytes = free }
                if let total { state.totalBytes = total }
                state.cardState = cardState
                if let free {
                    emit(String(format: "free %.1f GB", Double(free) / 1e9))
                }

            case .captureStatus(let st, let captureTime, _):
                state.captureState = st
                state.captureTime = captureTime

            case .captureStopped(let errCode, let uri):
                state.captureState = "idle"
                state.captureTime = nil
                if let uri {
                    emit("saved \(uri.split(separator: "/").last.map(String.init) ?? uri)")
                } else {
                    emit("capture stopped (err \(errCode))")
                }

            case .temperature(let st, let level):
                state.tempState = st
                state.tempLevel = level
                if level >= 2 { emit("temperature \(st)") }

            case .remaining(let remainingSec, let limitSec):
                if let remainingSec { state.remainingSec = remainingSec }
                if let limitSec { state.limitSec = limitSec }

            case .fileList(_, let totalCount):
                emit("\(totalCount) file(s) on camera")

            case .reply(let code, _):
                emit("reply \(code)")

            case .notification(let code, _):
                emit("event \(code)")
            }
        }
    }
}

// ------------------------------------------------------------------ central delegate
extension BleClient: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            if scanWhenReady {
                scanWhenReady = false
                startScan()
            }
        case .poweredOff:
            fail("Bluetooth is off")
        case .unauthorized:
            fail("Bluetooth permission denied")
        case .unsupported:
            fail("Bluetooth LE not supported")
        default:
            break
        }
    }

    func centralManager(
        _ c: CBCentralManager,
        didDiscover p: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // The advertised local name is more reliable than the cached peripheral.name.
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let nm = advName ?? p.name else { return }
        guard nm.uppercased().hasPrefix(Self.namePrefix) else { return }

        stopScan()
        state.phase = .found
        state.name = nm
        state.address = p.identifier.uuidString
        emit("found \(nm)")
        peripheral = p   // retain before the delay, or ARC drops it

        // brief beat so the UI can play "found"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.connect(p)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.service])
    }

    func centralManager(
        _ c: CBCentralManager,
        didFailToConnect p: CBPeripheral,
        error: Error?
    ) {
        fail(error?.localizedDescription ?? "Could not connect")
    }

    func centralManager(
        _ c: CBCentralManager,
        didDisconnectPeripheral p: CBPeripheral,
        error: Error?
    ) {
        writeCharacteristic = nil
        stopPolling()
        state.phase = .idle
        emit("link dropped")
    }
}

// ------------------------------------------------------------------ peripheral delegate
extension BleClient: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == Self.service }) else {
            fail("service be80 not found")
            return
        }
        p.discoverCharacteristics([Self.writeCharUUID, Self.notifyCharUUID], for: svc)
    }

    func peripheral(
        _ p: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.writeCharUUID {
                writeCharacteristic = ch
            }
            if ch.uuid == Self.notifyCharUUID {
                // Handles the CCCD write that Android had to do by hand.
                p.setNotifyValue(true, for: ch)
            }
        }

        guard writeCharacteristic != nil else {
            fail("characteristic be81 not found")
            return
        }

        emit("mtu \(p.maximumWriteValueLength(for: .withResponse) + 3)")
        state.phase = .ready
        state.message = nil
        emit("ready")

        // Unlike Android, CoreBluetooth serialises writes internally, so these two do not
        // need staggering the way BleClient.kt does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.send(GoCore.cmdGetStatus())
            self.send(GoCore.cmdGetOptions())
            self.startPolling()
        }
    }

    func peripheral(
        _ p: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.notifyCharUUID,
              let data = characteristic.value else { return }
        handle([UInt8](data))
    }

    func peripheral(
        _ p: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            emit("write failed: \(error.localizedDescription)")
        }
    }
}
