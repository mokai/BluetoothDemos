//
//  ViewController.swift
//  G1SDebuger
//
//  Created by gongkai on 15/7/23.
//  Copyright (c) 2015年 gigaiot. All rights reserved.
//

import UIKit
import CoreBluetooth

//蓝牙数据发送大小
private let  NOTIFY_MTU = 20

class ViewController: UIViewController,CBPeripheralDelegate,UITextFieldDelegate {
    @IBOutlet weak var logConsloe: UITextView!
    @IBOutlet weak var data: UITextField!
    @IBOutlet weak var hexStringSwitch: UISwitch!
    @IBOutlet weak var newLineSwitch: UISwitch!
    
    @IBOutlet weak var listenerBtn: UIButton!
    let SERVICE_UUID = CBUUID(string:"FF12")
    let WRITE_UUID = CBUUID(string:"FF01")
    
    var ble:BLE!
    
    
    //MARK:-
    //MARK:ui event
    @IBAction func onListener(sender: UIButton) {
        if sender.titleForState(.Normal)=="stop" { //listening,so stop
            sender.setTitle("start", forState: UIControlState.Normal)
            self.ble.stopNotifying(ble.configurationNotifyingCharacteristics[0], forService: SERVICE_UUID)
        }else{//start
            sender.setTitle("stop", forState: UIControlState.Normal)
            self.ble.startNotifying(ble.configurationNotifyingCharacteristics[0], forService: SERVICE_UUID)
        }
    }
    
    @IBAction func onChangeHexOrString(sender: UISwitch) {
        newLineSwitch.enabled = sender.on
    }
    
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        onSendData(nil)
        self.view.endEditing(true)
        return true
    }
    
    @IBAction func onSendData(sender: UIButton?) {
        if(data.text == nil || data.text == ""){
            return
        }
        if hexStringSwitch.on { //string
            let string = newLineSwitch.on ? data.text! + "\r\n" : data.text
            let utf8Data = string!.dataUsingEncoding(NSUTF8StringEncoding)
            sendData(utf8Data!)
        }else{//hex
            let hexStrings = data.text!.componentsSeparatedByString(" ")
            let hexDatas = NSMutableData()
            for hexString in hexStrings{
                let hexData = Utils.stringToByte(hexString)
                if(hexData==nil){
                    UIAlertView(title: nil, message: "输入合法的十六进制", delegate: nil, cancelButtonTitle: "确定").show()
                    return
                }
                hexDatas.appendData(hexData)
            }
            sendData(hexDatas)
        }
        data.text = ""
    }
    
    //MARK:-
    //MARK:life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.ble = BLE.shareInstance()
        self.title = self.ble!.peripheral!.name
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("onUpdateValue:"), name: self.ble.configurationNotifyingCharacteristics[0].UUIDString, object: nil)
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        self.onListener(self.listenerBtn)
        NSNotificationCenter.defaultCenter().removeObserver(self)
        self.ble.cancel()
    }
    
    //MARK:-
    //MARK:bluetooth
    func onUpdateValue(notify:NSNotification){
        if let stringData = notify.object as? StringData{
            self.logConsloe.text = "\(self.logConsloe.text!)\n\(stringData.string!)"
            autoScroll()
        }
    }
    
    func sendData(data:NSData){
        self.ble.writeValue(data, withCharacteristicUUID: WRITE_UUID, forService: SERVICE_UUID)
    }
    
    //MARK:-
    //MARK:private
    private func autoScroll(){
        if(self.logConsloe.contentSize.height <= self.logConsloe.bounds.size.height){
            return
        }
        var pt = self.logConsloe.contentOffset
        pt.y = self.logConsloe.contentSize.height -  self.logConsloe.bounds.size.height 
        self.logConsloe.setContentOffset(pt, animated: true)
    }
    
}
