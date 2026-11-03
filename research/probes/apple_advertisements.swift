// Untested — needs user. Advertisement observation only; no connections/writes.
// Sources and deliberately tentative decoding: README.md (accessed 2026-10-30).
import Foundation
import CoreBluetooth

guard CBManager.authorization == .allowedAlways else {
    print("No existing Bluetooth authorization. Exiting without requesting it.")
    exit(2)
}

final class Observer: NSObject, CBCentralManagerDelegate {
    var manager: CBCentralManager!
    var labels: [UUID: Int] = [:]
    let started = ProcessInfo.processInfo.systemUptime

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            print("Observing Apple advertisements; no pairing, connections, or writes.")
        case .unknown, .resetting:
            print("Waiting for existing Bluetooth state.")
        default:
            print("Bluetooth unavailable (state \(central.state.rawValue)); exiting.")
            exit(3)
        }
        fflush(stdout)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0x4c, bytes[1] == 0x00 else { return }
        if labels[peripheral.identifier] == nil {
            labels[peripheral.identifier] = labels.count + 1
        }
        let prefix = bytes.prefix(13).map { String(format: "%02x", $0) }.joined(separator: " ")
        var candidate = ""
        if bytes.count == 29, bytes[2] == 0x07, bytes[3] == 0x19 {
            let value = bytes[10]
            candidate = " candidate-lid-byte=\(value) low3=\(value & 7) bit3=\((value >> 3) & 1)"
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print(String(format: "%.3f", elapsed), "device=\(labels[peripheral.identifier]!)",
              "rssi=\(RSSI)", "length=\(bytes.count)", "prefix=\(prefix)" + candidate)
        fflush(stdout)
    }
}

let observer = Observer()
observer.manager = CBCentralManager(delegate: observer, queue: .main,
    options: [CBCentralManagerOptionShowPowerAlertKey: false])
DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
    observer.manager.stopScan()
    print("Finished.")
    exit(0)
}
RunLoop.main.run()
