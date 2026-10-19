import CoreBluetooth
import Foundation

/// Main-thread CoreBluetooth state. One ATT operation at a time; all waits expire.
final class RicohBluetooth: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  private lazy var central = CBCentralManager(delegate: self, queue: .main)
  private var devices: [UUID: CBPeripheral] = [:]
  private var seen: [UUID: NativeBleDevice] = [:]
  private var peripheral: CBPeripheral?
  private var characteristics: [String: CBCharacteristic] = [:]
  private var connection: ((Result<Void, Error>) -> Void)?
  private var operation: ((Result<Data, Error>) -> Void)?
  private var operationID: UUID?
  private var scanID: UUID?
  private var scanResult: ((Result<[NativeBleDevice?], Error>) -> Void)?
  var event: ((String, [String: Any]) -> Void)?
  static let model = "35FE6272-6AA5-44D9-88E1-F09427F51A71"
  static let firmware = "B4EB8905-7411-40A6-A367-2834C2157EA7"
  static let battery = "875FC41D-4980-434C-A653-FD4A4D4410C4"
  static let ssid = "90638E5A-E77D-409D-B550-78F7E1CA5AB4"
  static let password = "0F38279C-FE9E-461B-8596-81287E8C9A81"
  static let power = "B58CE84C-0666-4DE9-BEC8-2D27B27B3211"
  static let network = "9111CDD0-9F01-45C4-A2D4-E09E8FB0424D"
  static let request = "559644B8-E0BC-4011-929B-5CF9199851E7"

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .poweredOn && central.state != .unknown && central.state != .resetting {
      finishScan(.failure(nativeError("bluetoothUnavailable", "请开启蓝牙并允许访问")))
      disconnect()
    }
  }
  func scan(milliseconds: Int64, completion: @escaping (Result<[NativeBleDevice?], Error>) -> Void) {
    guard scanResult == nil else { completion(.failure(nativeError("bleBusy", "正在搜索相机"))); return }
    seen.removeAll(); scanResult = completion
    let token = UUID(); scanID = token
    let end = Date().addingTimeInterval(Double(min(max(milliseconds, 1000), 30000)) / 1000)
    func begin() {
      guard self.scanID == token else { return }
      if self.central.state == .unknown || self.central.state == .resetting {
        if Date() >= end { self.finishScan(.failure(nativeError("bleTimeout", "蓝牙初始化超时"))) }
        else { DispatchQueue.main.asyncAfter(deadline: .now()+0.2, execute: begin) }
        return
      }
      guard self.central.state == .poweredOn else { self.finishScan(.failure(nativeError("bluetoothUnavailable", "请开启蓝牙并允许访问"))); return }
      self.central.scanForPeripherals(withServices: nil)
      DispatchQueue.main.asyncAfter(deadline: .now()+max(0, end.timeIntervalSinceNow)) {
        if self.scanID == token { self.finishScan(.success(self.seen.values.map { Optional($0) })) }
      }
    }
    begin()
  }
  private func finishScan(_ result: Result<[NativeBleDevice?], Error>) {
    central.stopScan(); scanID = nil
    let callback = scanResult; scanResult = nil; callback?(result)
  }
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
    guard name.uppercased().contains("GR") || name.uppercased().contains("RICOH") else { return }
    devices[peripheral.identifier] = peripheral
    seen[peripheral.identifier] = NativeBleDevice(id: peripheral.identifier.uuidString, name: name, rssi: RSSI.int64Value)
  }
  func connect(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
    disconnect()
    guard let uuid = UUID(uuidString: id), let candidate = devices[uuid] ?? central.retrievePeripherals(withIdentifiers: [uuid]).first else {
      completion(.failure(nativeError("bleDeviceNotFound", "请重新搜索相机"))); return
    }
    finishScan(.success(seen.values.map { Optional($0) }))
    peripheral = candidate; candidate.delegate = self; connection = completion
    central.connect(candidate)
    DispatchQueue.main.asyncAfter(deadline: .now()+20) { [weak self, weak candidate] in
      guard let self = self, let candidate = candidate, self.peripheral === candidate, self.connection != nil else { return }
      let callback = self.connection; self.connection = nil
      self.disconnect(); callback?(.failure(nativeError("bleTimeout", "蓝牙连接超时")))
    }
  }
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard self.peripheral === peripheral else { return }
    peripheral.discoverServices(nil)
  }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard self.peripheral === peripheral else { return }
    if let error = error { finishConnection(.failure(error)); return }
    let services = peripheral.services ?? []
    pendingServices = services.count
    if services.isEmpty { finishConnection(.failure(nativeError("unsupportedCamera", "未发现相机服务"))) }
    services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
  }
  private var pendingServices = 0
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard self.peripheral === peripheral else { return }
    if let error = error { finishConnection(.failure(error)); return }
    for characteristic in service.characteristics ?? [] { characteristics[characteristic.uuid.uuidString.uppercased()] = characteristic }
    pendingServices -= 1
    if pendingServices == 0 {
      if characteristics[Self.model] != nil { finishConnection(.success(())); event?("bleState", ["state":"connected"]) }
      else { finishConnection(.failure(nativeError("unsupportedCamera", "未发现 GR 型号信息"))) }
    }
  }
  private func finishConnection(_ result: Result<Void, Error>) {
    let callback = connection; connection = nil; callback?(result)
    if case .failure = result { disconnect() }
  }
  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    guard self.peripheral === peripheral else { return }
    finishConnection(.failure(error ?? nativeError("bleConnectFailed", "连接失败")))
  }
  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    guard self.peripheral === peripheral else { return }
    disconnect(); event?("bleState", ["state":"disconnected"])
  }
  func disconnect() {
    let old = peripheral; peripheral = nil; characteristics.removeAll()
    if let old = old { central.cancelPeripheralConnection(old) }
    let callback = connection; connection = nil; callback?(.failure(nativeError("bleDisconnected", "相机已断开")))
    finishOperation(.failure(nativeError("bleDisconnected", "相机已断开")))
  }
  func read(_ id: String, completion: @escaping (Result<Data, Error>) -> Void) {
    transact(id, value: nil, completion: completion)
  }
  func write(_ id: String, value: Data, completion: @escaping (Result<Void, Error>) -> Void) {
    transact(id, value: value) { completion($0.map { _ in () }) }
  }
  private func transact(_ id: String, value: Data?, completion: @escaping (Result<Data, Error>) -> Void) {
    guard operation == nil else { completion(.failure(nativeError("bleBusy", "相机操作尚未完成"))); return }
    guard let device = peripheral, let characteristic = characteristics[id] else { completion(.failure(nativeError("bleDisconnected", "相机服务不可用"))); return }
    operation = completion; let token = UUID(); operationID = token; operationCharacteristic = characteristic.uuid
    if let value = value { device.writeValue(value, for: characteristic, type: .withResponse) }
    else { device.readValue(for: characteristic) }
    DispatchQueue.main.asyncAfter(deadline: .now()+8) { [weak self] in
      guard let self = self, self.operationID == token else { return }
      // Disconnect on timeout so a late response can never complete a newer ATT operation.
      self.disconnect()
    }
  }
  private var operationCharacteristic: CBUUID?
  private func finishOperation(_ result: Result<Data, Error>) {
    let callback = operation; operation = nil; operationID = nil; operationCharacteristic = nil; callback?(result)
  }
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard self.peripheral === peripheral, operationCharacteristic == characteristic.uuid else { return }
    if let error = error { finishOperation(.failure(error)) }
    else { finishOperation(.success(characteristic.value ?? Data())) }
  }
  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard self.peripheral === peripheral, operationCharacteristic == characteristic.uuid else { return }
    if let error = error { finishOperation(.failure(error)) } else { finishOperation(.success(Data())) }
  }
  func bootstrap(completion: @escaping (Result<NativeCameraBootstrap, Error>) -> Void) {
    let ids = [Self.model, Self.firmware, Self.battery, Self.ssid, Self.password]
    var values: [Data] = []
    func next(_ index: Int) {
      if index == ids.count {
        func text(_ i: Int) -> String { String(data: values[i], encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? "" }
        let battery = values[2]
        guard (1...2).contains(battery.count), battery[0] <= 100, battery.count == 1 || battery[1] <= 1 else {
          completion(.failure(nativeError("invalidPayload", "电量数据格式无效"))); return
        }
        completion(.success(NativeCameraBootstrap(model: text(0), firmware: text(1), batteryLevel: values[2].first.map { Int64($0) }, acPowered: battery.count == 2 && battery[1] == 1, ssid: text(3), passphrase: text(4))))
        return
      }
      self.read(ids[index]) { result in
        switch result { case .success(let data): values.append(data); next(index+1)
        case .failure(let error): completion(.failure(error)) }
      }
    }
    next(0)
  }
}
