import CoreBluetooth
import Foundation
import Observation

@Observable
@MainActor
public final class ScaleConnection: NSObject {
    public enum BluetoothProblem: Equatable, Sendable {
        case poweredOff
        case unauthorized
        case unsupported
    }

    public enum State: Equatable, Sendable {
        case idle
        case bluetoothUnavailable(BluetoothProblem)
        case searching
        case connecting
        case measuring(liveKg: Double?)
        case finished(ScaleReading)
    }

    public enum Event: Sendable {
        case packet(Data, ScalePacket?)
        case reading(ScaleReading)
        case storedReading(ScaleReading)
    }

    public private(set) var state: State = .idle

    @ObservationIgnored public var onEvent: ((Event) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var scale: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    @ObservationIgnored private var profile: UserProfile?
    @ObservationIgnored private var session = MeasurementSession()
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    private static let service = CBUUID(string: ActiveEraProtocol.serviceUUID)
    private static let writeCharacteristicID = CBUUID(string: ActiveEraProtocol.writeCharacteristicUUID)
    private static let notifyCharacteristicID = CBUUID(string: ActiveEraProtocol.notifyCharacteristicUUID)

    public func start(profile: UserProfile) {
        self.profile = profile
        guard let central else {
            central = CBCentralManager(delegate: self, queue: nil)
            return
        }
        if central.state == .poweredOn, scale == nil {
            search()
        }
    }

    public func stop() {
        finishTask?.cancel()
        central?.stopScan()
        if let scale {
            central?.cancelPeripheralConnection(scale)
        }
        scale = nil
        profile = nil
        session = MeasurementSession()
        state = .idle
    }

    private func search() {
        if !session.isFinished {
            state = .searching
        }
        central?.scanForPeripherals(withServices: [Self.service])
    }

    private func sendConfiguration(to peripheral: CBPeripheral) {
        guard let profile, let writeCharacteristic else { return }
        let packet = ActiveEraProtocol.configurationPacket(for: profile, at: .now)
        peripheral.writeValue(packet, for: writeCharacteristic, type: .withResponse)
    }

    private func handle(_ data: Data) {
        let packet = ActiveEraProtocol.decode(data)
        onEvent?(.packet(data, packet))
        switch packet {
        case nil:
            break
        case let .stored(measurement):
            onEvent?(.storedReading(ScaleReading(measurement)))
        case let .some(packet):
            if let finishDelay = session.consume(packet) {
                scheduleFinish(after: finishDelay)
            }
            if !session.isFinished {
                state = .measuring(liveKg: session.liveWeightKg)
            }
        }
    }

    private func scheduleFinish(after delay: Duration) {
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        finishTask?.cancel()
        guard let reading = session.finish(at: .now) else { return }
        state = .finished(reading)
        onEvent?(.reading(reading))
    }
}

extension ScaleConnection: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if profile != nil {
                search()
            }
        case .poweredOff:
            state = .bluetoothUnavailable(.poweredOff)
        case .unauthorized:
            state = .bluetoothUnavailable(.unauthorized)
        case .unsupported:
            state = .bluetoothUnavailable(.unsupported)
        default:
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard scale == nil else { return }
        central.stopScan()
        scale = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        session = MeasurementSession()
        state = .measuring(liveKg: nil)
        peripheral.discoverServices([Self.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        scale = nil
        search()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish()
        scale = nil
        writeCharacteristic = nil
        if profile != nil {
            search()
        }
    }
}

extension ScaleConnection: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { return }
        peripheral.discoverCharacteristics([Self.writeCharacteristicID, Self.notifyCharacteristicID], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.writeCharacteristicID:
                writeCharacteristic = characteristic
            case Self.notifyCharacteristicID:
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.notifyCharacteristicID, characteristic.isNotifying else { return }
        sendConfiguration(to: peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.notifyCharacteristicID, let data = characteristic.value else { return }
        handle(data)
    }
}
