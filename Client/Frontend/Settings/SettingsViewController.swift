/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import BraveShared
import Static
import SwiftKeychainWrapper
import LocalAuthentication
import SwiftyJSON
import Data
import WebKit
import BraveRewards
import BraveRewardsUI

extension TabBarVisibility: RepresentableOptionType {
    public var displayString: String {
        switch self {
        case .always: return Strings.alwaysShow
        case .landscapeOnly: return Strings.showInLandscapeOnly
        case .never: return Strings.neverShow
        }
    }
}

extension DataSource {
    /// Get the index path of a Row to modify it
    ///
    /// Since they are structs we cannot obtain references to them to alter them, we must directly access them
    /// from `sections[x].rows[y]`
    func indexPath(rowUUID: String, sectionUUID: String) -> IndexPath? {
        guard let section = sections.firstIndex(where: { $0.uuid == sectionUUID }),
            let row = sections[section].rows.firstIndex(where: { $0.uuid == rowUUID }) else {
                return nil
        }
        return IndexPath(row: row, section: section)
    }
    
    func reloadCell(row: Row, section: Section, displayText: String) {
        if let indexPath = indexPath(rowUUID: row.uuid, sectionUUID: section.uuid) {
            sections[indexPath.section].rows[indexPath.row].detailText = displayText
        }
    }
}

protocol SettingsDelegate: class {
    func settingsOpenURLInNewTab(_ url: URL)
    func settingsOpenURLs(_ urls: [URL])
    func settingsDidFinish(_ settingsViewController: SettingsViewController)
    func settingsOpenRewardsSettings(_ settingsViewController: SettingsViewController)
}

class SettingsViewController: TableViewController {
    weak var settingsDelegate: SettingsDelegate?
    
    private let profile: Profile
    private let tabManager: TabManager
    private let rewards: BraveRewards?
    
    init(profile: Profile, tabManager: TabManager, rewards: BraveRewards? = nil) {
        self.profile = profile
        self.tabManager = tabManager
        self.rewards = rewards
        
        super.init(style: .grouped)
    }
    
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = Strings.settings
        tableView.accessibilityIdentifier = "SettingsViewController.tableView"
        dataSource.sections = sections
    }
    
    override func viewWillAppear(_ animated: Bool) {
        applyTheme(theme)
        
        guard let vpnRow = vpnRow else { return }
        // This is a dynamic cell that must be updated based on vpn status.
        if let indexPath = dataSource.indexPath(rowUUID: vpnRow.uuid, sectionUUID: otherSettingsSection.uuid) {
            dataSource.sections[indexPath.section].rows.remove(at: indexPath.row)
            dataSource.sections[indexPath.section].rows.append(vpnSettingsRow())
        }
    }
    
    private func displayRewardsDebugMenu() {
        guard let rewards = rewards else { return }
        let settings = QASettingsViewController(rewards: rewards)
        navigationController?.pushViewController(settings, animated: true)
    }
    
    private var theme: Theme {
        Theme.of(tabManager.selectedTab)
    }
    
    private var sections: [Section] {
        var list = [Section]()
        
        let shouldShowVPNSection = { () -> Bool in
            if !VPNProductInfo.isComplete || Preferences.VPN.vpnSettingHeaderWasDismissed.value {
                return false
            }
            
            switch BraveVPN.vpnState {
            case .notPurchased, .expired, .purchased:
                return true
            case .installed:
                return false
            }
        }()
        
        if shouldShowVPNSection {
            list.append(enableBraveVPNSection)
        }
        list.append(generalSection)
        list.append(displaySection)
        list.append(otherSettingsSection)
        list.append(contentsOf: [privacySection,
                                 securitySection,
                                 shieldsSection,
                                 supportSection,
                                 aboutSection])
        
        if let debugSection = debugSection {
            list.append(debugSection)
        }

        return list
    }
    
    // MARK: - Sections
    
    private lazy var enableBraveVPNSection: Section = {
        let header = EnableVPNSettingHeader()
        header.enableVPNTapped = { [weak self] in
            self?.enableVPNTapped()
        }
        
        header.dismissHeaderTapped = { [weak self] in
            self?.dismissVPNHeaderTapped()
        }
        
        let calculatedSize = header.systemLayoutSizeFitting(
            CGSize(width: navigationController?.navigationBar.frame.width ?? 0, height: 300),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        
        header.bounds = CGRect(size: calculatedSize)
        
        return Section(header: .view(header))
    }()
    
    private func enableVPNTapped() {
        let state = BraveVPN.vpnState
        
        switch state {
        case .notPurchased, .purchased, .expired:
            guard let vc = state.enableVPNDestinationVC else { return }
            navigationController?.pushViewController(vc, animated: true)
        case .installed:
            BraveVPN.reconnect()
            dismiss(animated: true)
        }
    }
    
    private func dismissVPNHeaderTapped() {
        if dataSource.sections.isEmpty { return }
        dataSource.sections[0] = Section()
        Preferences.VPN.vpnSettingHeaderWasDismissed.value = true
    }
    
    private lazy var generalSection: Section = {
        var general = Section(
            header: .title(Strings.settingsGeneralSectionTitle),
            rows: [
                Row(text: Strings.searchEngines, selection: {
                    let viewController = SearchSettingsTableViewController()
                    viewController.model = self.profile.searchEngines
                    viewController.profile = self.profile
                    self.navigationController?.pushViewController(viewController, animated: true)
                }, accessory: .disclosureIndicator, cellClass: MultilineValue1Cell.self),
                .boolRow(title: Strings.saveLogins, option: Preferences.General.saveLogins),
                .boolRow(title: Strings.blockPopups, option: Preferences.General.blockPopups)
            ]
        )
        
        if #available(iOS 13.0, *), UIDevice.isIpad {
            general.rows.append(.boolRow(title: Strings.alwaysRequestDesktopSite,
            option: Preferences.General.alwaysRequestDesktopSite))
        }
        
        return general
    }()
    
    private lazy var displaySection: Section = {
        var display = Section(
            header: .title(Strings.displaySettingsSection),
            rows: []
        )
        
        let themeSubtitle = Theme.DefaultTheme(rawValue: Preferences.General.themeNormalMode.value)?.displayString
        var row = Row(text: Strings.themesDisplayBrightness, detailText: themeSubtitle, accessory: .disclosureIndicator, cellClass: MultilineSubtitleCell.self)
        row.selection = { [unowned self] in
            let optionsViewController = OptionSelectionViewController<Theme.DefaultTheme>(
                options: Theme.DefaultTheme.normalThemesOptions,
                selectedOption: Theme.DefaultTheme(rawValue: Preferences.General.themeNormalMode.value),
                optionChanged: { [unowned self] _, option in
                    Preferences.General.themeNormalMode.value = option.rawValue
                    self.dataSource.reloadCell(row: row, section: display, displayText: option.displayString)
                    self.applyTheme(self.theme)
                }
            )
            optionsViewController.headerText = Strings.themesDisplayBrightness
            optionsViewController.footerText = Strings.themesDisplayBrightnessFooter
            self.navigationController?.pushViewController(optionsViewController, animated: true)
        }
        display.rows.append(row)
        
        display.rows.append(Row(text: Strings.NTP.settingsTitle,
            selection: { [unowned self] in
                self.navigationController?.pushViewController(NTPTableViewController(), animated: true)
            },
            accessory: .disclosureIndicator,
            cellClass: MultilineValue1Cell.self
        ))
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            display.rows.append(
                Row(text: Strings.showTabsBar, accessory: .switchToggle(value: Preferences.General.tabBarVisibility.value == TabBarVisibility.always.rawValue, { Preferences.General.tabBarVisibility.value = $0 ? TabBarVisibility.always.rawValue : TabBarVisibility.never.rawValue }), cellClass: MultilineValue1Cell.self)
            )
        } else {
            var row = Row(text: Strings.showTabsBar, detailText: TabBarVisibility(rawValue: Preferences.General.tabBarVisibility.value)?.displayString, accessory: .disclosureIndicator, cellClass: MultilineSubtitleCell.self)
            row.selection = { [unowned self] in
                // Show options for tab bar visibility
                let optionsViewController = OptionSelectionViewController<TabBarVisibility>(
                    options: TabBarVisibility.allCases,
                    selectedOption: TabBarVisibility(rawValue: Preferences.General.tabBarVisibility.value),
                    optionChanged: { _, option in
                        Preferences.General.tabBarVisibility.value = option.rawValue
                        self.dataSource.reloadCell(row: row, section: display, displayText: option.displayString)
                    }
                )
                optionsViewController.headerText = Strings.showTabsBar
                self.navigationController?.pushViewController(optionsViewController, animated: true)
            }
            display.rows.append(row)
        }
        
        display.rows.append(
            .boolRow(title: Strings.showBookmarkButtonInTopToolbar,
                     option: Preferences.General.showBookmarkToolbarShortcut)
        )
        
        return display
    }()
    
    private lazy var otherSettingsSection: Section = {
        // BRAVE TODO: Change it once we finalize our decision how to name the section.(#385)
        var section = Section(header: .title(Strings.otherSettingsSection))
        if BraveRewards.isAvailable {
            if let rewards = rewards {
                section.rows += [
                    Row(text: Strings.braveRewardsTitle, selection: { [unowned self] in
                        let rewardsVC = BraveRewardsSettingsViewController(rewards)
                        rewardsVC.tappedShowRewardsSettings = { [unowned self] in
                            self.settingsDelegate?.settingsOpenRewardsSettings(self)
                        }
                        self.navigationController?.pushViewController(rewardsVC, animated: true)
                        }, accessory: .disclosureIndicator),
                ]
            }
        }
        
        vpnRow = vpnSettingsRow()
        
        if let row = vpnRow {
            section.rows.append(row)
        }
        
        return section
    }()
    
    private var vpnRow: Row?
    
    private func vpnSettingsRow() -> Row {
        
        let (text, color) = { () -> (String, UIColor) in
            switch BraveVPN.vpnState {
            case .notPurchased, .purchased:
                return ("", UIColor.black)
            case .installed(let enabled):
                if enabled {
                    return (Strings.VPN.settingsVPNEnabled, #colorLiteral(red: 0.1607843137, green: 0.737254902, blue: 0.5647058824, alpha: 1))
                } else {
                    return (Strings.VPN.settingsVPNDisabled, BraveUX.red)
                }
            case .expired:
                return (Strings.VPN.settingsVPNExpired, BraveUX.red)
            }
        }()
        
        return Row(text: Strings.VPN.vpnName, detailText: text, selection: { [unowned self] in
            
            let vc = { () -> UIViewController? in
                switch BraveVPN.vpnState {
                case .notPurchased, .purchased, .expired:
                    return BraveVPN.vpnState.enableVPNDestinationVC
                case .installed:
                    let vc = BraveVPNSettingsViewController()
                    vc.faqButtonTapped = { [weak self] in
                        self?.settingsDelegate?.settingsOpenURLInNewTab(BraveUX.braveVPNFaqURL)
                        self?.dismiss(animated: true)
                    }
                    return vc
                }
            }()
            
            guard let vcToShow = vc else { return }
            self.navigationController?.pushViewController(vcToShow, animated: true)
            }, accessory: .disclosureIndicator,
               cellClass: ColoredDetailCell.self, context: [ColoredDetailCell.colorKey: color], uuid: "vpnrow")
    }
    
    private lazy var privacySection: Section = {
        var privacy = Section(
            header: .title(Strings.privacy)
        )
        privacy.rows = [
            Row(text: Strings.clearPrivateData,
                selection: { [unowned self] in
                    // Show Clear private data screen
                    let clearPrivateData = ClearPrivateDataTableViewController().then {
                        $0.profile = self.profile
                        $0.tabManager = self.tabManager
                    }
                    self.navigationController?.pushViewController(clearPrivateData, animated: true)
                },
                accessory: .disclosureIndicator,
                cellClass: MultilineValue1Cell.self
            ),
            .boolRow(title: Strings.blockAllCookies, option: Preferences.Privacy.blockAllCookies, onValueChange: { [unowned self] in
                func toggleCookieSetting(with status: Bool) {
                    // Lock/Unlock Cookie Folder
                    let completionBlock: (Bool) -> Void = { _ in
                        let success = FileManager.default.setFolderAccess([
                            (.cookie, status),
                            (.webSiteData, status)
                            ])
                        if success {
                            Preferences.Privacy.blockAllCookies.value = status
                        } else {
                            //Revert the changes. Not handling success here to avoid a loop.
                            FileManager.default.setFolderAccess([
                                (.cookie, false),
                                (.webSiteData, false)
                                ])
                            self.toggleSwitch(on: false, section: self.privacySection, rowUUID: Preferences.Privacy.blockAllCookies.key)
                            
                            // TODO: Throw Alert to user to try again?
                            let alert = UIAlertController(title: nil, message: Strings.blockAllCookiesFailedAlertMsg, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: Strings.OKString, style: .default))
                            self.present(alert, animated: true)
                        }
                    }
                    // Save cookie to disk before purge for unblock load.
                    status ? HTTPCookie.saveToDisk(completion: completionBlock) : completionBlock(true)
                }
                if $0 {
                    let status = $0
                    // THROW ALERT to inform user of the setting
                    let alert = UIAlertController(title: Strings.blockAllCookiesAlertTitle, message: Strings.blockAllCookiesAlertInfo, preferredStyle: .alert)
                    let okAction = UIAlertAction(title: Strings.blockAllCookiesAction, style: .destructive, handler: { (action) in
                        toggleCookieSetting(with: status)
                    })
                    alert.addAction(okAction)
                    
                    let cancelAction = UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: { (action) in
                        self.toggleSwitch(on: false, section: self.privacySection, rowUUID: Preferences.Privacy.blockAllCookies.key)
                    })
                    alert.addAction(cancelAction)
                    self.present(alert, animated: true)
                } else {
                    toggleCookieSetting(with: $0)
                }
            })
        ]
        privacy.rows.append(
            .boolRow(
                title: Strings.privateBrowsingOnly,
                option: Preferences.Privacy.privateBrowsingOnly,
                onValueChange: { value in
                    
                    let applyThemeBlock = { [weak self] in
                        guard let self = self else { return }
                        // Need to flush the table, hacky, but works consistenly and well
                        let superView = self.tableView.superview
                        self.tableView.removeFromSuperview()
                        DispatchQueue.main.async {
                            // Let shield toggle change propagate, otherwise theme may not be set properly
                            superView?.addSubview(self.tableView)
                            self.applyTheme(self.theme)
                        }
                    }

                    if value {
                        let alert = UIAlertController(title: Strings.privateBrowsingOnly, message: Strings.privateBrowsingOnlyWarning, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: { _ in
                            DispatchQueue.main.async {
                                self.toggleSwitch(on: false, section: self.privacySection, rowUUID: Preferences.Privacy.privateBrowsingOnly.key)
                            }
                        }))

                        alert.addAction(UIAlertAction(title: Strings.OKString, style: .default, handler: { _ in
                            let spinner = SpinnerView().then {
                                $0.present(on: self.view)
                            }
                            
                            Preferences.Privacy.privateBrowsingOnly.value = value
                            
                            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.1) {
                                let clearables: [Clearable] = [CookiesAndCacheClearable()]
                                ClearPrivateDataTableViewController.clearPrivateData(clearables).uponQueue(.main) { [weak self] in
                                    guard let self = self else { return }
                                    
                                    //First remove all tabs so that only a blank tab exists.
                                    self.tabManager.removeAll()
                                    
                                    //Reset tab configurations and delete all webviews..
                                    self.tabManager.reset()
                                    
                                    //Restore all existing tabs by removing the blank tabs and recreating new ones..
                                    self.tabManager.removeAll()
                                    
                                    spinner.dismiss()
                                    applyThemeBlock()
                                }
                            }
                        }))

                        self.present(alert, animated: true, completion: nil)
                    } else {
                        Preferences.Privacy.privateBrowsingOnly.value = value
                        applyThemeBlock()
                    }
                }
            )
        )
        return privacy
    }()

    private lazy var securitySection: Section = {
        let passcodeTitle: String = {
            let localAuthContext = LAContext()
            if localAuthContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                let title: String
                if localAuthContext.biometryType == .faceID {
                    return Strings.authenticationFaceIDPasscodeSetting
                } else {
                    return Strings.authenticationTouchIDPasscodeSetting
                }
            } else {
                return Strings.authenticationPasscode
            }
        }()
        
        return Section(
            header: .title(Strings.security),
            rows: [
                Row(text: passcodeTitle, selection: { [unowned self] in
                    let passcodeSettings = PasscodeSettingsViewController()
                    self.navigationController?.pushViewController(passcodeSettings, animated: true)
                    }, accessory: .disclosureIndicator, cellClass: MultilineValue1Cell.self)
            ]
        )
    }()
    
    private lazy var shieldsSection: Section = {
        var shields = Section(
            header: .title(Strings.shieldsDefaults),
            rows: [
                .boolRow(title: Strings.blockAdsAndTracking, option: Preferences.Shields.blockAdsAndTracking),
                .boolRow(title: Strings.HTTPSEverywhere, option: Preferences.Shields.httpsEverywhere),
                .boolRow(title: Strings.blockPhishingAndMalware, option: Preferences.Shields.blockPhishingAndMalware),
                .boolRow(title: Strings.blockScripts, option: Preferences.Shields.blockScripts),
                .boolRow(title: Strings.fingerprintingProtection, option: Preferences.Shields.fingerprintingProtection),
            ]
        )
        if let locale = Locale.current.languageCode, let _ = ContentBlockerRegion.with(localeCode: locale) {
            shields.rows.append(.boolRow(title: Strings.useRegionalAdblock, option: Preferences.Shields.useRegionAdBlock))
        }
        return shields
    }()
    
    private lazy var supportSection: Section = {
        return Section(
            header: .title(Strings.support),
            rows: [
                Row(text: Strings.reportABug,
                    selection: { [unowned self] in
                        self.settingsDelegate?.settingsOpenURLInNewTab(BraveUX.braveCommunityURL)
                        self.dismiss(animated: true)
                    },
                    cellClass: MultilineButtonCell.self),
                Row(text: Strings.rateBrave,
                    selection: { [unowned self] in
                        // Rate Brave
                        guard let writeReviewURL = URL(string: "https://itunes.apple.com/app/id1052879175?action=write-review")
                            else { return }
                        UIApplication.shared.open(writeReviewURL)
                        self.dismiss(animated: true)
                    },
                    cellClass: MultilineValue1Cell.self),
                Row(text: Strings.privacyPolicy,
                    selection: { [unowned self] in
                        // Show privacy policy
                        let privacy = SettingsContentViewController().then { $0.url = BraveUX.bravePrivacyURL }
                        self.navigationController?.pushViewController(privacy, animated: true)
                    },
                    accessory: .disclosureIndicator, cellClass: MultilineValue1Cell.self),
                Row(text: Strings.termsOfUse,
                    selection: { [unowned self] in
                        // Show terms of use
                        let toc = SettingsContentViewController().then { $0.url = BraveUX.braveTermsOfUseURL }
                        self.navigationController?.pushViewController(toc, animated: true)
                    },
                    accessory: .disclosureIndicator, cellClass: MultilineValue1Cell.self)
            ]
        )
    }()
    
    private lazy var aboutSection: Section = {
        let version = String(format: Strings.versionTemplate,
                             Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                             Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
        return Section(
            header: .title(Strings.about),
            rows: [
                Row(text: version, selection: { [unowned self] in
                    let device = UIDevice.current
                    let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                    actionSheet.popoverPresentationController?.sourceView = self.view
                    actionSheet.popoverPresentationController?.sourceRect = self.view.bounds
                    let iOSVersion = "\(device.systemName) \(UIDevice.current.systemVersion)"
                    
                    let deviceModel = String(format: Strings.deviceTemplate, device.modelName, iOSVersion)
                    let copyDebugInfoAction = UIAlertAction(title: Strings.copyAppInfoToClipboard, style: .default) { _ in
                        UIPasteboard.general.strings = [version, deviceModel]
                    }
                    
                    actionSheet.addAction(copyDebugInfoAction)
                    actionSheet.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: nil))
                    self.navigationController?.present(actionSheet, animated: true, completion: nil)
                }, cellClass: MultilineValue1Cell.self),
                Row(text: Strings.settingsLicenses, selection: { [unowned self] in
                    guard let url = URL(string: WebServer.sharedInstance.base) else { return }
                    
                    let licenses = SettingsContentViewController().then {
                        $0.url = url.appendingPathComponent("about").appendingPathComponent("license")
                    }
                    self.navigationController?.pushViewController(licenses, animated: true)
                    }, accessory: .disclosureIndicator)
            ]
        )
    }()
    
    private lazy var debugSection: Section? = {
        if AppConstants.buildChannel.isPublic { return nil }
        
        return Section(
            rows: [
                Row(text: "Region: \(Locale.current.regionCode ?? "--")"),
                Row(text: "Adblock Debug", selection: { [weak self] in
                    let vc = AdblockDebugMenuTableViewController(style: .grouped)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }, accessory: .disclosureIndicator, cellClass: MultilineValue1Cell.self),
                Row(text: "View URP Logs", selection: {
                    self.navigationController?.pushViewController(UrpLogsViewController(), animated: true)
                }, accessory: .disclosureIndicator, cellClass: MultilineValue1Cell.self),
                Row(text: "URP Code: \(UserReferralProgram.getReferralCode() ?? "--")"),
                Row(text: "View Rewards Debug Menu", selection: {
                    self.displayRewardsDebugMenu()
                }, accessory: .disclosureIndicator, cellClass: MultilineValue1Cell.self),
                Row(text: "Load all QA Links", selection: {
                    let url = URL(string: "https://raw.githubusercontent.com/brave/qa-resources/master/testlinks.json")!
                    let string = try? String(contentsOf: url)
                    let urls = JSON(parseJSON: string!)["links"].arrayValue.compactMap { URL(string: $0.stringValue) }
                    self.settingsDelegate?.settingsOpenURLs(urls)
                    self.dismiss(animated: true)
                }, cellClass: MultilineButtonCell.self),
                Row(text: "CRASH!!!", selection: {
                    let alert = UIAlertController(title: "Force crash?", message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Crash app", style: .destructive) { _ in
                        fatalError()
                    })
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }, cellClass: MultilineButtonCell.self)
            ]
        )
    }()
    
    func toggleSwitch(on: Bool, section: Section, rowUUID: String) {
        if let sectionRow: Row = section.rows.first(where: {$0.uuid == rowUUID}) {
            if let switchView: UISwitch = sectionRow.accessory.view as? UISwitch {
                switchView.setOn(on, animated: true)
            }
        }
    }
}

extension TableViewController: Themeable {
    func applyTheme(_ theme: Theme) {
        styleChildren(theme: theme)
        tableView.reloadData()

        //  View manipulations done via `apperance()` do not impact existing UI, so need to adjust manually
        // exiting menus, so setting explicitly.
        navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationController?.navigationBar.barTintColor = UINavigationBar.appearance().appearanceBarTintColor
        navigationController?.navigationBar.titleTextAttributes =
            [NSAttributedString.Key.foregroundColor: theme.colors.tints.home]
    }
}
