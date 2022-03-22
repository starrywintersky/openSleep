//
//  FlowViewController.swift
//  openSleep
//
//  Created by Adam Haar Horowitz on 11/25/18.
//  Copyright © 2018 Tomas Vega. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation

class FlowViewController:
  thinkOfRecordingsTableDelegate,
  DormioDelegate,
  UITextFieldDelegate {

  // Singletons
  var flowManager = FlowManager.shared
  var dormioManager = DormioManager.shared
  var dropDetector = DropDetector.shared
  var flexAnalyzer = FlexAnalyzer.shared

  var activeView : Int = -1
  
  var player : AVPlayer?

  @IBOutlet weak var backgroundView: UIView!
  @IBOutlet weak var connectButton: UIButton!
  @IBOutlet weak var dreamText: UITextField!
  @IBOutlet weak var userNameText: UITextField!
  @IBOutlet weak var continue1Button: UIButton!
  @IBOutlet weak var continueNameButton: UIButton!
  @IBOutlet weak var continue2Button: UIButton!
  @IBOutlet weak var continue3Button: UIButton!
  @IBOutlet weak var continueTimerBasedButton: UIButton!
  @IBOutlet weak var dreamButton: UIButton!
  @IBOutlet weak var dreamStageControl: UISegmentedControl!
  @IBOutlet weak var dreamLabel: UILabel!
  @IBOutlet weak var EDALabel: UILabel!
  @IBOutlet weak var HRLabel: UILabel!
  @IBOutlet weak var flexLabel: UILabel!
  
  @IBOutlet weak var numOnsetsControl: UISegmentedControl!
  @IBOutlet weak var sleepMessageLabel: UILabel!
  @IBOutlet weak var microphoneImage: UIImageView!
  @IBOutlet weak var dreamDetectorControl: UISegmentedControl!
  
  // Used in timer based mode
  @IBOutlet weak var timeUntilSleep: UITextField!
  @IBOutlet weak var phoneDropCalibrationTime: UIButton!
  @IBOutlet weak var phoneDropCalibrationStartStop: UIButton!
  
  // If a false positive is detected in timer based version, then the user can add x seconds additional time
  // TODO make timerFalsePostiveAdditionalTime configurable from experimental view
  @IBOutlet weak var timerFalsePositiveButton: UIButton!
  let timerFalsePositiveAdditionalTime = 60.0
  
  @IBOutlet weak var tableView: UITableView!
  
  var autoCompleteCharacterCount = 0
  var autoCompleteTimer = Timer()
  
  var playedAudio : Bool = false
  var currentStatus: String = "IDLE"
  var numOnsets = 0
  
  var detectSleepTimer = Timer()
  var detectSleepTimerPause : Bool = false
  
  var falsePositiveTimer = Timer()
  var falsePositiveTimerInterval = 0.5
  
  var edaBuffer = [UInt32]()
  var flexBuffer = [UInt32]()
  var hrBuffer = [UInt32]()
  var hrQueue = HeartQueue(windowTime: 60)
  var lastHrUpdate = Date().timeIntervalSince1970
  
  var isCalibrating = false
  var edaBufferCalibrate = [Int]()
  var flexBufferCalibrate = [Int]()
  var hrBufferCalibrate = [Int]()
  var meanEDA : Int = 0
  var meanHR : Int = 0
  var meanFlex : Int = 0
  var lastEDA : Int = 0
  var lastHR : Int = 0
  var lastFlex : Int = 0
  
  var firstOnset = true
  var lastOnset = Date().timeIntervalSince1970
  
  var isRecording = false
  var timer = Timer()
  
  var deviceUUID: String = ""
  var sessionDateTime: String = ""
  var getParams: [String: String] = [:]// parameters sent with get api calls to server

  var alarmTimer = Timer()
  
  var maxWaitOnsetTimer = Timer() // timer used for triggering an onset when maxWaitOnset time is exceeded
  
  var falsePositive: Bool = false
  
  var isPhoneDropCalibrating: Bool = false // whether the user is calibrating the time until sleep with drop detection
  var phoneDropCalibrationStartTime: Double = 0.0
  
  var sleepIsDetected: Bool = false
  
  var maxTimeToFirstOnsetTimer = Timer()
  
  var startTime: Double = 0

  func getDeviceUUID() {
    if UserDefaults.standard.object(forKey: "phoneUUID") == nil {
      UserDefaults.standard.set(UUID().uuidString, forKey: "phoneUUID")
    }
    deviceUUID = String(UserDefaults.standard.object(forKey: "phoneUUID") as! String)
    
    if let prefix = UserDefaults.standard.object(forKey: "phoneUUIDPrefix"){
      if (prefix as! String) != "" {
        deviceUUID = (prefix as! String) + "-" + deviceUUID
      }
    }
    
    getParams["deviceUUID"] = deviceUUID
  }
  
  func setUUIDPrefix(_ prefix: String) {
    UserDefaults.standard.set(prefix, forKey: "phoneUUIDPrefix")
    getDeviceUUID()
  }
  
  override func viewDidLoad() {
      super.viewDidLoad()
    
    if connectButton != nil {
      activeView = 0
      playVideo()
    }
    if let cb = continueNameButton {
      cb.isEnabled = false
      cb.setTitleColor(UIColor.lightGray, for: .disabled)
      activeView = 8
    }
    if let cb = continue1Button {
      cb.isEnabled = false
      cb.setTitleColor(UIColor.lightGray, for: .disabled)
      activeView = 1
    }
    if let cb = continue2Button {
      cb.isEnabled = false
      cb.setTitleColor(UIColor.lightGray, for: .disabled)
      activeView = 2
    }
    if let cb = continue3Button {
      cb.isEnabled = false
      cb.setTitleColor(UIColor.lightGray, for: .disabled)
      activeView = 3
    }
    if let cb = continueTimerBasedButton {
      cb.isEnabled = false
      cb.setTitleColor(UIColor.lightGray, for: .disabled)
      timeUntilSleep.addTarget(self, action: #selector(timeUntilSleepDidChange(_:)), for: .editingChanged)
      activeView = 7
    }
    if let dsc = dreamStageControl {
      flowManager.dreamStage = dsc.selectedSegmentIndex
      activeView = 4
    }
    if let noc = numOnsetsControl {
      flowManager.numOnsets = noc.selectedSegmentIndex + 1
      print("number of onsets is \(flowManager.numOnsets)")
      activeView = 5
    }
    if dreamButton != nil {
      dormioManager.delegate = self
      activeView = 6
      microphoneImage.isHidden = true
      HRLabel.text = ""
      EDALabel.text = ""
      flexLabel.text = ""
      timerFalsePositiveButton.isHidden = true
    }
    
    getDeviceUUID()
    
    if let tV = tableView {
      tableView.dataSource = self
      tableView.delegate = self
    }
      // Do any additional setup after loading the view.
  }
  
  private func playVideo() {
    guard let path = Bundle.main.path(forResource: "dormio", ofType:"m4v") else {
      debugPrint("dormio.m4v not found")
      return
    }
    player = AVPlayer(url: URL(fileURLWithPath: path))
    player?.volume = 0
    let playerLayer = AVPlayerLayer(player: player)
    playerLayer.frame = self.view.bounds
    self.view.backgroundColor = UIColor.clear;
    self.view.layer.insertSublayer(playerLayer, at: 0)
    player?.play()
    
    NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { _ in
      self.player?.seek(to: kCMTimeZero)
      self.player?.play()
    }
  }
  
  override func viewWillAppear(_ animated: Bool) {
    if let sml = sleepMessageLabel {
      sml.text = "\"You can fall asleep now,\nRemember to think of " + flowManager.dreamTitle! + "\""
    }
  }
  
  @IBAction func numOnsetsChanged(_ sender: Any) {
    flowManager.numOnsets = numOnsetsControl.selectedSegmentIndex + 1
  }
  
  @IBAction func dreamStageChanged(_ sender: Any) {
    flowManager.dreamStage = dreamStageControl.selectedSegmentIndex
  }
  
  @IBAction func timersPressed(_ sender: Any) {
    // TODO: set timer mode
    let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
    let newViewController = storyBoard.instantiateViewController(withIdentifier: "stepName") as! FlowViewController
    flowManager.isTimerBased = true
    self.navigationController?.pushViewController(newViewController, animated: true)
  }
  
  @IBAction func connectPressed(_ sender: Any) {
    dormioManager.delegate = self
    if dormioManager.isConnected {
      dormioManager.disconnect()
    } else {
      dormioManager.scanAndConnect()
      self.connectButton.setTitle("Scanning...", for: .normal)
      
    }
    flowManager.isTimerBased = false
  }
  
  @IBAction func recordWakupPressed(_ sender: UIButton) {
    continue2Button.isEnabled = true
    if !isRecording {
      recordingsManager.startRecording(mode: 1)
      sender.isSelected = true
    } else {
      recordingsManager.stopRecording()
      sender.isSelected = false
    }
    isRecording = !isRecording
  }
  
  @IBAction func recordSleepPressed(_ sender: UIButton) {
    continue3Button.isEnabled = true
    if !isRecording {
      recordingsManager.startRecordingMulti(mode: 0)
      sender.isSelected = true
    } else {
      recordingsManager.stopRecording()
      sender.isSelected = false
      tableView.reloadData()
    }
    isRecording = !isRecording
    
  }
  
  @IBAction func continue1Pressed(_ sender: Any) {
    flowManager.dreamTitle = self.dreamText.text
    let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
    let nextViewControllerID = (flowManager.isTimerBased) ? "timerStep" : "step3"
    let newViewController = storyBoard.instantiateViewController(withIdentifier: nextViewControllerID) as! FlowViewController
    self.navigationController?.pushViewController(newViewController, animated: true)
  }
  
  @IBAction func continueTimerBasedPressed(_ send: Any) {
    let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
    if let timeUntilSleepText = self.timeUntilSleep.text {
      flowManager.timeUntilSleep = Int(timeUntilSleepText)!
      print("FlowManager time until sleep = \(flowManager.timeUntilSleep)")
    }
    let newViewController = storyBoard.instantiateViewController(withIdentifier: "step3") as! FlowViewController
    self.navigationController?.pushViewController(newViewController, animated: true)
  }
  
  @IBAction func continuePressed(_ sender: UIButton) {
    if isRecording {
      recordingsManager.stopRecording()
    }
    print("Moving to step " + String(activeView + 2))
    let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
    let newViewController = storyBoard.instantiateViewController(withIdentifier: "step" + String(activeView + 2)) as! FlowViewController
    self.navigationController?.pushViewController(newViewController, animated: true)
  }
  
  @IBAction func continueNamePressed(_ sender: UIButton) {
    let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
    let nextViewControllerID = "step2"
    let newViewController = storyBoard.instantiateViewController(withIdentifier: nextViewControllerID) as! FlowViewController
    self.navigationController?.pushViewController(newViewController, animated: true)
  }
  
  /*
   Called when phone drop calibration is pressed
   Starts accelerometers and that listen for a drop
 */
  @IBAction func phoneDropCalibrationPressed(_ sender: UIButton) {
    print("Starting phone Drop Calibration!")
    
    if(!isPhoneDropCalibrating) {
      sender.setTitle("Stop",for: .normal)
      sender.setTitleColor(UIColor.red, for: .normal)
      isPhoneDropCalibrating = true
      phoneDropCalibrationStartTime = CFAbsoluteTimeGetCurrent()
      dropDetector.startAccelerometers()
      dropDetector.setCB(dropCB: dropCB)
    } else {
      sender.setTitle("Phone Drop Calibration Time:", for: .normal)
      sender.setTitleColor(UIColor.white, for: .normal)
      isPhoneDropCalibrating = false

      phoneDropCalibrationTime.setTitle(String(Int(CFAbsoluteTimeGetCurrent() - phoneDropCalibrationStartTime)) + " sec", for: .normal)
      dropDetector.stopAccelerometers()
    }
  }
  
  /*
    User will press this button when they are not asleep when timer mode dream catching has been triggered
 */
  @IBAction func timerFalsePositiveButtonPressed(_ sender: UIButton) {
    print("Adding \(timerFalsePositiveAdditionalTime)'s to the time delay")
    self.falsePositiveTimer.invalidate()
    self.sleepIsDetected = false
    self.timer.invalidate()
    self.maxWaitOnsetTimer.invalidate()
    self.recordingsManager.reset()
    self.playedAudio = false
    self.timerFalsePositiveButton.isHidden = true
    self.maxWaitOnsetTimer = Timer.scheduledTimer(withTimeInterval: timerFalsePositiveAdditionalTime, repeats: false, block: {
      t in
      self.sleepDetected(trigger: OnsetTrigger.TIMER)
    })
  }
  
  /*
   Callback function for when a drop is detected. Accelerometers are stopped and the time the drop occured is displayed on the screen
 */
  func dropCB() {
    phoneDropCalibrationTime.setTitle(String(Int(CFAbsoluteTimeGetCurrent() - phoneDropCalibrationStartTime)) + " sec", for: .normal)
    isPhoneDropCalibrating = false
    phoneDropCalibrationStartStop.setTitle("Phone Drop Calibration Time:", for: .normal)
    phoneDropCalibrationStartStop.setTitleColor(UIColor.white, for: .normal)
    dropDetector.stopAccelerometers()
  }
  
  /*
   The recorded phone drop calibration time can be pressed to fill the timeUntilSleep text field
 */
  @IBAction func phoneDropCalibrationTimePressed(_ sender: UIButton) {
    let t = phoneDropCalibrationTime.currentTitle!.components(separatedBy: " ")[0]
    if t != "None" {
      timeUntilSleep.text = t
      continueTimerBasedButton.isEnabled = true
    }
  }

  @IBAction func dreamPressed(_ sender: Any) {
    
    if (currentStatus == "IDLE") {
      dreamButton.setTitle("Cancel", for: .normal)
      dreamButton.setTitleColor(UIColor.red, for: .normal)
      dreamLabel.text = "Enjoy your dreams :)"
      currentStatus = "CALIBRATING"
      
      getDeviceUUID()
      self.numOnsets = 0
      recordingsManager.calibrateSilenceThreshold()
      
      if(!flowManager.isTimerBased) {
        let initParams = getInitParams()
        SleepAPI.apiGet(endpoint: "init", params: initParams, onSuccess: {json in
          self.sessionDateTime = json["datetime"] as! String
          self.getParams["datetime"] = self.sessionDateTime
          print("Sent these params: ", initParams,"getParams:", self.getParams)
        })
        self.detectSleepTimer.invalidate()
        
        self.calibrateStart()
        
        self.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false, block: {
          t in
          self.recordingsManager.startPlayingMulti(mode: 0, numOnset: self.numOnsets)
          
          self.timer = Timer.scheduledTimer(withTimeInterval: Double(UserDefaults.standard.object(forKey: "calibrationTime") as! Int) - 30, repeats: false, block: {
            t in
            self.currentStatus = "RUNNING"
            self.calibrateEnd()
            
            SleepAPI.apiGet(endpoint: "train", params: self.getParams)
            self.startTime = CFAbsoluteTimeGetCurrent()
            self.detectSleepTimerPause = false
            self.detectSleepTimer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(self.detectSleep(sender:)), userInfo: nil, repeats: true)
            
            self.maxTimeToFirstOnsetTimer = Timer.scheduledTimer(withTimeInterval: Double(UserDefaults.standard.object(forKey: "maxTimeToFirstOnset") as! Int) - 30, repeats: false, block: {
              t in
              print("Triggering first Onset after max time of", Double(UserDefaults.standard.object(forKey: "maxTimeToFirstOnset") as! Int))
              self.sleepDetected(trigger: .TIMER)
            })
            
          })
        })
      }
      else {
        // Start the timer for timer based version
        self.recordingsManager.startPlayingMulti(mode: 0, numOnset: self.numOnsets)
          print("Waiting for timeUntilSleep", self.flowManager.timeUntilSleep)
          self.timer = Timer.scheduledTimer(withTimeInterval: Double(self.flowManager.timeUntilSleep), repeats: false, block: {
            t in
              self.currentStatus = "RUNNING"
              self.sleepDetected(trigger: OnsetTrigger.TIMER)
            })
      }
      
    } else if (currentStatus == "CALIBRATING" || currentStatus == "RUNNING") {
      reset()
    }
  }
  
  /*
   Resets UI appearance, invalidates timers
 */
  func reset() {
    dreamButton.setTitle("Dream", for: .normal)
    dreamButton.setTitleColor(UIColor.blue, for: .normal)
    dreamLabel.text = "Relax for 30 seconds.\nWhen your bio-signals stabilize, press Dream"
    currentStatus = "IDLE"
    playedAudio = false
    falsePositive = false
    self.calibrateEnd()
    detectSleepTimerPause = true
    self.timer.invalidate()
    self.detectSleepTimer.invalidate()
    self.recordingsManager.reset()
    self.maxWaitOnsetTimer.invalidate()
    self.alarmTimer.invalidate()
    self.falsePositiveTimer.invalidate()
    self.maxTimeToFirstOnsetTimer.invalidate()
    
    self.timerFalsePositiveButton.isHidden = true
  }
  
  /*
   Hide keyboard/keypad when touching outside keyboard/keypad
 */
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    self.view.endEditing(true)
  }

  @objc func timeUntilSleepDidChange(_ textfield:UITextField) {
    print("Time until sleep text is: ",timeUntilSleep.text)
    if(flowManager.isTimerBased) {
      continueTimerBasedButton.isEnabled = timeUntilSleep.text != ""
    }
  }
  @objc func detectSleep(sender: Timer) {
    print("TIMERBASED?", flowManager.isTimerBased)
    let shouldTriggerFirstOnset = (CFAbsoluteTimeGetCurrent() - startTime) > Double(UserDefaults.standard.object(forKey:"minTimeToFirstOnset") as! Int)
    SleepAPI.apiGet(endpoint: "predict", params: getParams, onSuccess: { json in
      
      let score = Int((json["max_sleep"] as! NSNumber).floatValue.rounded())
      if (!self.detectSleepTimerPause && self.numOnsets == 0 && shouldTriggerFirstOnset) {
        if (self.dreamDetectorControl.selectedSegmentIndex == 0 && score >= (UserDefaults.standard.object(forKey: "deltaHBOSS") as! Int)) {
          DispatchQueue.main.async {
            self.sleepDetected(trigger: OnsetTrigger.HBOSS)
          }
        } else if (self.dreamDetectorControl.selectedSegmentIndex == 1 && abs(self.lastHR - self.meanHR) >= (UserDefaults.standard.object(forKey: "deltaHR") as! Int)) {
          DispatchQueue.main.async {
            self.sleepDetected(trigger: OnsetTrigger.HR)
          }
        } else if (self.dreamDetectorControl.selectedSegmentIndex == 2 && abs(self.lastEDA - self.meanEDA) >= (UserDefaults.standard.object(forKey: "deltaEDA") as! Int)) {
          DispatchQueue.main.async {
            self.sleepDetected(trigger: OnsetTrigger.EDA)
          }
        } else if (self.dreamDetectorControl.selectedSegmentIndex == 3 && abs(self.lastFlex - self.meanFlex) >= (UserDefaults.standard.object(forKey: "deltaFlex") as! Int)) {
          DispatchQueue.main.async {
            self.sleepDetected(trigger: OnsetTrigger.FLEX)
          }
        }
      }
    })
  }
  
  func sleepDetected(trigger: OnsetTrigger) {
    self.timer.invalidate()
    self.maxWaitOnsetTimer.invalidate()
    self.maxTimeToFirstOnsetTimer.invalidate()
    
    if(flowManager.isTimerBased) {
      self.timerFalsePositiveButton.isHidden = false
    }
    
    self.sleepIsDetected = true
    
    print("Sleep!")

    print("TRIGGER WAS", String(describing: trigger))
    
    var json: [String : Any] = ["trigger" : String(describing: trigger),
                                "currDateTime" : Date().timeIntervalSince1970,
                                "deviceUUID": deviceUUID,
                                "datetime": sessionDateTime]
    if (!self.playedAudio) {
      
      self.playedAudio = true
      self.detectSleepTimerPause = true
      // pause timer
      print("Waiting for Prompt time Delay:", flowManager.promptTimeDelay())
      
      
      if(!self.flowManager.isTimerBased) {
        self.falsePositiveTimer = Timer.scheduledTimer(withTimeInterval: falsePositiveTimerInterval, repeats: true, block: {
          t in
          
          if (self.flexAnalyzer.isFalsePositive()) {
            // Need to invalidate timers, delete any false-positve audio recordings, and transition back to trying to sleep
            print("False Positive Detected during sleepDetected!")
            self.falsePositiveTimer.invalidate()
            self.timer.invalidate()
            json["legitimate"] = false
            
            SleepAPI.apiPost(endpoint: "reportTrigger", json: json)
            
            self.recordingsManager.stopRecording()
            self.recordingsManager.deleteCurrentDream()
            self.recordingsManager.reset()
            self.transitionOnsetToSleep()

          }
        })
      }
      
      self.timer = Timer.scheduledTimer(withTimeInterval: flowManager.promptTimeDelay(), repeats: false, block: {
        t in
        
        self.recordingsManager.startPlaying(mode: 1)
        self.falsePositive = false
        
        self.recordingsManager.doOnPlayingEnd = {
          self.microphoneImage.isHidden = false
          
          self.recordingsManager.startRecordingDream(dreamTitle: self.flowManager.dreamTitle!, silenceCallback: {() in
            
            print("SILENCE DETECTED!")
            
            self.recordingsManager.stopRecording()
            self.falsePositiveTimer.invalidate()
            
            if(self.flowManager.isTimerBased) {
              self.timerFalsePositiveButton.isHidden = true
            }
            self.numOnsets += 1
            json["legitimate"] = true
            
            if(!self.flowManager.isTimerBased) {
              SleepAPI.apiPost(endpoint: "reportTrigger", json: json)
            }
            if (self.numOnsets < self.flowManager.numOnsets) {
              self.transitionOnsetToSleep()
            } else {
              self.alarmTimer = Timer.scheduledTimer(withTimeInterval: self.flowManager.waitTimeForAlarm, repeats: false, block: { (t) in
                self.wakeupAlarm()
              })
              }
            
          })
        }
        self.calibrateStart()
      })
    }
  }
  
  /*
    Called after onset is detected to setup next onset detection. After 30 seconds, will start playing the SLEEP audio.
   Also sets up a timer for Timer triggered onset
 */
  func transitionOnsetToSleep() {
    self.sleepIsDetected = false
    let timeToNextOnset = max(Double(UserDefaults.standard.object(forKey: "waitForOnsetTime") as! Int), 45.0)
    self.maxWaitOnsetTimer = Timer.scheduledTimer(withTimeInterval: timeToNextOnset, repeats: false, block: {
      t in
      self.sleepDetected(trigger: OnsetTrigger.TIMER)
    })
    
    self.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false, block: {
      t in
      self.recordingsManager.startPlayingMulti(mode: 0, numOnset: self.numOnsets)
      self.microphoneImage.isHidden = true
      self.playedAudio = false
      self.detectSleepTimerPause = false
      self.calibrateEnd()
      
    })
  }
  
  /*
   Alarm after all onsets detected
 */
  func wakeupAlarm() {
    print("All onsets detected, sounding alarm")
    self.recordingsManager.alarm()
    let alert = UIAlertController(title: "Wakeup!", message: "Dreamcatcher has caught \(self.numOnsets) dream(s).", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Continue (+1 onset(s))", style: .default, handler: {action in
      if(action.style == .default) {
        self.flowManager.numOnsets = self.flowManager.numOnsets + 1
        self.recordingsManager.stopAlarm()
        self.transitionOnsetToSleep()
      }
    }))
    alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: {action in
      if(action.style == .cancel) {
        print("Alarm Alert Dismissed")
        self.recordingsManager.stopAlarm()
        self.reset()
      }
    }))
    self.present(alert, animated: true, completion: nil)
  }
  
  func dormioConnected() {
    print("Connected")
    self.connectButton.setTitle("Disconnect Dormio", for: .normal)
    if activeView == 0 {
      let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
      let newViewController = storyBoard.instantiateViewController(withIdentifier: "stepName") as! FlowViewController
      self.navigationController?.pushViewController(newViewController, animated: true)
    }
  }
  // BUG: if disconnecting dormio while not on the starting screen (where the connectButton is displayed), navigating back to the starting screen
  // will not show the correct text "Connect Dormio"
  func dormioDisconnected() {
    if let cbutton = self.connectButton {
      cbutton.setTitle("Connect Dormio", for: .normal)
    }
  }
  
  func dormioData(hr: UInt32, eda: UInt32, flex: UInt32) {
    if activeView == 6 {
      flexLabel.text = String(flex);
      EDALabel.text = String(eda);
      hrQueue.put(hr: hr)
      if (Date().timeIntervalSince1970 - lastHrUpdate > 1) {
      lastHrUpdate = Date().timeIntervalSince1970
      HRLabel.text = String(hrQueue.bpm())
      }

      if (self.currentStatus != "IDLE") {
        sendData(flex: flex, hr: hr, eda: eda)
      }

      if (self.isCalibrating) {
        calibrateData(flex: flex, hr: hrQueue.bpm(), eda: eda)
      }
      
      if(self.sleepIsDetected && !flowManager.isTimerBased) {
        flexAnalyzer.detectFalsePositive(flex: flex)
      }
    }
  }
  
  func sendData(flex: UInt32, hr: UInt32, eda: UInt32) {
    flexBuffer.append(flex)
    edaBuffer.append(eda)
    hrBuffer.append(hr)
    
    if (flexBuffer.count >= 30) {
      // send buffer to server
      let json: [String : Any] = ["flex" : flexBuffer,
                                  "eda" : edaBuffer,
                                  "ecg" : hrBuffer,
                                  "deviceUUID": getParams["deviceUUID"],
                                  "datetime": getParams["datetime"]
                                  ]
      SleepAPI.apiPost(endpoint: "upload", json: json)
      
      lastEDA = Int(Float(edaBuffer.reduce(0, +)) / Float(edaBuffer.count))
      lastFlex = Int(Float(flexBuffer.reduce(0, +)) / Float(flexBuffer.count))
      lastHR = hrQueue.bpm()
      
      flexBuffer.removeAll()
      edaBuffer.removeAll()
      hrBuffer.removeAll()
    }
  }
  
  func calibrateData(flex: UInt32, hr: Int, eda: UInt32) {
    flexBufferCalibrate.append(Int(flex))
    edaBufferCalibrate.append(Int(eda))
    hrBufferCalibrate.append(Int(hr))
  }
  
  func calibrateStart() {
    flexBufferCalibrate.removeAll()
    edaBufferCalibrate.removeAll()
    hrBufferCalibrate.removeAll()
    isCalibrating = true
  }
  
  func calibrateEnd() {
    if hrBufferCalibrate.count > 0 {
      meanHR = Int(Float(hrBufferCalibrate.reduce(0, +)) / Float(hrBufferCalibrate.count))
      meanEDA = Int(Float(edaBufferCalibrate.reduce(0, +)) / Float(edaBufferCalibrate.count))
      meanFlex = Int(Float(flexBufferCalibrate.reduce(0, +)) / Float(flexBufferCalibrate.count))
      isCalibrating = false
    }
  }
  
  func setRecordingTimes() {
    let minTime = UserDefaults.standard.object(forKey: "minRecordingTime")
    let maxTime = UserDefaults.standard.object(forKey: "maxRecordingTime")
    recordingsManager.configureRecordingTime(min: minTime, max: maxTime)
  }
  
  func setFalsePositiveFlexParams() {
    let falsePosFlexOpen = UserDefaults.standard.object(forKey: "falsePosFlexOpen")
    let falsePosFlexClosed = UserDefaults.standard.object(forKey: "falsePosFlexClosed")
    flexAnalyzer.configureFalsePositiveParams(open: falsePosFlexOpen, closed: falsePosFlexClosed)
  }
  
  func getInitParams()-> [String: String] {
    
    var ret = getParams
    ret["promptLatency"] = String(flowManager.promptTimeDelay())
    ret["numberOfSleeps"] = String(flowManager.numOnsets)
    
    let defaults = UserDefaults.standard
      
      if let uuidPrefix = defaults.object(forKey: "phoneUUIDPrefix") {
        ret["uuidPrefix"] = String(uuidPrefix as! String)
      }
      if let calibrationTime = defaults.object(forKey: "calibrationTime") {
        ret["calibrationTime"] = String(calibrationTime as! Int)
      }
      if let maxTimeBetweenSleeps = defaults.object(forKey: "waitForOnsetTime")  {
        ret["maxTimeBetweenSleeps"] = String(maxTimeBetweenSleeps as! Int)
      }
      if let falsePositiveFlexOpen = defaults.object(forKey: "falsePosFlexOpen") {
        ret["falsePositiveFlexOpen"] = String(falsePositiveFlexOpen as! Int)
      }
      if let falsePositiveFlexClosed = defaults.object(forKey: "falsePosFlexClosed") {
        ret["falsePositiveFlexClosed"] = String(falsePositiveFlexClosed as! Int)
      }
      if let minRecordingTime = defaults.object(forKey: "minRecordingTime") {
        ret["minRecordingTime"] = String(minRecordingTime as! Int)
      }
      if let maxRecordingTime = defaults.object(forKey: "maxRecordingTime") {
        ret["maxRecordingTime"] = String(maxRecordingTime as! Int)
      }
      if let deltaHBOSS = defaults.object(forKey: "deltaHBOSS") {
        ret["deltaHBOSS"] = String(deltaHBOSS as! Int)
      }
      if let deltaEDA = defaults.object(forKey: "deltaEDA") {
        ret["deltaEDA"] = String(deltaEDA as! Int)
      }
      if let deltaHR = defaults.object(forKey: "deltaHR") {
        ret["deltaHR"] = String(deltaHR as! Int)
      }
      if let deltaFlex = defaults.object(forKey: "deltaFlex") {
        ret["deltaFlex"] = String(deltaFlex as! Int)
      }
      if let maxTimeToFirstOnset = defaults.object(forKey: "maxTimeToFirstOnset") {
        ret["maxTimeToFirstOnset"] = String(maxTimeToFirstOnset as! Int)
      }
      if let minTimeToFirstOnset = defaults.object(forKey: "minTimeToFirstOnset") {
        ret["minTimeToFirstOnset"] = String(minTimeToFirstOnset as! Int)
      }
      
    return ret
  }
  
  @IBAction func onUserNameTextChanged(_ sender: UITextField){
    guard let userName = userNameText.text else {
      return
    }
    userNameText.text = flowManager.sanitizeUserName(userName: userName)
    
    let validUserName = (userNameText.text != "")
    
    continueNameButton.isEnabled = validUserName
    
    if(validUserName) {
      setUUIDPrefix(userNameText.text!)
    }
  }
  
  // AUTOCOMPLETE
  func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool { //1

    continue1Button.isEnabled = true
    
    var subString = (textField.text!.capitalized as NSString).replacingCharacters(in: range, with: string) // 2
    subString = formatSubstring(subString: subString)
    
    if subString.count == 0 { // 3 when a user clears the textField
      resetValues()
    } else {
      searchAutocompleteEntriesWIthSubstring(substring: subString) //4
    }
    return true
  }
  
  func formatSubstring(subString: String) -> String {
    let formatted = String(subString.dropLast(autoCompleteCharacterCount)).lowercased().capitalized //5
    return formatted
  }
  
  func resetValues() {
    autoCompleteCharacterCount = 0
    dreamText.text = ""
    continue1Button.isEnabled = false
  }
  
  func searchAutocompleteEntriesWIthSubstring(substring: String) {
    let userQuery = substring
    let suggestions = getAutocompleteSuggestions(userText: substring) //1
    
    if suggestions.count > 0 {
      autoCompleteTimer = .scheduledTimer(withTimeInterval: 0.01, repeats: false, block: { (timer) in //2
        let autocompleteResult = self.formatAutocompleteResult(substring: substring, possibleMatches: suggestions) // 3
        self.putColourFormattedTextInTextField(autocompleteResult: autocompleteResult, userQuery : userQuery) //4
        self.moveCaretToEndOfUserQueryPosition(userQuery: userQuery) //5
      })
    } else {
      autoCompleteTimer = .scheduledTimer(withTimeInterval: 0.01, repeats: false, block: { (timer) in //7
        self.dreamText.text = substring
      })
      autoCompleteCharacterCount = 0
    }
  }
  
  func getAutocompleteSuggestions(userText: String) -> [String]{
    var possibleMatches: [String] = []
    for item in recordingsManager.getCategories() { //2
      let myString:NSString! = item as NSString
      let substringRange :NSRange! = myString.range(of: userText)
      
      if (substringRange.location == 0)
      {
        possibleMatches.append(item)
      }
    }
    return possibleMatches
  }
  
  func putColourFormattedTextInTextField(autocompleteResult: String, userQuery : String) {
    let colouredString: NSMutableAttributedString = NSMutableAttributedString(string: userQuery + autocompleteResult)
    colouredString.addAttribute(NSAttributedStringKey.foregroundColor, value: UIColor.gray, range: NSRange(location: userQuery.count,length:autocompleteResult.count))
    self.dreamText.attributedText = colouredString
  }
  func moveCaretToEndOfUserQueryPosition(userQuery : String) {
    if let newPosition = self.dreamText.position(from: self.dreamText.beginningOfDocument, offset: userQuery.count) {
      self.dreamText.selectedTextRange = self.dreamText.textRange(from: newPosition, to: newPosition)
    }
    let selectedRange: UITextRange? = dreamText.selectedTextRange
    dreamText.offset(from: dreamText.beginningOfDocument, to: (selectedRange?.start)!)
  }
  func formatAutocompleteResult(substring: String, possibleMatches: [String]) -> String {
    var autoCompleteResult = possibleMatches[0]
    autoCompleteResult.removeSubrange(autoCompleteResult.startIndex..<autoCompleteResult.index(autoCompleteResult.startIndex, offsetBy: substring.count))
    autoCompleteCharacterCount = autoCompleteResult.count
    return autoCompleteResult
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "rememberToThinkOfCell", for: indexPath) as! ThinkOfRecordingCell
    cell.label?.text = "Remember To Think Of (\(indexPath.row))"
    return cell
  }
  
  @IBAction func startEditing(_ sender: Any) {
    tableView.isEditing = !tableView.isEditing
    let b = sender as! UIBarButtonItem
    b.title = (b.title == "Edit") ? "Done" : "Edit"
  }
}
