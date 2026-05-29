import CoreBluetooth

enum BLEState {
    case idle
    case scanning
    case connecting
    case connected
    case disconnected
}

final class BLEHeartRateService: NSObject {

    private let hrServiceUUID = CBUUID(string: "180D")
    private let hrCharUUID    = CBUUID(string: "2A37")

    private var central:    CBCentralManager?
    private var peripheral: CBPeripheral?

    var isExercising: Bool = false

    var onHR:           ((Double) -> Void)?
    var onStateChange:  ((BLEState) -> Void)?

    /// Start scanning. If central has not been created yet, creates it (which will trigger
    /// centralManagerDidUpdateState when powered on). If already powered on, starts scanning immediately.
    func startScanning() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated))
        } else if central?.state == .poweredOn {
            onStateChange?(.scanning)
            central?.scanForPeripherals(withServices: [hrServiceUUID], options: nil)
        }
    }

    /// Disconnect from current peripheral and return to scanning (standby mode).
    func returnToScanning() {
        isExercising = false
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
        }
        peripheral = nil
        onStateChange?(.scanning)
        if central?.state == .poweredOn {
            central?.scanForPeripherals(withServices: [hrServiceUUID], options: nil)
        }
    }

    func start() {
        isExercising = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated))
        } else if central?.state == .poweredOn {
            onStateChange?(.scanning)
            central?.scanForPeripherals(withServices: [hrServiceUUID], options: nil)
        }
    }

    func stop() {
        isExercising = false
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        central?.stopScan()
        peripheral = nil
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEHeartRateService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            onStateChange?(.scanning)
            central.scanForPeripherals(withServices: [hrServiceUUID], options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        central.stopScan()
        onStateChange?(.connecting)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([hrServiceUUID])
        onStateChange?(.connected)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onStateChange?(.disconnected)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onStateChange?(.disconnected)
        if isExercising {
            // Auto-reconnect during exercise
            if let p = self.peripheral {
                onStateChange?(.connecting)
                central.connect(p, options: nil)
            }
        } else {
            // Return to scanning in standby
            returnToScanning()
        }
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
