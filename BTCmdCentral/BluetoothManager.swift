//
//  BluetoothManager.swift
//  BTCmdCentral
//
//  Created by Jay Tucker on 1/14/15.
//  Copyright (c) 2015 Imprivata. All rights reserved.
//

import Foundation
import CoreBluetooth

class BluetoothManager: NSObject {
    
    let provisioningServiceUUID = CBUUID(string: "193DB24F-E42E-49D2-9A70-6A5616863A9D")
    let commandCharacteristicUUID = CBUUID(string: "43CDD5AB-3EF6-496A-A4CC-9933F5ADAF68")
    let responseCharacteristicUUID = CBUUID(string: "F1A9A759-C922-4219-B62C-1A14F62DE0A4")
    
    let timeoutInSecs = 5.0
    
    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral!
    var responseCharacteristic: CBCharacteristic!
    var isPoweredOn = false
    var scanTimer: NSTimer!
    
    var isBusy = false
    
    // See:
    // http://stackoverflow.com/questions/24218581/need-self-to-set-all-constants-of-a-swift-class-in-init
    // http://stackoverflow.com/questions/24441254/how-to-pass-self-to-initializer-during-initialization-of-an-object-in-swift
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate:self, queue:nil)
    }
    
    func sendCommand() {
        log("sendCommand")
        if (isBusy) {
            log("busy, ignoring request")
            return
        }
        isBusy = true
        startScanForPeripheralWithService(provisioningServiceUUID)
    }
    
    private func startScanForPeripheralWithService(uuid: CBUUID) {
        log("startScanForPeripheralWithService \(nameFromUUID(uuid)) \(uuid)")
        centralManager.stopScan()
        scanTimer = NSTimer.scheduledTimerWithTimeInterval(timeoutInSecs, target: self, selector: Selector("timeout"), userInfo: nil, repeats: false)
        centralManager.scanForPeripheralsWithServices([uuid], options: nil)
    }
    
    // can't be private because called by timer
    func timeout() {
        log("timed out")
        centralManager.stopScan()
        isBusy = false
    }
    
    private func nameFromUUID(uuid: CBUUID) -> String {
        switch uuid {
        case provisioningServiceUUID: return "provisioningService"
        case commandCharacteristicUUID: return "commandCharacteristic"
        case responseCharacteristicUUID: return "responseCharacteristic"
        default: return "unknown"
        }
    }
    
}

extension BluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(central: CBCentralManager!) {
        var caseString: String!
        switch centralManager.state {
        case .Unknown:
            caseString = "Unknown"
        case .Resetting:
            caseString = "Resetting"
        case .Unsupported:
            caseString = "Unsupported"
        case .Unauthorized:
            caseString = "Unauthorized"
        case .PoweredOff:
            caseString = "PoweredOff"
        case .PoweredOn:
            caseString = "PoweredOn"
        default:
            caseString = "WTF"
        }
        log("centralManagerDidUpdateState \(caseString)")
        isPoweredOn = (centralManager.state == .PoweredOn)
        if isPoweredOn {
            sendCommand()
        }
    }
    
    func centralManager(central: CBCentralManager!, didDiscoverPeripheral peripheral: CBPeripheral!, advertisementData: [NSObject : AnyObject]!, RSSI: NSNumber!) {
        log("centralManager didDiscoverPeripheral")
        scanTimer.invalidate()
        centralManager.stopScan()
        self.peripheral = peripheral
        centralManager.connectPeripheral(peripheral, options: nil)
    }
    
    func centralManager(central: CBCentralManager!, didConnectPeripheral peripheral: CBPeripheral!) {
        log("centralManager didConnectPeripheral")
        self.peripheral.delegate = self
        peripheral.discoverServices([provisioningServiceUUID])
    }
    
}

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(peripheral: CBPeripheral!, didDiscoverServices error: NSError!) {
        if error == nil {
            log("peripheral didDiscoverServices ok")
        } else {
            log("peripheral didDiscoverServices error \(error.localizedDescription)")
            return
        }
        for service in peripheral.services {
            log("service \(nameFromUUID(service.UUID))  \(service.UUID)")
            peripheral.discoverCharacteristics(nil, forService: service as! CBService)
        }
    }
    
    func peripheral(peripheral: CBPeripheral!, didDiscoverCharacteristicsForService service: CBService!, error: NSError!) {
        if error == nil {
            log("peripheral didDiscoverCharacteristicsForService \(service.UUID) ok")
        } else {
            log("peripheral didDiscoverCharacteristicsForService error \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics {
            let name = nameFromUUID(characteristic.UUID)
            log("characteristic \(name) \(characteristic.UUID)")
            if characteristic.UUID == commandCharacteristicUUID {
                let data = "Hello, World!".dataUsingEncoding(NSUTF8StringEncoding)
                peripheral.writeValue(data, forCharacteristic: characteristic as! CBCharacteristic, type: CBCharacteristicWriteType.WithResponse)
            } else if characteristic.UUID == responseCharacteristicUUID {
                responseCharacteristic = characteristic as! CBCharacteristic
            }
        }
    }
    
    func peripheral(peripheral: CBPeripheral!, didWriteValueForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
        if error == nil {
            log("peripheral didWriteValueForCharacteristic ok")
            peripheral.readValueForCharacteristic(responseCharacteristic)
        } else {
            log("peripheral didWriteValueForCharacteristic error \(error.localizedDescription)")
        }
    }

    func peripheral(peripheral: CBPeripheral!, didUpdateValueForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
        if error == nil {
            let name = nameFromUUID(characteristic.UUID)
            log("peripheral didUpdateValueForCharacteristic \(name) ok")
            let value: String = NSString(data: characteristic.value, encoding: NSUTF8StringEncoding)! as String
            log("received response: \(value)")
        } else {
            log("peripheral didUpdateValueForCharacteristic error \(error.localizedDescription)")
            return
        }
        log("disconnecting")
        centralManager.cancelPeripheralConnection(peripheral)
        self.peripheral = nil
        self.responseCharacteristic = nil
        isBusy = false
    }
    
}