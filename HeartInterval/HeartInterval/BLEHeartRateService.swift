import CoreBluetooth

enum BLEState {
    case idle
    case scanning
    case available     // Discovered in standby, not connected
    case connecting
    case connected
    case disconnected
}

final class BLEHeartRateService: NSObject {

    private let hrServiceUUID = CBUUID(string: "180D")
    private let hrCharUUID    = CBUUID(string: "2A37")

    private var central:    CBCentralManager?
    private var peripheral: CBPeripheral?

    /// True once we've emitted `.available` for the current standby pass — gates
    /// repeated state callbacks when scanning with `allowDuplicates`.
    private var availableEmitted = false

    /// When true, discovery results lead to an active connection.
    /// When false (standby), discovery only updates the "available" status.
    private var wantsConnection: Bool = false

    var isExercising: Bool = false

    var onHR:           ((Double) -> Void)?
    var onStateChange:  ((BLEState) -> Void)?

    /// Begin passive discovery in standby. Will surface available HR monitors
    /// without holding a connection. Call `start()` to actually connect.
    func startScanning() {
        wantsConnection = false
        availableEmitted = false
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated))
        } else if central?.state == .poweredOn {
            beginDiscovery()
        }
    }

    /// Disconnect from current peripheral and return to standby discovery mode.
    func returnToScanning() {
        isExercising = false
        wantsConnection = false
        availableEmitted = false
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
        }
        peripheral = nil
        if central?.state == .poweredOn {
            beginDiscovery()
        }
    }

    /// Begin exercise: connect to a discovered/system-connected peripheral, or scan and auto-connect.
    func start() {
        isExercising = true
        wantsConnection = true
        availableEmitted = false
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated))
            return
        }
        if central?.state == .poweredOn {
            connectToAvailableOrScan()
        }
    }

    func stop() {
        isExercising = false
        wantsConnection = false
        availableEmitted = false
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        central?.stopScan()
        peripheral = nil
        onStateChange?(.idle)
    }

    // MARK: - Discovery helpers

    /// Standby discovery: surface availability via `retrieveConnectedPeripherals` first,
    /// fall back to scanning. Never calls `connect`.
    private func beginDiscovery() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [hrServiceUUID])
        if let p = connected.first {
            self.peripheral = p
            availableEmitted = true
            onStateChange?(.available)
            return
        }
        onStateChange?(.scanning)
        central.scanForPeripherals(
            withServices: [hrServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    /// Exercise-start discovery: prefer a system-connected HR peripheral, then a peripheral
    /// already discovered in standby, then a fresh scan that auto-connects on discover.
    private func connectToAvailableOrScan() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [hrServiceUUID])
        if let p = connected.first {
            self.peripheral = p
            central.stopScan()
            onStateChange?(.connecting)
            central.connect(p, options: nil)
            return
        }
        if let p = peripheral {
            central.stopScan()
            onStateChange?(.connecting)
            central.connect(p, options: nil)
            return
        }
        onStateChange?(.scanning)
        central.scanForPeripherals(
            withServices: [hrServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEHeartRateService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        if wantsConnection {
            connectToAvailableOrScan()
        } else {
            beginDiscovery()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        if wantsConnection {
            central.stopScan()
            onStateChange?(.connecting)
            central.connect(peripheral, options: nil)
        } else if !availableEmitted {
            availableEmitted = true
            onStateChange?(.available)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([hrServiceUUID])
        onStateChange?(.connected)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onStateChange?(.disconnected)
        self.peripheral = nil
        if wantsConnection {
            connectToAvailableOrScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onStateChange?(.disconnected)
        if isExercising, wantsConnection {
            onStateChange?(.connecting)
            central.connect(peripheral, options: nil)
        }
        // Else: returnToScanning() (if it triggered this disconnect) already restarted discovery.
        // Do NOT re-enter returnToScanning() here — it caused duplicate scan sessions.
    }
}

// MARK: - CBPeripheralDelegate
extension BLEHeartRateService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == hrServiceUUID }) else { return }
        peripheral.discoverCharacteristics([hrCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let char = service.characteristics?.first(where: { $0.uuid == hrCharUUID }) else { return }
        peripheral.setNotifyValue(true, for: char)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == hrCharUUID,
              let data = characteristic.value, data.count >= 2 else { return }

        // Byte 0: flags. Bit 0 = 0 → HR is UInt8 at byte 1; Bit 0 = 1 → HR is UInt16 at bytes 1-2
        let flags = data[0]
        let bpm: Double = (flags & 0x01) == 0
            ? Double(data[1])
            : Double(UInt16(data[1]) | UInt16(data[2]) << 8)

        onHR?(bpm)
    }
}
