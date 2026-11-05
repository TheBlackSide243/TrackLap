import Foundation
import CoreBluetooth
import Observation

/// The TrackLap BLE service of the ESP32 (protocol v1, see README).
enum TrackLapBLE {
    static let service = CBUUID(string: "7A1C0000-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    static let fix = CBUUID(string: "7A1C0001-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    static let lap = CBUUID(string: "7A1C0002-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    static let track = CBUUID(string: "7A1C0003-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    static let control = CBUUID(string: "7A1C0004-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    static let info = CBUUID(string: "7A1C0005-3F4B-4C8E-9D2A-6B1E5F0A9C10")
}

struct DeviceInfo: Decodable {
    var fw: String? = nil
    var chip: String? = nil
    /// Empty while no GPS module answers.
    var gps: String? = nil
    var hz: Int? = nil
    /// The GPIOs the GPS is wired to.
    var rx: Int? = nil
    var tx: Int? = nil
    var name: String? = nil
    /// The board's accelerometer ("QMI8658"), empty or nil without one.
    var imu: String? = nil
}

struct FoundDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    let peripheral: CBPeripheral
}

/// Little-endian packets of protocol v1.
enum BLEPacket {
    struct Fix {
        var valid: Bool
        var sats: Int
        var rate: Int
        var itow: Double
        var lat: Double
        var lon: Double
        var speed: Double
        var heading: Double
        var alt: Double? = nil
        /// From the board's accelerometer, in g: lateral (+ right) and longitudinal (+ accelerating).
        var g: GPoint? = nil
    }

    /// 20 bytes: version, flags, sats, rate Hz, iTOW ms (u32), lat/lon 1e-7° (i32), speed cm/s (u16), heading 0.01° (u16);
    /// from firmware 0.7.0 then the altitude above sea level in mm (i32, INT32_MIN for none); from 0.9.2
    /// the accelerometer's lateral and longitudinal g in milli-g (i16 each, INT16_MIN for none).
    static func fix(_ data: Data) -> Fix? {
        guard data.count >= 20 else { return nil }
        let b = [UInt8](data)
        func u16(_ i: Int) -> UInt16 {
            UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
        }
        func u32(_ i: Int) -> UInt32 {
            let lo = UInt32(u16(i))
            let hi = UInt32(u16(i + 2))
            return lo | (hi << 16)
        }
        return Fix(valid: b[1] & 1 == 1,
                   sats: Int(b[2]),
                   rate: Int(b[3]),
                   itow: Double(u32(4)) / 1000,
                   lat: Double(Int32(bitPattern: u32(8))) * 1e-7,
                   lon: Double(Int32(bitPattern: u32(12))) * 1e-7,
                   speed: Double(u16(16)) / 100,
                   heading: Double(u16(18)) / 100,
                   alt: b.count >= 24 && Int32(bitPattern: u32(20)) != Int32.min ? Double(Int32(bitPattern: u32(20))) / 1000 : nil,
                   g: g(b))
    }

    private static func g(_ b: [UInt8]) -> GPoint? {
        guard b.count >= 28 else { return nil }
        let lateral = Int16(bitPattern: UInt16(b[24]) | UInt16(b[25]) << 8)
        let longitudinal = Int16(bitPattern: UInt16(b[26]) | UInt16(b[27]) << 8)
        guard lateral != Int16.min, longitudinal != Int16.min else { return nil }
        return GPoint(lateral: Double(lateral) / 1000, longitudinal: Double(longitudinal) / 1000)
    }

    /// The fix's UTC time: iTOW counts from the start of the GPS week, GPS time runs 18 s ahead of
    /// UTC, and which week it is comes from the phone's clock.
    static func utc(itow: Double, now: Date = Date()) -> Double {
        let epoch = 315_964_800.0, leap = 18.0, week = 604_800.0
        let gpsNow = now.timeIntervalSince1970 - epoch + leap
        var start = (gpsNow / week).rounded(.down) * week
        let into = gpsNow - start
        if itow - into > week / 2 { start -= week } else if into - itow > week / 2 { start += week }
        return epoch + start + itow - leap
    }

    /// version 1, gate count, then each gate as latA, lonA, latB, lonB (i32, 1e-7°); the start line comes first.
    static func track(_ t: Track) -> Data? {
        guard let start = t.start else { return nil }
        let gates = [start] + t.sectors
        var d = Data([1, UInt8(gates.count)])
        func put(_ deg: Double) {
            let v = Int32((deg * 1e7).rounded()).littleEndian
            withUnsafeBytes(of: v) { d.append(contentsOf: $0) }
        }
        for g in gates {
            put(g.a.lat)
            put(g.a.lon)
            put(g.b.lat)
            put(g.b.lon)
        }
        return d
    }
}

@Observable
final class BLEManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum State { case off, unauthorized, unsupported, idle, scanning, connecting, connected }

    private(set) var state: State = .idle
    private(set) var devices: [FoundDevice] = []
    private(set) var connectedName: String? = nil
    private(set) var info: DeviceInfo? = nil
    private(set) var sats = 0
    private(set) var rateHz = 0
    private(set) var hasFix = false
    private(set) var deviceLapTime: Double? = nil
    @ObservationIgnored var onSample: ((Sample) -> Void)? = nil
    @ObservationIgnored var onConnected: (() -> Void)? = nil

    @ObservationIgnored private var central: CBCentralManager? = nil
    @ObservationIgnored private var peripheral: CBPeripheral? = nil
    @ObservationIgnored private var characteristics: [CBUUID: CBCharacteristic] = [:]
    @ObservationIgnored private var pendingTrack: Data? = nil
    @ObservationIgnored private var keepConnected = false
    @ObservationIgnored private var weekOffset: Double = 0
    @ObservationIgnored private var lastITOW: Double? = nil
    @ObservationIgnored private var scanTimeout: DispatchWorkItem? = nil
    @ObservationIgnored private var infoReread = false

    private static let lastDeviceKey = "lastDevice"

    var stateTitle: String {
        switch state {
        case .off: L("Bluetooth spento")
        case .unauthorized: L("Bluetooth non autorizzato")
        case .unsupported: L("Bluetooth non disponibile")
        case .idle: L("Nessun dispositivo collegato")
        case .scanning: L("Ricerca in corso…")
        case .connecting: L("Collegamento a \(connectedName ?? "TrackLap")…")
        case .connected: connectedName ?? "TrackLap"
        }
    }

    var stateDetail: String {
        switch state {
        case .off: L("Accendilo dal Centro di Controllo.")
        case .unauthorized: L("Consentilo in Impostazioni → TrackLap → Bluetooth.")
        case .unsupported: L("Questo dispositivo non supporta il Bluetooth LE.")
        case .idle: L("Accendi l'ESP32 e tocca Cerca.")
        case .scanning: L("Tieni l'ESP32 acceso e vicino.")
        case .connecting: L("Si ricollega da solo quando torna a portata.")
        case .connected: hasFix ? L("GPS agganciato") : L("In attesa del fix GPS")
        }
    }

    // MARK: - Commands

    func activate() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else if central?.state == .poweredOn, peripheral == nil {
            reconnectLast()
        }
    }

    func deactivate() {
        keepConnected = false
        central?.stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        characteristics = [:]
        resetStatus()
        if central?.state == .poweredOn { state = .idle }
    }

    func scan() {
        activate()
        guard let central, central.state == .poweredOn else { return }
        devices = []
        state = .scanning
        central.scanForPeripherals(withServices: [TrackLapBLE.service], options: nil)
        scanTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    func stopScan() {
        central?.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ d: FoundDevice) {
        central?.stopScan()
        keepConnected = true
        peripheral = d.peripheral
        connectedName = d.name
        state = .connecting
        central?.connect(d.peripheral, options: nil)
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.lastDeviceKey)
        deactivate()
    }

    func send(track: Track) {
        guard let data = BLEPacket.track(track) else { return }
        pendingTrack = data
        flushTrack()
    }

    func resetDeviceSession() {
        write(Data([0x01]), to: TrackLapBLE.control)
    }

    /// Moves the GPS to other GPIOs (nil = the chip's defaults); the ESP32 restarts and reconnects.
    func setGPSPins(rx: Int?, tx: Int?) {
        var d = Data([0x02, 0xFF, 0xFF])
        if let rx, let tx {
            d[1] = UInt8(clamping: rx)
            d[2] = UInt8(clamping: tx)
        }
        write(d, to: TrackLapBLE.control)
    }

    /// A friend's lap for the ESP32 to compare with at every line: its time and when it crossed each
    /// sector line (0 where unknown); nil puts the ESP32's own best lap back.
    func setRival(time: Double?, splits: [Double]) {
        var d = Data([0x03])
        if let time {
            d.append(UInt8(splits.count + 1))
            for v in [time] + splits { d.appendLE(UInt32(clamping: Int((v * 1000).rounded()))) }
        }
        write(d, to: TrackLapBLE.control)
    }

    /// Your place in the live group for the ESP32's screen: position 0 for none, the gap in seconds to
    /// the one ahead (negative when first, the margin over the second).
    func setGroup(position: Int, count: Int, gap: Double?) {
        var d = Data([0x04, UInt8(clamping: position), UInt8(clamping: count)])
        d.appendLE(UInt32(bitPattern: gap.map { Int32(clamping: Int(($0 * 1000).rounded())) } ?? Int32.max))
        write(d, to: TrackLapBLE.control)
    }

    /// The drag dashboard: nil puts the lap one back; otherwise 0 waiting for a stop, 1 ready, 2 a run
    /// in progress, `elapsed` seconds since the launch.
    func setDrag(state: UInt8?, elapsed: Double = 0) {
        guard let state else {
            write(Data([0x05, 0x00]), to: TrackLapBLE.control)
            return
        }
        var d = Data([0x05, 0x01, state])
        d.appendLE(UInt32(clamping: Int((elapsed * 1000).rounded())))
        write(d, to: TrackLapBLE.control)
    }

    /// A drag result for the dashboard, shown for 5 s: a time, or a distance (braking), purple for a best.
    func showDrag(label: String, time: Double?, distance: Double?, best: Bool) {
        var d = Data([0x05, 0x02, (best ? 1 : 0) | (distance != nil ? 2 : 0)])
        let value = distance.map { $0 * 100 } ?? (time ?? 0) * 1000
        d.appendLE(UInt32(clamping: Int(value.rounded())))
        d.append(contentsOf: Array(label.utf8.prefix(12)))
        write(d, to: TrackLapBLE.control)
    }

    private func flushTrack() {
        guard let data = pendingTrack, state == .connected, characteristics[TrackLapBLE.track] != nil else { return }
        write(data, to: TrackLapBLE.track)
        pendingTrack = nil
    }

    private func write(_ data: Data, to uuid: CBUUID) {
        guard let p = peripheral, let c = characteristics[uuid] else { return }
        p.writeValue(data, for: c, type: .withResponse)
    }

    private func reconnectLast() {
        guard let central,
              let s = UserDefaults.standard.string(forKey: Self.lastDeviceKey),
              let id = UUID(uuidString: s),
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        keepConnected = true
        peripheral = p
        connectedName = p.name ?? "TrackLap"
        state = .connecting
        central.connect(p, options: nil)
    }

    private func resetStatus() {
        sats = 0
        rateHz = 0
        hasFix = false
        lastITOW = nil
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .idle
            reconnectLast()
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unsupported
        default:
            state = .off
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "TrackLap"
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[i].rssi = RSSI.intValue
            devices[i].name = name
        } else {
            devices.append(FoundDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastDeviceKey)
        peripheral.delegate = self
        peripheral.discoverServices([TrackLapBLE.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .idle
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        characteristics = [:]
        resetStatus()
        if keepConnected {
            // A pending connection never times out: it comes back on its own when in range.
            state = .connecting
            central.connect(peripheral, options: nil)
        } else {
            state = .idle
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] where s.uuid == TrackLapBLE.service {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            characteristics[c.uuid] = c
            if c.uuid == TrackLapBLE.fix || c.uuid == TrackLapBLE.lap { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == TrackLapBLE.info {
                peripheral.readValue(for: c)
                // The firmware says when the GPS module or its pins change.
                if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
            }
        }
        state = .connected
        connectedName = peripheral.name ?? connectedName
        onConnected?()
        flushTrack()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case TrackLapBLE.fix: handleFix(data)
        case TrackLapBLE.lap: handleLap(data)
        case TrackLapBLE.info: handleInfo(data, characteristic)
        default: break
        }
    }

    private func handleInfo(_ data: Data, _ c: CBCharacteristic) {
        if let i = try? JSONDecoder().decode(DeviceInfo.self, from: data) {
            info = i
            infoReread = false
        } else if !infoReread {
            // A notification longer than the connection's MTU arrives cut: read it whole.
            infoReread = true
            peripheral?.readValue(for: c)
        }
    }

    private func handleFix(_ data: Data) {
        guard let fix = BLEPacket.fix(data) else { return }
        sats = fix.sats
        rateHz = fix.rate
        hasFix = fix.valid
        guard fix.valid else { return }
        // iTOW restarts every Sunday at midnight GPS time.
        if let last = lastITOW, fix.itow < last - 302_400 { weekOffset += 604_800 }
        lastITOW = fix.itow
        onSample?(Sample(t: weekOffset + fix.itow, coord: Coord(fix.lat, fix.lon), speed: fix.speed, heading: fix.heading,
                         utc: BLEPacket.utc(itow: fix.itow), alt: fix.alt, g: fix.g))
    }

    /// version, kind (1 = lap), lap number (u16), time ms (u32): the lap as timed by the ESP32 itself.
    private func handleLap(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 8, b[1] == 1 else { return }
        let ms = UInt32(b[4]) | (UInt32(b[5]) << 8) | (UInt32(b[6]) << 16) | (UInt32(b[7]) << 24)
        deviceLapTime = Double(ms) / 1000
    }
}

private extension Data {
    mutating func appendLE(_ v: UInt32) {
        Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) }
    }
}
