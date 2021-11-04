//  KeePassium Password Manager
//  Copyright © 2021 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol DatabasePickerCoordinatorDelegate: AnyObject {
    func shouldAcceptDatabaseSelection(
        _ fileRef: URLReference,
        in coordinator: DatabasePickerCoordinator) -> Bool

    func didSelectDatabase(_ fileRef: URLReference?, in coordinator: DatabasePickerCoordinator)
    
    func shouldKeepSelection(in coordinator: DatabasePickerCoordinator) -> Bool
}

public enum DatabasePickerMode {
    case full
    case autoFill
    case light
}

final class DatabasePickerCoordinator: NSObject, Coordinator, Refreshable {
    var childCoordinators = [Coordinator]()
    
    var dismissHandler: CoordinatorDismissHandler?
    weak var delegate: DatabasePickerCoordinatorDelegate?
    private(set) var selectedDatabase: URLReference?
    var shouldSelectDefaultDatabase = false
    
    private let router: NavigationRouter
    private let databasePickerVC: DatabasePickerVC
    private let mode: DatabasePickerMode
    
    private var fileKeeperNotifications: FileKeeperNotifications!
    
    init(router: NavigationRouter, mode: DatabasePickerMode) {
        self.router = router
        self.mode = mode
        databasePickerVC = DatabasePickerVC.instantiateFromStoryboard()
        databasePickerVC.mode = mode
        super.init()
        
        databasePickerVC.delegate = self
        fileKeeperNotifications = FileKeeperNotifications(observer: self)
    }
    
    deinit {
        assert(childCoordinators.isEmpty)
        removeAllChildCoordinators()
        
        fileKeeperNotifications.stopObserving()
    }
    
    func start() {
        router.push(databasePickerVC, animated: true, onPop: { [weak self] in
            guard let self = self else { return }
            self.removeAllChildCoordinators()
            self.dismissHandler?(self)
        })
        fileKeeperNotifications.startObserving()
    }
    
    func refresh() {
        databasePickerVC.refresh()
    }
    
    
    public func setEnabled(_ enabled: Bool) {
        databasePickerVC.isEnabled = enabled
    }
    
    public func selectDatabase(_ fileRef: URLReference?, animated: Bool) {
        selectedDatabase = fileRef
        switch mode {
        case .full, .autoFill:
            Settings.current.startupDatabase = fileRef
        case .light:
            break
        }
        databasePickerVC.selectDatabase(fileRef, animated: animated)
        delegate?.didSelectDatabase(fileRef, in: self)
    }
    
    #if MAIN_APP
    private func showTipBox(in viewController: UIViewController) {
        let modalRouter = NavigationRouter.createModal(style: .formSheet)
        let tipBoxCoordinator = TipBoxCoordinator(router: modalRouter)
        tipBoxCoordinator.dismissHandler = { [weak self] coordinator in
            self?.removeChildCoordinator(coordinator)
        }
        tipBoxCoordinator.start()
        addChildCoordinator(tipBoxCoordinator)
        viewController.present(modalRouter, animated: true, completion: nil)
    }
    
    func showAboutScreen(
        at popoverAnchor: PopoverAnchor,
        in viewController: UIViewController
    ) {
        let modalRouter = NavigationRouter.createModal(
            style: ProcessInfo.isRunningOnMac ? .formSheet : .popover,
            at: popoverAnchor)
        let aboutCoordinator = AboutCoordinator(router: modalRouter)
        aboutCoordinator.dismissHandler = { [weak self] coordinator in
            self?.removeChildCoordinator(coordinator)
        }
        aboutCoordinator.start()
        addChildCoordinator(aboutCoordinator)        
        viewController.present(modalRouter, animated: true, completion: nil)
    }

    func showAppSettings(
        at popoverAnchor: PopoverAnchor,
        in viewController: UIViewController
    ) {
        let modalRouter = NavigationRouter.createModal(
            style: ProcessInfo.isRunningOnMac ? .formSheet : .popover,
            at: popoverAnchor)
        let settingsCoordinator = SettingsCoordinator(router: modalRouter)
        settingsCoordinator.dismissHandler = { [weak self] coordinator in
            self?.removeChildCoordinator(coordinator)
        }
        settingsCoordinator.start()
        addChildCoordinator(settingsCoordinator)
        viewController.present(modalRouter, animated: true, completion: nil)
    }
    #endif
    
    private func hasValidDatabases() -> Bool {
        let accessibleDatabaseRefs = FileKeeper.shared
            .getAllReferences(fileType: .database, includeBackup: false)
            .filter { !$0.needsReinstatement } 
        return accessibleDatabaseRefs.count > 0
    }
    
    public func maybeAddExistingDatabase(presenter: UIViewController) {
        guard needsPremiumToAddDatabase() else {
            addExistingDatabase(presenter: presenter)
            return
        }

        performPremiumActionOrOfferUpgrade(for: .canUseMultipleDatabases, in: presenter) {
            [weak self, weak presenter] in
            guard let self = self,
                  let presenter = presenter
            else {
                return
            }
            self.addExistingDatabase(presenter: presenter)
        }
    }
    
    public func addExistingDatabase(presenter: UIViewController) {
        let documentPicker = UIDocumentPickerViewController(
            forOpeningContentTypes: FileType.databaseUTIs
        )
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .pageSheet
        presenter.present(documentPicker, animated: true, completion: nil)
    }
    
    private func addDatabaseFile(_ url: URL, mode: FileKeeper.OpenMode) {
        FileKeeper.shared.addFile(url: url, fileType: .database, mode: .openInPlace) {
            [weak self] (result) in
            switch result {
            case .success(let fileRef):
                self?.refresh()
                self?.selectDatabase(fileRef, animated: true)
            case .failure(let fileKeeperError):
                Diag.error("Failed to import database [message: \(fileKeeperError.localizedDescription)]")
                self?.refresh()
            }
        }
    }

    #if MAIN_APP
    public func maybeCreateDatabase(presenter: UIViewController) {
        guard needsPremiumToAddDatabase() else {
            createDatabase(presenter: presenter)
            return
        }
        
        performPremiumActionOrOfferUpgrade(for: .canUseMultipleDatabases, in: presenter) {
            [weak self, weak presenter] in
            guard let self = self,
                  let presenter = presenter
            else {
                return
            }
            self.createDatabase(presenter: presenter)
        }
    }
    
    public func createDatabase(presenter: UIViewController) {
        let modalRouter = NavigationRouter.createModal(style: .formSheet)
        let databaseCreatorCoordinator = DatabaseCreatorCoordinator(router: modalRouter)
        databaseCreatorCoordinator.delegate = self
        databaseCreatorCoordinator.dismissHandler = { [weak self] coordinator in
            self?.removeChildCoordinator(coordinator)
        }
        databaseCreatorCoordinator.start()
        
        presenter.present(modalRouter, animated: true, completion: nil)
        addChildCoordinator(databaseCreatorCoordinator)
    }
    #endif

    private func showFileInfo(
        _ fileRef: URLReference,
        at popoverAnchor: PopoverAnchor,
        in viewController: DatabasePickerVC
    ) {
        let fileInfoVC = FileInfoVC.make(urlRef: fileRef, fileType: .database, at: popoverAnchor)
        fileInfoVC.canExport = true
        fileInfoVC.didDeleteCallback = { [weak self, weak fileInfoVC] in
            self?.refresh()
            fileInfoVC?.dismiss(animated: true, completion: nil)
        }
        viewController.present(fileInfoVC, animated: true, completion: nil)
    }
    
    private func showDatabaseSettings(
        _ fileRef: URLReference,
        at popoverAnchor: PopoverAnchor,
        in viewController: DatabasePickerVC
    ) {
        let modalRouter = NavigationRouter.createModal(style: .popover, at: popoverAnchor)
        let databaseSettingsCoordinator = DatabaseSettingsCoordinator(
            fileRef: fileRef,
            router: modalRouter
        )
        databaseSettingsCoordinator.delegate = self
        databaseSettingsCoordinator.dismissHandler = { [weak self] coordinator in
            self?.removeChildCoordinator(coordinator)
        }
        databaseSettingsCoordinator.start()
        
        viewController.present(modalRouter, animated: true, completion: nil)
        addChildCoordinator(databaseSettingsCoordinator)
    }
}

extension DatabasePickerCoordinator: DatabasePickerDelegate {

    func getDefaultDatabase(
        from databases: [URLReference],
        in viewController: DatabasePickerVC
    ) -> URLReference? {
        switch mode {
        case .light:
            return nil
        case .full, .autoFill:
            break
        }
        
        defer {
            shouldSelectDefaultDatabase = false
        }
        guard shouldSelectDefaultDatabase,
              Settings.current.isAutoUnlockStartupDatabase
        else {
            return nil
        }
        
        #if AUTOFILL_EXT
        if databases.count == 1,
           let defaultDatabase = databases.first
        {
            return defaultDatabase
        }
        #endif
        if let startupDatabase = Settings.current.startupDatabase,
           let defaultDatabase = startupDatabase.find(in: databases)
        {
            return defaultDatabase
        }
        return nil
    }
    
    
    private func needsPremiumToAddDatabase() -> Bool {
        if hasValidDatabases() {
            let isEligible = PremiumManager.shared.isAvailable(feature: .canUseMultipleDatabases)
            return !isEligible
        } else {
            return false
        }
    }
    
    func needsPremiumToAddDatabase(in viewController: DatabasePickerVC) -> Bool {
        return needsPremiumToAddDatabase()
    }
    
    func didPressSetupAppLock(in viewController: DatabasePickerVC) {
        let passcodeInputVC = PasscodeInputVC.instantiateFromStoryboard()
        passcodeInputVC.delegate = self
        passcodeInputVC.mode = .setup
        passcodeInputVC.modalPresentationStyle = .formSheet
        passcodeInputVC.isCancelAllowed = true
        viewController.present(passcodeInputVC, animated: true, completion: nil)
    }
    
    #if MAIN_APP
    func didPressHelp(at popoverAnchor: PopoverAnchor, in viewController: DatabasePickerVC) {
        showAboutScreen(at: popoverAnchor, in: viewController)
    }
    
    func didPressSettings(at popoverAnchor: PopoverAnchor, in viewController: DatabasePickerVC) {
        showAppSettings(at: popoverAnchor, in: viewController)
    }
    
    func didPressCreateDatabase(in viewController: DatabasePickerVC) {
        maybeCreateDatabase(presenter: viewController)
    }
    #endif
    
    func didPressCancel(in viewController: DatabasePickerVC) {
        router.pop(viewController: databasePickerVC, animated: true)
    }
    
    func didPressAddExistingDatabase(in viewController: DatabasePickerVC) {
        maybeAddExistingDatabase(presenter: viewController)
    }

    func didPressRevealDatabaseInFinder(
        _ fileRef: URLReference,
        in viewController: DatabasePickerVC
    ) {
        FileExportHelper.revealInFinder(fileRef)
    }

    func didPressExportDatabase(
        _ fileRef: URLReference,
        at popoverAnchor: PopoverAnchor,
        in viewController: DatabasePickerVC
    ) {
        FileExportHelper.showFileExportSheet(fileRef, at: popoverAnchor, parent: viewController)
    }
    
    func didPressEliminateDatabase(
        _ fileRef: URLReference,
        shouldConfirm: Bool,
        at popoverAnchor: PopoverAnchor,
        in viewController: DatabasePickerVC
    ) {
        FileDestructionHelper.destroyFile(
            fileRef,
            fileType: .database,
            withConfirmation: shouldConfirm,
            at: popoverAnchor,
            parent: viewController,
            completion: { [weak self] isEliminated in
                guard let self = self else { return }
                if isEliminated && (fileRef === self.selectedDatabase) {
                    self.selectDatabase(nil, animated: false)
                }
                self.refresh()
            }
        )
    }
    
    func didPressFileInfo(
        _ fileRef: URLReference,
        at popoverAnchor: PopoverAnchor,
        in viewController: DatabasePickerVC
    ) {
        showFileInfo(fileRef, at: popoverAnchor, in: viewController)
    }
    
    func didPressDatabaseSettings(
        _ fileRef: URLReference,
        at popoverAnchor: PopoverAnchor,
        in viewController: DatabasePickerVC
    ) {
        showDatabaseSettings(fileRef, at: popoverAnchor, in: viewController)
    }

    func shouldKeepSelection(in viewController: DatabasePickerVC) -> Bool {
        return delegate?.shouldKeepSelection(in: self) ?? true
    }
    
    func shouldAcceptDatabaseSelection(
        _ fileRef: URLReference,
        in viewController: DatabasePickerVC
    ) -> Bool {
        return delegate?.shouldAcceptDatabaseSelection(fileRef, in: self) ?? true
    }
    
    func didSelectDatabase(_ fileRef: URLReference, in viewController: DatabasePickerVC) {
        selectDatabaseOrOfferPremiumUpgrade(fileRef, in: viewController)
    }
    
    private func selectDatabaseOrOfferPremiumUpgrade(
        _ fileRef: URLReference,
        in viewController: DatabasePickerVC
    ) {
        if fileRef == Settings.current.startupDatabase {
            selectDatabase(fileRef, animated: false)
            return
        }
        
        let validSortedDatabases = viewController.databaseRefs.filter {
            !$0.hasError && $0.location != .internalBackup
        }
        let isFirstDatabase = (fileRef === validSortedDatabases.first)
        if isFirstDatabase || fileRef.location == .internalBackup {
            selectDatabase(fileRef, animated: false)
        } else {
            performPremiumActionOrOfferUpgrade(
                for: .canUseMultipleDatabases,
                allowBypass: true,
                in: viewController,
                actionHandler: { [weak self] in
                    self?.selectDatabase(fileRef, animated: false)
                }
            )
        }
    }
}


extension DatabasePickerCoordinator: PasscodeInputDelegate {
    func passcodeInputDidCancel(_ sender: PasscodeInputVC) {
        do {
            try Keychain.shared.removeAppPasscode() 
        } catch {
            Diag.error(error.localizedDescription)
            databasePickerVC.showErrorAlert(error, title: LString.titleKeychainError)
            return
        }
        sender.dismiss(animated: true, completion: nil)
        refresh()
    }
    
    func passcodeInput(_sender: PasscodeInputVC, canAcceptPasscode passcode: String) -> Bool {
        return passcode.count > 0
    }
    
    func passcodeInput(_ sender: PasscodeInputVC, didEnterPasscode passcode: String) {
        sender.dismiss(animated: true) {
            [weak self] in
            do {
                let keychain = Keychain.shared
                try keychain.setAppPasscode(passcode)
                keychain.prepareBiometricAuth(true)
                Settings.current.isBiometricAppLockEnabled = true
                self?.refresh()
            } catch {
                Diag.error(error.localizedDescription)
                self?.databasePickerVC.showErrorAlert(error, title: LString.titleKeychainError)
            }
        }
    }
}

extension DatabasePickerCoordinator: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first else { return }
        FileAddingHelper.ensureFileIsDatabase(url, parent: databasePickerVC) {
            [weak self] (url) in
            self?.addDatabaseFile(url, mode: .openInPlace)
        }
    }
}

#if MAIN_APP
extension DatabasePickerCoordinator: DatabaseCreatorCoordinatorDelegate {
    func didCreateDatabase(
        in databaseCreatorCoordinator: DatabaseCreatorCoordinator,
        database urlRef: URLReference
    ) {
        selectDatabase(urlRef, animated: true)
    }
}
#endif

extension DatabasePickerCoordinator: DatabaseSettingsCoordinatorDelegate {
    func didChangeDatabaseSettings(in coordinator: DatabaseSettingsCoordinator) {
        refresh()
    }
}

extension DatabasePickerCoordinator: FileKeeperObserver {
    func fileKeeper(didAddFile urlRef: URLReference, fileType: FileType) {
        guard fileType == .database else { return }
        refresh()
    }
    
    func fileKeeper(didRemoveFile urlRef: URLReference, fileType: FileType) {
        guard fileType == .database else { return }
        if urlRef === selectedDatabase {
            selectDatabase(nil, animated: false)
        }
        refresh()
    }
}
