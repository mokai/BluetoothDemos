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

struct  Peripheraler{
    var lastDate:NSTimeInterval!
    var peripheral:CBPeripheral!
}
class ListViewController: UITableViewController,CBCentralManagerDelegate,CBPeripheralDelegate {
    var discoveredPeripherals:[Peripheraler] = []
    
    var centralMgr:CBCentralManager!
    var discoveredPeripheral:CBPeripheral?
    var peripheral:CBPeripheral?
    
    
    var isScanning:Bool = false
    
    private var _connectingView:MBProgressHUD!
    private var connectingView:MBProgressHUD{
        if _connectingView == nil{
            _connectingView = MBProgressHUD(view: self.view)
            _connectingView.labelText = "连接中..."
            _connectingView.mode = MBProgressHUDModeIndeterminate
            self.view .addSubview(_connectingView)
        }
        
        return _connectingView
    }
    
    //MARK:-
    //MARK:life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        self.centralMgr = CBCentralManager(delegate: self, queue: queue)
        //掉线处理
        NSTimer.scheduledTimerWithTimeInterval(GetOutScanTimeInterval, target: self, selector: Selector("refreshPeripheral"), userInfo: nil, repeats: true)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        if(self.centralMgr.state == .PoweredOn){
            self.scan()
        }
        //MARK:断开连接
        if(self.peripheral != nil){
            self.centralMgr.cancelPeripheralConnection(self.peripheral!)
            self.discoveredPeripherals.removeAll(keepCapacity: true)
            super.tableView.reloadData()
        }
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        self.stopScan()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let vc = segue.destinationViewController as? ViewController{
            vc.peripheral = self.peripheral
        }
    }
    
    //MARK:-
    //MARK:bluetooth
    func scan(){
        if(isScanning) {
            return
        }
        isScanning = true
        
        self.centralMgr.scanForPeripheralsWithServices(nil, options: [ CBCentralManagerScanOptionAllowDuplicatesKey : true ])
    }
    
    func stopScan(){
        if(!isScanning) {
            return
        }
        isScanning = false
        self.centralMgr.stopScan()
    }
    
    func refreshPeripheral(){
        println("掉线检测")
        weak var this = self
        let lockQueue = dispatch_queue_create("com.test.LockQueue", nil)
        dispatch_sync(lockQueue) {
            var availables = Array<Peripheraler>()
            let nowTime = NSDate().timeIntervalSince1970
            for i in 0..<this!.discoveredPeripherals.count{
                let peripheraler = this!.discoveredPeripherals[i]
                println(nowTime - peripheraler.lastDate)
                if(peripheraler.lastDate + GetOutTimeInterval > nowTime ){
                    availables.append(peripheraler)
                }else{
                    println("\(peripheraler.peripheral)掉线")
                    
                }
            }
            this!.discoveredPeripherals = availables
        }
    }
    
    //MARK:bluetooth delegate
    func centralManagerDidUpdateState(central: CBCentralManager!){
        if(self.centralMgr.state == .PoweredOn){
            self.scan()
        }
    }
    
    func centralManager(central: CBCentralManager!, didDiscoverPeripheral peripheral: CBPeripheral!, advertisementData: [NSObject : AnyObject]!, RSSI: NSNumber!) {
        println("\n===================发现设备\(peripheral.name)=================\(RSSI)")
        println(advertisementData)
        println(peripheral)
        
        if(discoveredPeripherals.filter{ $0.peripheral == peripheral }.count <= 0){ //未被发现过
            var peripheraler = Peripheraler(lastDate: NSDate().timeIntervalSince1970, peripheral: peripheral)
            
            weak var this = self
            let lockQueue = dispatch_queue_create("com.test.LockQueue", nil)
            dispatch_sync(lockQueue) {
                this!.discoveredPeripherals.append(peripheraler)
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    super.tableView.reloadData()
                })
            }
        }
    }
    
    func centralManager(central: CBCentralManager!, didFailToConnectPeripheral peripheral: CBPeripheral!, error: NSError!) {
        self.connectingView.hide(true)
        println("\n===================连接失败=================\(error)")
        UIAlertView(title: nil, message: "连接失败", delegate: nil, cancelButtonTitle: "确定").show()
    }
    
    func centralManager(central: CBCentralManager!, didConnectPeripheral peripheral: CBPeripheral!) {
        self.connectingView.hide(true)
        println("\n===================连接成功=================")
        stopScan()
        self.peripheral = peripheral
        self.performSegueWithIdentifier(kPushViewController, sender: self)
    }
    
    //MARK:table delegate
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveredPeripherals.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let name = self.discoveredPeripherals[indexPath.row].peripheral.name
        var cell = tableView.dequeueReusableCellWithIdentifier("TableViewCellID") as! UITableViewCell
        (cell.viewWithTag(1) as! UILabel).text = (name == nil || name == "") ? "Unkown Name" : name
        return cell
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        //MKAR连接
        self.connectingView.show(true)
        self.centralMgr.connectPeripheral(self.discoveredPeripherals[indexPath.row].peripheral, options: nil)
    }
    
    //MARK:-
    //MARK:UI EVENT
    @IBAction func onRefresh(sender: AnyObject) {
        //MARK:断开连接
        if(self.peripheral != nil){
            self.discoveredPeripherals.removeAll(keepCapacity: true)
            super.tableView.reloadData()
            self.stopScan()
            self.scan()
        }
//        let identifiers = self.discoveredPeripherals.map { (peripheral) -> NSUUID in
//            return peripheral.identifier.copy() as! NSUUID
//        }
//        let retrievePeripherals = self.centralMgr.retrievePeripheralsWithIdentifiers(identifiers)
//        println(retrievePeripherals)
//        for  peripheral in self.discoveredPeripherals{
//            peripheral.delegate = self
//            peripheral.readRSSI()
//        }
    }
    
    
//    func peripheralDidUpdateRSSI(peripheral: CBPeripheral!, error: NSError!) {
//        if(error != nil){
//            println(error)
//        }else{
//            println("\(peripheral)------------")
//        }
//    }
//    
//    func peripheral(peripheral: CBPeripheral!, didReadRSSI RSSI: NSNumber!, error: NSError!) {
//        peripheral.delegate = nil
//        if(error != nil){
//            println(error)
//        }else{
//            println("\(peripheral)------------\(RSSI)")
//        }
//    }
}