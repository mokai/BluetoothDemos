//
//  ViewController.swift
//  TestCentral
//
//  Created by gongkai on 15/7/6.
//  Copyright (c) 2015年 gigaiot. All rights reserved.
//

import UIKit
import CoreBluetooth

let kPushViewController = "PushViewController"
let GetOutScanTimeInterval:NSTimeInterval = 10
let GetOutTimeInterval:NSTimeInterval = 30


class ListViewController: UITableViewController,BLEDelegate {
    var discoveredPeripherals:[CBPeripheral] = []
    var ble:BLE!
    
    //MARK:-
    //MARK:life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.ble = BLE.shareInstanceWithDelegate(self)
        self.ble.configurationNotifyingCharacteristics = [
            CBUUID(string: "FF02")
        ]
        self.ble.updatingEOMFlag = "EOM"
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.discoveredPeripherals.removeAll(keepCapacity: true)
        self.ble.scan(nil)
        super.tableView.reloadData()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        self.ble.stopScan()
    }
    
    //MARK:bluetooth delegate
    func centralManagerDidUpdateState(central: CBCentralManager){
        self.ble.centralManagerDidUpdateState()
    }
    
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        self.discoveredPeripherals.append(peripheral)
        super.tableView.reloadData()
    }
    
    func ble(ble: BLE!, didLossPeripheral peripheral: CBPeripheral!) {
        for i in 0..<self.discoveredPeripherals.count{
            if(peripheral.isEqual(self.discoveredPeripherals[i])){
                self.discoveredPeripherals.removeAtIndex(i)
                break
            }
        }
        super.tableView.reloadData()
    }
    
    func ble(ble: BLE!, didUpdateValue value: StringData!, forCharacteristic characteristic: CBCharacteristic, error: NSError!) {
        print(value.string)
    }
    
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        self.performSegueWithIdentifier(kPushViewController, sender: self)
    }
    
    //MARK:table delegate
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveredPeripherals.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let name = self.discoveredPeripherals[indexPath.row].name
        let cell = tableView.dequeueReusableCellWithIdentifier("TableViewCellID")!
        (cell.viewWithTag(1) as! UILabel).text = (name == nil || name == "") ? "Unkown Name" : name
        return cell
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        //MKAR连接
        let peripheral = self.discoveredPeripherals[indexPath.row]
        self.ble.connect(peripheral, options: nil)
    }
    
    //
    //MARK:-
    //MARK:UI EVENT
    @IBAction func onRefresh(sender: AnyObject) {
        //MARK:断开连接
        self.discoveredPeripherals.removeAll(keepCapacity: true)
        self.ble.refresh()
        super.tableView.reloadData()
    }
}