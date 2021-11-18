//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

final class SettingsAutoFillVC: UITableViewController {
    private let setupGuideURL_iOS =
        URL(string: "https://keepassium.com/apphelp/how-to-set-up-autofill-ios/")!
    private let setupGuideURL_macOS =
        URL(string: "https://keepassium.com/apphelp/how-to-set-up-autofill-macos/")!
    
    @IBOutlet private weak var setupInstructionsCell: UITableViewCell!
    @IBOutlet private weak var quickAutoFillCell: UITableViewCell!
    @IBOutlet private weak var perfectMatchCell: UITableViewCell!
    @IBOutlet private weak var copyTOTPCell: UITableViewCell!
    
    @IBOutlet private weak var quickTypeLabel: UILabel!
    @IBOutlet private weak var quickTypeSwitch: UISwitch!
    @IBOutlet private weak var copyTOTPSwitch: UISwitch!
    @IBOutlet private weak var perfectMatchSwitch: UISwitch!
    
    private var settingsNotifications: SettingsNotifications!
    private var isAutoFillEnabled = false

    
    override func viewDidLoad() {
        super.viewDidLoad()
        quickTypeLabel.text = LString.titleQuickAutoFill
        
        settingsNotifications = SettingsNotifications(observer: self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settingsNotifications.startObserving()
        refresh()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        settingsNotifications.stopObserving()
        super.viewWillDisappear(animated)
    }
    
    @objc
    private func appDidBecomeActive(_ notification: Notification) {
        refresh()
    }
    
    func refresh() {
        let settings = Settings.current
        quickTypeSwitch.isOn = settings.isQuickTypeEnabled
        copyTOTPSwitch.isOn = settings.isCopyTOTPOnAutoFill
        perfectMatchSwitch.isOn = settings.autoFillPerfectMatch

        isAutoFillEnabled = QuickTypeAutoFillStorage.isEnabled
        quickAutoFillCell.setEnabled(isAutoFillEnabled)
        perfectMatchCell.setEnabled(isAutoFillEnabled)
        copyTOTPCell.setEnabled(isAutoFillEnabled)
        if isAutoFillEnabled {
            setupInstructionsCell.textLabel?.text = LString.titleAutoFillSetupGuide
        } else {
            setupInstructionsCell.textLabel?.text = LString.actionActivateAutoFill
        }

        tableView.reloadData()
    }
    
    
    private func didPressSetupInstructions() {
        let url = ProcessInfo.isRunningOnMac ? setupGuideURL_macOS : setupGuideURL_iOS
        URLOpener(AppGroup.applicationShared).open(
            url: url,
            completionHandler: { success in
                if !success {
                    Diag.error("Failed to open help article")
                }
            }
        )
    }
    
    @IBAction func didToggleQuickType(_ sender: UISwitch) {
        Settings.current.isQuickTypeEnabled = quickTypeSwitch.isOn
        if !quickTypeSwitch.isOn {
            quickTypeLabel.flashColor(to: .destructiveTint, duration: 0.7)
            QuickTypeAutoFillStorage.removeAll()
        }
        refresh()
    }
    
    @IBAction func didToggleCopyTOTP(_ sender: UISwitch) {
        Settings.current.isCopyTOTPOnAutoFill = copyTOTPSwitch.isOn
        refresh()
    }
    
    @IBAction func didTogglePerfectMatch(_ sender: UISwitch) {
        Settings.current.autoFillPerfectMatch = perfectMatchSwitch.isOn
        refresh()
    }
}

extension SettingsAutoFillVC {
    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch section {
        case 0:
            if isAutoFillEnabled {
                return nil
            } else {
                return LString.howToActivateAutoFillDescription
            }
        case 1:
            return LString.quickAutoFillDescription
        default:
            return super.tableView(tableView, titleForFooterInSection: section)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cell = tableView.cellForRow(at: indexPath)
        switch cell {
        case setupInstructionsCell:
            didPressSetupInstructions()
        default:
            return
        }
    }
}

extension SettingsAutoFillVC: SettingsObserver {
    func settingsDidChange(key: Settings.Keys) {
        guard key != .recentUserActivityTimestamp else { return }
        refresh()
    }
}

extension LString {
    public static let actionActivateAutoFill = NSLocalizedString(
        "[Settings/AutoFill/Activate/action]",
        value: "Activate AutoFill",
        comment: "Action that opens system settings or instructions")
    public static let titleAutoFillSetupGuide = NSLocalizedString(
        "[Settings/AutoFill/Setup Guide/title]",
        value: "AutoFill Setup Guide",
        comment: "Title of a help article on how to activate AutoFill.")
    public static let howToActivateAutoFillDescription = NSLocalizedString(
        "[Settings/AutoFill/Activate/description]",
        value: "Before first use, you need to activate AutoFill in system settings.",
        comment: "Description for the AutoFill setup instructions")
    
    public static let titleQuickAutoFill = NSLocalizedString(
        "[QuickAutoFill/title]",
        value: "Quick AutoFill",
        comment: "Name of a feature that shows relevant entries directly next to the login/password forms.")
    public static let quickAutoFillDescription = NSLocalizedString(
        "[QuickAutoFill/description]",
        value: "Quick AutoFill shows relevant entries right next to the password field, without opening KeePassium.",
        comment: "Description of the Quick AutoFill feature.")
}
