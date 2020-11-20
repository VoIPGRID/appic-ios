//
//  SIPCallingViewController.swift
//  Copyright © 2016 VoIPGRID. All rights reserved.
//

import Contacts
import MediaPlayer
import PhoneLib
import CallKit
import AVKit

private var myContext = 0

@objc class SIPCallingViewController: UIViewController, KeypadViewControllerDelegate, SegueHandler {

    lazy var sip: Sip = {
        (UIApplication.shared.delegate as! AppDelegate).sip
    }()

    private lazy var phone: PhoneLib = {
        PhoneLib.shared
    }()

    // MARK: - Configuration
    enum SegueIdentifier : String {
        case unwindToVialerRootViewController = "UnwindToVialerRootViewControllerSegue"
        case showKeypad = "ShowKeypadSegue"
        case setupTransfer = "SetupTransferSegue"
    }
    
    fileprivate struct Config {
        struct Timing {
            static let waitingTimeAfterDismissing = 1.0
            static let connectDurationInterval = 1.0
        }
    }

    private var call: Call? {
        get { sip.call }
    }
    
    var presentsSecondCall = false

    private var user: SystemUser {
        get { SystemUser.current()}
    }

    private var dtmf: String = ""

    /**
        The remote number that has been called with the dialed dtmf
        appended.
    */
    private var displayedNumber: String {
        get {
            "\(call?.remoteNumber ?? "") \(dtmf)"
        }
    }

    private var displayedName = ""
    
    private lazy var dateComponentsFormatter: DateComponentsFormatter = {
        let dateComponentsFormatter = DateComponentsFormatter()
        dateComponentsFormatter.zeroFormattingBehavior = .pad
        dateComponentsFormatter.allowedUnits = [.minute, .second]
        return dateComponentsFormatter
    }()

    private var connectDurationTimer: Timer?
    
    // MARK: - Outlets
    @IBOutlet weak var muteButton: SipCallingButton!
    @IBOutlet weak var keypadButton: SipCallingButton!
    @IBOutlet weak var speakerButton: SipCallingButton!
    @IBOutlet weak var speakerLabel: UILabel!
    @IBOutlet weak var transferButton: SipCallingButton!
    @IBOutlet weak var holdButton: SipCallingButton!
    @IBOutlet weak var hangupButton: UIButton!
    @IBOutlet weak var numberLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var statusLabelTopConstraint: NSLayoutConstraint!
}

// MARK: - Lifecycle
extension SIPCallingViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        numberLabel?.text = ""
        nameLabel?.text = ""
        statusLabel?.text = ""
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleCallUpdate), name: NSNotification.Name(rawValue: "call-update"), object: nil)

        UIDevice.current.isProximityMonitoringEnabled = true
        
        if call?.simpleState == .finished {
            VialerLogInfo("Ending as state is ended.")
            handleCallEnded()
        }

        connectDurationTimer = Timer.scheduledTimer(timeInterval: Config.Timing.connectDurationInterval, target: self, selector: #selector(updateUI), userInfo: nil, repeats: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)

        connectDurationTimer?.invalidate()
        UIDevice.current.isProximityMonitoringEnabled = false
    }
}

// MARK: - Actions
extension SIPCallingViewController {

    func performCallAction(action: (_: UUID) -> CXCallAction) {
        guard let uuid = sip.call?.uuid else {
            VialerLogError("Unable to perform action on call as there is no active call")
            return
        }

        let controller = CXCallController()
        let action = action(uuid)

        controller.request(CXTransaction(action: action)) { error in
            if error != nil {
                VialerLogError("Failed to perform \(action.description) \(String(describing: error?.localizedDescription))")
                DispatchQueue.main.async {
                 self.dismiss(animated: true)
                }
            } else {
                VialerLogDebug("Performed \(action.description))")
            }
        }
    }

    @IBAction func muteButtonPressed(_ sender: SipCallingButton) {
        performCallAction { uuid in
            CXSetMutedCallAction(call: uuid, muted: !phone.isMicrophoneMuted)
        }
    }
    
    @IBAction func keypadButtonPressed(_ sender: SipCallingButton) {
//        dtmfWholeValue += dtmfSingleTimeValue
//        dtmfSingleTimeValue = ""
//        DispatchQueue.main.async {
//            self.performSegue(segueIdentifier: .showKeypad)
//        }
    }
    
    @IBAction func speakerButtonPressed(_ sender: SipCallingButton) {
        _ = phone.setSpeaker(phone.isSpeakerOn ? false : true)
        updateUI()
    }
    
    @IBAction func transferButtonPressed(_ sender: SipCallingButton) {
        guard let call = call, call.simpleState == .inProgress else { return }
        if call.session.state != .paused {
            performCallAction { uuid in
                CXSetHeldCallAction(call: uuid, onHold: true)
            }
        }
        
        DispatchQueue.main.async {
            self.performSegue(segueIdentifier: .setupTransfer)
        }
    }
    
    @IBAction func holdButtonPressed(_ sender: SipCallingButton) {
        performCallAction { uuid in
            CXSetHeldCallAction(call: uuid, onHold: !(call?.session.state == .paused))
        }
    }
    
    @IBAction func hangupButtonPressed(_ sender: UIButton) {
        performCallAction { uuid in
            CXEndCallAction(call: uuid)
        }
    }
}

// MARK: - Call setup
extension SIPCallingViewController {

    fileprivate func dismissView() {
        let waitingTimeAfterDismissing = Config.Timing.waitingTimeAfterDismissing
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(waitingTimeAfterDismissing * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) { [weak self] in
            if self?.sip.call?.direction == Direction.inbound {
                DispatchQueue.main.async {
                    VialerLogInfo("Unwinding to VialerRootViewController.")
                    self?.performSegue(segueIdentifier: .unwindToVialerRootViewController)
                }
            } else {
                UIDevice.current.isProximityMonitoringEnabled = false
                VialerLogInfo("Dismissing calling view.")
                self?.presentingViewController?.dismiss(animated: false, completion: nil)
            }
        }
    }
    
    func handleCallEnded() {
        VialerLogInfo("HandleCallEnded.")
        hangupButton?.isEnabled = false
        dismissView()
    }
    
    @objc func handleCallUpdate(_: NSNotification) {
        VialerLogInfo("HandleCallUpdate: State \(String(reflecting: call?.state)).")
//        guard call != nil else { //wip
//            handleCallEnded()
//            return
//        }
        updateUI()
    }
}

// MARK: - Handling UI updating
extension SIPCallingViewController {
    @objc func updateUI() {
        var presentedCall: Call?
        if presentsSecondCall {
            VialerLogInfo("Updating UI for second transfer call.")
            presentedCall = sip.secondTransferCall
        } else {
            VialerLogInfo("Updating UI for first call.")
            //presentedCall = sip.firstTransferCall ?? call //wip
            
            //wip to fix dismissed outgoing after transfer
            if sip.firstTransferCall != nil && sip.firstTransferCall?.simpleState != .finished {
                presentedCall = sip.firstTransferCall
            } else {
                presentedCall = call
            }
        }
        
        guard var call = presentedCall else {
            VialerLogInfo("Ending from UpdateUI as call object is nil.")
            handleCallEnded()//wip
            return
        }
                
        if call.simpleState == .finished {
            if presentsSecondCall {
                //will be handled in subclass
                return
            } else if sip.firstTransferCall == nil || sip.firstTransferCall?.simpleState == .finished { //wip
                VialerLogInfo("Ending from UpdateUI as state is \(String(reflecting: call.state)) and UUID is \(String(describing: call.uuid))")
                handleCallEnded()
                return
            } else {//wip if sip.firstTransferCall != nil {
                VialerLogInfo("Second call of the transfer ended, going to update UI for the first call screen.")
                call = sip.firstTransferCall!
                //sip.firstTransferCall = nil //wip
            }
        }
        
        VialerLogInfo("Updating UI for call.uuid: \(call.uuid).") //wip delete this line
        updateCalleeLabels(call: call)
        updateStatusLabel(call: call)
        updateButtons(call: call)
    }

    func updateButtons(call: Call) {
        //keypadButton?.isEnabled = call.session.state == .paused && call.session.state == .connected
        holdButton?.active = call.session.state == .paused
        muteButton?.active = phone.isMicrophoneMuted
        speakerButton?.active = phone.isSpeakerOn

        //        if callManager.audioController.hasBluetooth {
//            speakerButton?.buttonImage = "CallButtonBluetooth"
//            speakerLabel?.text = NSLocalizedString("audio", comment: "audio")
//        } else {
        speakerButton?.buttonImage = "CallButtonSpeaker"
        speakerLabel?.text = NSLocalizedString("speaker", comment: "speaker")
//        }

        switch call.simpleState {
        case .initializing, .ringing:
            holdButton?.isEnabled = false
            muteButton?.isEnabled = false
            transferButton?.isEnabled = false
            speakerButton?.isEnabled = true
            hangupButton?.isEnabled = true
        case .inProgress:
            holdButton?.isEnabled = true
            muteButton?.isEnabled = true
            transferButton?.isEnabled = true
            speakerButton?.isEnabled = true
            hangupButton?.isEnabled = true
        case .finished:
            holdButton?.isEnabled = false
            muteButton?.isEnabled = false
            transferButton?.isEnabled = false
            speakerButton?.isEnabled = false
            hangupButton?.isEnabled = false
        }
    }

    func updateStatusLabel(call: Call) {
        switch call.simpleState {
        case .initializing:
            statusLabel?.text = ""
        case .ringing:
            if call.isIncoming {
                statusLabel?.text = NSLocalizedString("Incoming call...", comment: "Statuslabel state text .Incoming")
            } else {
                statusLabel?.text = NSLocalizedString("Calling...", comment: "Statuslabel state text .Calling")
            }
        case .inProgress:
            //statusLabel?.text = NSLocalizedString("On hold", comment: "On hold")
            statusLabel?.text = "\(dateComponentsFormatter.string(from: TimeInterval(call.duration))!)"
        case .finished:
            statusLabel?.text = NSLocalizedString("Call ended", comment: "Statuslabel state text .Disconnected")
        }
    }

    func updateCalleeLabels(call: Call) {
        let name = call.displayName,
            number = displayedNumber

        if name?.isEmpty == false {
            nameLabel?.text = name
            numberLabel.text = number
        } else {
            setDisplayedName(phoneNumber: displayedNumber)
            nameLabel?.text = displayedName.isEmpty ? number : displayedName
            numberLabel.text = displayedName.isEmpty ? "" : number
        }
    }
    
    func setDisplayedName(phoneNumber: String) {
        let cleanedPhoneNumber = PhoneNumberUtils.cleanPhoneNumber(phoneNumber) ?? ""
        
        DispatchQueue.global(qos: DispatchQoS.QoSClass.userInteractive).async {
            PhoneNumberModel.getCallName(fromPhoneNumber: cleanedPhoneNumber, withCompletion: { (phoneNumberModel) in
                DispatchQueue.main.async { [weak self] in
                    self?.displayedName = phoneNumberModel.displayName ?? ""
                }
            })
        }
    }
}

// MARK: - Segues
extension SIPCallingViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segueIdentifier(segue: segue) {
        case .showKeypad:
            let keypadVC = segue.destination as! KeypadViewController
            keypadVC.call = call
            keypadVC.delegate = self
            keypadVC.phoneNumberLabelText = displayedNumber
        case .setupTransfer:
            let tabBarC = segue.destination as! UITabBarController
            let transferContactListNavC = tabBarC.viewControllers![0] as! UINavigationController
            let transferDialPadNavC = tabBarC.viewControllers![1] as! UINavigationController
            let setupCallTransferContactsVC = transferContactListNavC.viewControllers[0] as! SetupCallTransferContactsViewController
            let setupCallTransferDialPadVC = transferDialPadNavC.viewControllers[0] as! SetupCallTransferDialPadViewController
            setupCallTransferDialPadVC.firstCall = call
            setupCallTransferDialPadVC.firstCallPhoneNumberLabelText = displayedNumber
            
            setupCallTransferContactsVC.firstCall = call
            setupCallTransferContactsVC.firstCallPhoneNumberLabelText = displayedNumber
        case .unwindToVialerRootViewController:
            break
        }
    }
    
    @IBAction func unwindToFirstCallSegue(_ segue: UIStoryboardSegue) {}

    @IBAction func unwindToActiveCallSegue(_ segue: UIStoryboardSegue) {} // Seque used to make the second call the active one when the first call is ended during a transfer setup.
}


// MARK: - KeypadViewControllerDelegate
extension SIPCallingViewController {
    func dtmfSent(_ dtmfSent: String?) {
        self.dtmf += dtmfSent ?? ""
    }
}

extension SIPCallingViewController {
    private func bringupAudioDeviceSheet(availableAudioPorts:[AVAudioSessionPortDescription]) {
        let alertController = UIAlertController(title: nil,
                message: nil,
                preferredStyle: .actionSheet)
        for audioPort in availableAudioPorts {
            let action = UIAlertAction(title: audioPort.portName, style: .default) { (action) in
//                SoundManager.sharedInstance.setPreferredInput(audioPortDescription: audioPort.portDescription)
            }
//            if audioPort. {
//                action.setValue(true, forKey: "checked")
//            }
            var imageName: String?  = nil;
            switch audioPort.portType {
            case AVAudioSession.Port.builtInMic:
                imageName = "ic_36dp_phone"
            case AVAudioSession.Port.builtInSpeaker:
                imageName = "ic_36dp_speaker"
            case AVAudioSession.Port.headsetMic:
                imageName = "ic_36dp_headset"
            case AVAudioSession.Port.headphones:
                imageName = "ic_36dp_headset"
            case AVAudioSession.Port.bluetoothHFP:
                imageName = "ic_36dp_bluetooth"
            case AVAudioSession.Port.bluetoothA2DP:
                imageName = "ic_36dp_bluetooth"
            default: break
            }
            if imageName != nil {
                if let image = UIImage(named: imageName!) {
                    action.setValue(image.resized(to: CGSize(width: 30, height: 30)), forKey: "image")
                }
            }
            alertController.addAction(action)


        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (action) in
            // Do nothing
        }
        alertController.addAction(cancelAction)
        self.present(alertController, animated: true, completion: nil)
        // auto dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            alertController.dismiss(animated: true, completion: nil)
        }
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
