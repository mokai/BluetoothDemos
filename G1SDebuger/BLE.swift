//
//  BLE.swift
//  iOS
//
//   蓝牙
//
//  Created by gongkai on 15/8/3.
//  Copyright (c) 2015年 gongkai. All rights reserved.
//

import Foundation
import CoreBluetooth

//蓝牙数据发送大小
private let  NOTIFY_MTU = 20

class BLE : NSObject,CBCentralManagerDelegate,CBPeripheralDelegate,UIAlertViewDelegate {
    private struct  Peripheraler{
        var lastDate:NSTimeInterval
        var peripheral:CBPeripheral
    }
    private struct  UpdatingDataer{
        var characteristic:CBCharacteristic
        var data:NSMutableData!
    }
    private struct Static {
        static var onceToken : dispatch_once_t = 0
        static var staticInstance : BLE!
    }
    //===================private=========================
    private var centralMgr:CBCentralManager!
    private var serviceUUIDs:[CBUUID]!
    private var discoveredPeripheralers:[Peripheraler] = [] //发现的设备
    
    //===================可读取=========================
    private var _discoveredPeripherals:[CBPeripheral] = []
    //发现的设备
    var discoveredPeripherals:[CBPeripheral]{
        return _discoveredPeripherals
    }
    
    private var _isScanning = false
    //是否在扫描
    var isScanning:Bool{
        return _isScanning
    }
    
    private var _peripheral:CBPeripheral!
    //当前连接的peripheral
    var peripheral:CBPeripheral?{
        return _peripheral
    }
    
    private var _services:[CBService]!
    //发现的服务
    var services:[CBService]?{
        return _services
    }
    
    private var _characteristics:[CBCharacteristic]!
    //发现的特征
    var characteristics:[CBCharacteristic]?{
        return _characteristics
    }
    
    
    //===================可设置=========================
    // 指定时间内未被发现则为掉线
    private var lossTimer:NSTimer?
    var lossTimeInterval:NSTimeInterval = 30
    
    var delegate:BLEDelegate?
    
    /***
        需要订阅的特征
        如果有数据时会同时触发
        * delegate
        * 通知（key为相应特征的UUIDString)，参数为接收的StringData类型数据
    ***/
    var configurationNotifyingCharacteristics:[CBUUID] = []
    
    //数据接收
    private var updatingDatas:[UpdatingDataer]!
    var updatingEOMFlag:String? //数据接收时开始与结束标志

    
    /**
    MARK:初始化
    
    - returns:
    */
    static func shareInstance()->BLE{
        dispatch_once(&Static.onceToken) {
            Static.staticInstance = BLE()
            let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
            Static.staticInstance!.centralMgr = CBCentralManager(delegate: Static.staticInstance, queue: queue)
        }
        return Static.staticInstance
    }
    
    /**
    MARK:初始化
    - parameter delegate: 监听代理
    
    - returns:
    */
    static func shareInstanceWithDelegate(delegate:BLEDelegate?)->BLE{
        self.shareInstance()
        Static.staticInstance.delegate = delegate
        return Static.staticInstance
    }
    
    
    //MARK:-
    //MARK:操作蓝牙

    /**
    MARK: 扫描
    */
    func scan(serviceUUIDs:[CBUUID]?){
        if(self._isScanning) {
            return
        }
        log("scaning")
        self.serviceUUIDs = serviceUUIDs
        self._isScanning = true
        self.centralMgr.scanForPeripheralsWithServices(serviceUUIDs, options: [ CBCentralManagerScanOptionAllowDuplicatesKey : true ])
        self.lossTimer = NSTimer.scheduledTimerWithTimeInterval(10, target: self, selector: Selector("lossScan"), userInfo: nil, repeats: true)
    }
    
    /**
    MARK: 停止扫描
    */
    func stopScan(){
        if(!self._isScanning) {
            return
        }
        self._isScanning = false
        self.centralMgr.stopScan()
        self.lossTimer!.invalidate()
        self.discoveredPeripheralers = []
        self._discoveredPeripherals = []
        log("stopScaning")
    }
    
    /**
    MARK:重新刷新，清空已发现设备
    */
    func refresh(){
        self.discoveredPeripheralers = []
        self._discoveredPeripherals = []
        self.centralMgr.stopScan()
        self.centralMgr.scanForPeripheralsWithServices(serviceUUIDs, options: [ CBCentralManagerScanOptionAllowDuplicatesKey : true ])
    }
    
    /**
    MARK:连接
    - parameter peripheral:
    */
    func connect(peripheral:CBPeripheral,options: [String : AnyObject]?){
        self.centralMgr.connectPeripheral(peripheral, options: options)
        log("connecting")
    }
    
    /**
    MARK:断开连接
    - parameter peripheral:
    */
    func cancel(){
        if(self.peripheral != nil){
            log("canceling")
            self.centralMgr.cancelPeripheralConnection(self.peripheral!)
        }
    }
    
    /**
    获取服务
    
    - parameter uuid: 服务id
    
    - returns:
    */
    func serviceWithUUID(uuid:CBUUID)->CBService?{
        if(self._services==nil){
            return nil
        }
        for service in self._services!{
            if(service.UUID .isEqual(uuid)){
                return service
            }
        }
        return nil
    }
    
    /**
    获取服务中的特征
    */
    func characteristicWithUUID(uuid:CBUUID,forService serviceUUID:CBUUID)->CBCharacteristic?{
        if(self._services == nil || self._characteristics == nil){
            return nil
        }
        for characteristic in self._characteristics!{
            if(characteristic.UUID .isEqual(uuid) && characteristic.service.UUID.isEqual(serviceUUID)){
                return characteristic
            }
        }
        return nil
    }
    
    /**
    订阅数据
    */
    func startNotifying(characteristicUUID:CBUUID,forService serviceUUID:CBUUID){
        if let characteristic = self.characteristicWithUUID(characteristicUUID, forService: serviceUUID){
            peripheral!.setNotifyValue(true, forCharacteristic: characteristic)
        }
    }
    
    /**
        停止订阅数据
    */
    func stopNotifying(characteristicUUID:CBUUID,forService serviceUUID:CBUUID){
        if let characteristic = self.characteristicWithUUID(characteristicUUID, forService: serviceUUID){
            peripheral!.setNotifyValue(false, forCharacteristic: characteristic)
        }
    }
    
    
    /**
        MARK:写数据
    */
    func writeValue(data:NSData,withCharacteristic characteristic:CBCharacteristic)->Bool{
        if(self.peripheral == nil){
            return false
        }
        var didSend = false
        var sendDataIndex = 0
        while (data.length - sendDataIndex != 0) {
            // Work out how big it should be
            var amountToSend = data.length - sendDataIndex
            
            // Can't be longer than 20 bytes
            if (amountToSend > NOTIFY_MTU) {
                amountToSend = NOTIFY_MTU
            }
            let chunk = NSData(bytes: data.bytes + sendDataIndex, length: amountToSend)
            var type:CBCharacteristicWriteType = .WithoutResponse
            if(characteristic.properties == CBCharacteristicProperties.Write){
                type = .WithResponse
            }
            self.peripheral!.writeValue(chunk, forCharacteristic: characteristic, type: type)
            sendDataIndex += amountToSend
        }
        return true
    }
    
    
    func writeValue(data:NSData,withCharacteristicUUID characteristicUUID:CBUUID,forService serviceUUID:CBUUID)->Bool{
        let characteristic = self.characteristicWithUUID(characteristicUUID, forService: serviceUUID)
        if(characteristic == nil){
            return false
        }
        return self.writeValue(data, withCharacteristic: characteristic!)
    }
    
    func writeString(string:String,withCharacteristicUUID characteristicUUID:CBUUID,forService serviceUUID:CBUUID)->Bool{
        let characteristic = self.characteristicWithUUID(characteristicUUID, forService: serviceUUID)
        if(characteristic == nil){
            return false
        }
        
        if let data = string.dataUsingEncoding(NSUTF8StringEncoding) {
            return self.writeValue(data, withCharacteristicUUID: characteristicUUID, forService: serviceUUID)
        }
        return false
    }
    
    func writeInt(int:Int,withCharacteristicUUID characteristicUUID:CBUUID,forService serviceUUID:CBUUID)->Bool{
        return writeString("\(int)", withCharacteristicUUID: characteristicUUID, forService: serviceUUID)
    }
    
    
    //MARK:-
    //MARK:delegate
    //bluetooth delegate
    func centralManagerDidUpdateState(central: CBCentralManager) {
        let on = self.delegate != nil
        if(on){
            dispatch_async(dispatch_get_main_queue()){
                self.delegate?.centralManagerDidUpdateState(central)
            }
        }
    }
    
    //发现设备，过渡掉discoveredPeripherals中已经存在的
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        //更新发现时间
        let nowTime = NSDate().timeIntervalSince1970
        for i in 0..<discoveredPeripheralers.count{
            var peripheraler = discoveredPeripheralers[i]
            if(peripheral.identifier.isEqual(peripheraler.peripheral.identifier)){ //是否已经在列表当中
                peripheraler.lastDate = nowTime
                return
            }
        }
        log("发现设备:\(peripheral)")
        //增加
        let peripheraler = Peripheraler(lastDate: nowTime, peripheral: peripheral)
        weak var this = self
        synced{
            this!._discoveredPeripherals.append(peripheral)
            this!.discoveredPeripheralers.append(peripheraler)
        }
        let on = self.delegate != nil && self.delegate!.respondsToSelector(Selector("centralManager:didDiscoverPeripheral:advertisementData:RSSI:"))
        if(on){
            dispatch_async(dispatch_get_main_queue()){
                self.delegate!.centralManager!(central, didDiscoverPeripheral: peripheral, advertisementData: advertisementData, RSSI: RSSI)
            }
        }
    }
    
    //连接成功
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        self._peripheral = peripheral
        self._services = []
        self._characteristics = []
        self.updatingDatas = []
        self.stopScan()
        peripheral.discoverServices(nil)
        peripheral.delegate = self
        let on = self.delegate != nil && self.delegate!.respondsToSelector(Selector("centralManager:didConnectPeripheral:"))
        if(on){
            dispatch_async(dispatch_get_main_queue()){
                self.delegate!.centralManager!(central, didConnectPeripheral: peripheral)
            }
        }
    }
    
    //连接失败
    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        let on = self.delegate != nil && self.delegate!.respondsToSelector(Selector("centralManager:didFailToConnectPeripheral:error"))
        if(on){
            dispatch_async(dispatch_get_main_queue()){
                self.delegate!.centralManager!(central, didFailToConnectPeripheral: peripheral, error: error)
            }
        }else{
            if(error != nil){
                log("[ERROR]didFailToConnectPeripheral:\(error)")
                return
            }
            log("\(peripheral)连接失败")
        }
    }
    
    //断开连接
    func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        let on = self.delegate != nil && self.delegate!.respondsToSelector(Selector("centralManager:didDisconnectPeripheral:error"))
        if(on){
            dispatch_async(dispatch_get_main_queue()){
                self.delegate!.centralManager!(central, didDisconnectPeripheral: peripheral, error: error)
            }
        }else{
            if(error != nil){
                log("[ERROR]didDisconnectPeripheral:\(error)")
                return
            }
            log("\(peripheral)断开连接")
        }
        cleanup()
    }
    
    //发现服务
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        if(error != nil){
            log(error)
            return
        }
        let on = self.delegate != nil && self.delegate!.respondsToSelector(Selector("peripheral:didDiscoverServices:"))
        for item in peripheral.services!{
            let service = item 
            log("service---\(service)")
            self._services.append(service)
            if(!on){
                peripheral.discoverCharacteristics(nil, forService: service)
            }
        }
        if(on){
            dispatch_async(dispatch_get_main_queue()){
                self.delegate!.peripheral!(peripheral, didDiscoverServices: error)
            }
        }
    }
    
    //发现特征
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        if(error != nil){
            log(error)
            return
        }
        let on = self.delegate != nil && self.delegate!.respondsToSelector(Selector("peripheral:didDiscoverCharacteristicsForService:error:"))
        
        for item in service.characteristics!{
            let characteristic = item 
            log("characteristic---\(characteristic)")
            self._characteristics.append(characteristic)
            //MARK:订阅设置好的特征
            if(self.configurationNotifyingCharacteristics.filter{ characteristic.UUID.isEqual($0) }.count > 0 ){
                peripheral.setNotifyValue(true, forCharacteristic: characteristic)
            }
        }
        
        if(on){
            dispatch_async(dispatch_get_main_queue()){
                self.delegate!.peripheral!(peripheral, didDiscoverCharacteristicsForService: service, error:error)
            }
        }
    }
    
    //MARK:订阅数据回调
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        let on = self.delegate != nil && self.respondsToSelector(Selector("peripheral:didUpdateValueForCharacteristic:error:"))
        if(error != nil){
            log(error)
            if(on){
                dispatch_async(dispatch_get_main_queue()){
                    self.delegate?.ble(self, didUpdateValue: nil, forCharacteristic: characteristic, error: error)
                }
            }
            return
        }
        if(characteristic.value != nil){
            var data = characteristic.value!
            var string = NSString(data: data, encoding: NSUTF8StringEncoding)
            log(string)
            
             //接收多段数据
            if(self.updatingEOMFlag != nil){
                if(self.updatingEOMFlag == string){
                    var EOMEndFlag = false
                    for i in 0..<self.updatingDatas.count{ //数据结束
                        let updatingData = self.updatingDatas[i]
                        if(updatingData.characteristic.UUID.isEqual(characteristic.UUID)){
                            data = updatingData.data
                            string = NSString(data: data, encoding: NSUTF8StringEncoding)
                            self.updatingDatas.removeAtIndex(i) //删除缓存数据
                            EOMEndFlag = true
                            break
                        }
                    }
                    if(!EOMEndFlag){//数据开始
                        let updatingData = UpdatingDataer(characteristic: characteristic, data: NSMutableData())
                        self.updatingDatas!.append(updatingData)
                        return
                    }
                }else{
                    if var updatingData = (self.updatingDatas?.filter{ $0.characteristic.UUID.isEqual(characteristic.UUID) }) where updatingData.count == 1 && updatingData[0].data != nil { //数据中间
                        updatingData[0].data.appendData(data)
                        return
                    }
                }
            }
            //触发delegate与通知回调
            let stringData = StringData(string:string as? String,data:data)
            if(on){
                dispatch_async(dispatch_get_main_queue()){
                    self.delegate!.ble(self, didUpdateValue: stringData, forCharacteristic: characteristic,error:nil)
                }
            }
            dispatch_async(dispatch_get_main_queue()){
                NSNotificationCenter.defaultCenter().postNotificationName(characteristic.UUID.UUIDString, object:stringData)
            }
        }
    }
    
    //alertView delegate
    func alertView(alertView: UIAlertView, clickedButtonAtIndex buttonIndex: Int) {
        if(buttonIndex == 0 ) { //cancel
            return
        }
        if(alertView.tag == 1){ //open
             if #available(iOS 8.0, *) {
                 UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
             } else {
                 // Fallback on earlier versions
             }
        }else{ //authorized
            UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationLaunchOptionsBluetoothCentralsKey)!)
        }
    }
    
    //MARK:-
    //MARK:private
    func centralManagerDidUpdateState(){
        switch(self.centralMgr.state){
        case .PoweredOff:
            log("PoweredOff")
            dispatch_async(dispatch_get_main_queue()){
                let alertView = UIAlertView(title: "", message: localized("蓝牙未开启,请前往开启"), delegate: self, cancelButtonTitle: localized("返回"), otherButtonTitles: localized("去开启"))
                alertView.tag = 1
                alertView.show()
            }
        case .PoweredOn:
            log("PoweredOn")
        case .Unauthorized:
            log("Unauthorized")
            dispatch_async(dispatch_get_main_queue()){
                let alertView = UIAlertView(title: "", message: localized("蓝牙访问未授权,请前往设置中应用页面允许"), delegate: self, cancelButtonTitle: localized("返回"), otherButtonTitles: localized("去允许"))
                alertView.tag = 2
                alertView.show()
            }
        case .Resetting:
            log("Resetting")
        case .Unsupported:
            log("Unsupported")
            dispatch_async(dispatch_get_main_queue()){
                UIAlertView(title: nil, message: localized("不支持蓝牙"), delegate: nil, cancelButtonTitle: localized("确定")).show()
            }
        case .Unknown:
            log("Unknown")
        }
    }
    
    /**
    MARK:掉线处理
    */
    func lossScan(){
        weak var this  = self
        synced {
            var availablePeripheralers = Array<Peripheraler>()
            var availablePeripherals = Array<CBPeripheral>()
            let nowTime = NSDate().timeIntervalSince1970
            for(var i = 0 ; i < this!.discoveredPeripheralers.count ; i++ ){
                let peripheraler = this!.discoveredPeripheralers[i]
                if(peripheraler.lastDate + this!.lossTimeInterval < nowTime){
                    log("设备掉线:\(peripheraler.peripheral)")
                    if(this!.delegate != nil && this!.delegate!.respondsToSelector("ble:didLossPeripheral:")){
                        dispatch_async(dispatch_get_main_queue()){
                            this!.delegate?.ble(this!, didLossPeripheral: peripheraler.peripheral)
                        }
                    }
                    this!.discoveredPeripheralers.removeAtIndex(i)
                    this!._discoveredPeripherals.removeAtIndex(i)
                    i--;
                }
            }
        }
    }
    
    /**
    清理工作
    */
    private func cleanup(){
        if(self._peripheral == nil){
            return
        }
        for characteristic in self._characteristics{
            if(characteristic.isNotifying){
                self.peripheral?.setNotifyValue(false, forCharacteristic: characteristic)
            }
        }
        self._characteristics = nil
        self._services = nil
        self._peripheral = nil
        self.updatingDatas = nil
    }
    
}

class StringData{
    var string:String!
    var data:NSData!
    init(string:String!,data:NSData!){
        self.string = string
        self.data = data
    }
}

/**
*  BLE代理
*/
protocol BLEDelegate : CBCentralManagerDelegate,CBPeripheralDelegate{
    /**
    已发现的蓝牙丢失
    - parameter ble:
    - parameter peripheral:
    */
    func ble(ble: BLE!, didLossPeripheral peripheral: CBPeripheral!)
    
    
    /**
    订阅的数据回调
    - parameter ble:
    - parameter value: 接收到的数据,string与NSData
    - parameter characteristic: 来从哪个特征
    - parameter error: 有错误
    */
    func ble(ble: BLE!, didUpdateValue value:StringData!,forCharacteristic characteristic:CBCharacteristic,error:NSError!)
}
