import Foundation
import Combine
import ServiceManagement

final class SettingsStore: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var enableDriftCorrectionByDefault: Bool {
        didSet { UserDefaults.standard.set(enableDriftCorrectionByDefault, forKey: Keys.drift) }
    }

    @Published var restoreOutputOnStop: Bool {
        didSet { UserDefaults.standard.set(restoreOutputOnStop, forKey: Keys.restoreOutput) }
    }

    @Published var notifyOnDisconnect: Bool {
        didSet { UserDefaults.standard.set(notifyOnDisconnect, forKey: Keys.notifyDisconnect) }
    }

    @Published var developerMode: Bool {
        didSet { UserDefaults.standard.set(developerMode, forKey: Keys.developerMode) }
    }

    private enum Keys {
        static let launchAtLogin = "settings.launchAtLogin"
        static let showMenuBarIcon = "settings.showMenuBarIcon"
        static let drift = "settings.driftCorrection"
        static let restoreOutput = "settings.restoreOutput"
        static let notifyDisconnect = "settings.notifyDisconnect"
        static let developerMode = "settings.developerMode"
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.showMenuBarIcon) == nil {
            defaults.set(true, forKey: Keys.showMenuBarIcon)
        }
        if defaults.object(forKey: Keys.drift) == nil {
            defaults.set(true, forKey: Keys.drift)
        }
        if defaults.object(forKey: Keys.restoreOutput) == nil {
            defaults.set(true, forKey: Keys.restoreOutput)
        }
        if defaults.object(forKey: Keys.notifyDisconnect) == nil {
            defaults.set(true, forKey: Keys.notifyDisconnect)
        }

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        enableDriftCorrectionByDefault = defaults.bool(forKey: Keys.drift)
        restoreOutputOnStop = defaults.bool(forKey: Keys.restoreOutput)
        notifyOnDisconnect = defaults.bool(forKey: Keys.notifyDisconnect)
        developerMode = defaults.bool(forKey: Keys.developerMode)
    }

    private func applyLaunchAtLogin() {
        #if os(macOS)
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Launch-at-login requires a proper app bundle / SMAppService setup.
        }
        #endif
    }
}
