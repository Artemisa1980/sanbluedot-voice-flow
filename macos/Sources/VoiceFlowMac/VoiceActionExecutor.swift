import AppKit
import Foundation
import VoiceFlowMacCore

enum VoiceActionExecutionResult {
    case openedApp(String)
    case openedURL(URL)
    /// No application by that name exists on this Mac, so the name's website opened
    /// instead. Kept distinct so the interface can say a site opened rather than repeat
    /// the parser's "Open App", which would name something that did not happen.
    case openedSiteForMissingApp(name: String, url: URL)
    case failed(String)

    var isSuccess: Bool {
        switch self {
        case .openedApp, .openedURL, .openedSiteForMissingApp: return true
        case .failed: return false
        }
    }

    /// What to show the speaker. The parser's description is right for everything the
    /// executor did as asked; only the site fallback did something else.
    func label(for action: VoiceAction) -> String {
        switch self {
        case .openedSiteForMissingApp(let name, let url):
            return "Open site: \(url.host ?? url.absoluteString) · no \(name) app installed"
        case .openedApp, .openedURL, .failed:
            return action.displayDescription
        }
    }
}

enum VoiceActionExecutor {
    static func execute(_ action: VoiceAction) -> VoiceActionExecutionResult {
        switch action.type {
        case .openURL(let url):
            if NSWorkspace.shared.open(url) {
                return .openedURL(url)
            } else {
                return .failed("Could not open URL: \(url.absoluteString)")
            }

        case .googleSearch(let query, let browserBundleID):
            guard let url = SearchURL.google(query) else {
                return .failed("Invalid search query: \(query)")
            }
            // The browser the sentence named, when it is installed. `open(url)` alone
            // handed "abre safari y busca …" to the default browser (D-136).
            if let browserBundleID,
               let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID) {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: browserURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return .openedURL(url)
            }
            if NSWorkspace.shared.open(url) {
                return .openedURL(url)
            } else {
                return .failed("Could not open browser for query: \(query)")
            }

        case .youtubeSearch(let query):
            guard let url = SearchURL.youtube(query) else {
                return .failed("Invalid search query: \(query)")
            }
            if NSWorkspace.shared.open(url) {
                return .openedURL(url)
            } else {
                return .failed("Could not open YouTube for query: \(query)")
            }

        case .githubSearch(let query):
            guard let url = SearchURL.github(query) else {
                return .failed("Invalid search query: \(query)")
            }
            if NSWorkspace.shared.open(url) {
                return .openedURL(url)
            } else {
                return .failed("Could not open GitHub for query: \(query)")
            }

        case .openApp(let appName):
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            // The search order lives in `ApplicationSearch`, where a check can read it.
            for path in ApplicationSearch.candidatePaths(for: appName, home: home) {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    // The launch is asynchronous; a failure is reported when it arrives
                    // rather than the action being called done regardless (D-10).
                    NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                        guard let error else { return }
                        DispatchQueue.main.async {
                            NSSound.beep()
                            NSLog("VoiceFlow: %@ could not be opened: %@", appName, error.localizedDescription)
                            // Preserve user speech on the clipboard if async launch fails (R3c safety).
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appName, forType: .string)
                        }
                    }
                    return .openedApp(appName)
                }
            }
            // No application by that name. Some of these names are a website, not an
            // app: opening the site is what the speaker meant, and failing here is what
            // made "abre youtube" paste the sentence instead.
            if let site = WebDestination.url(forApplicationNamed: appName) {
                if NSWorkspace.shared.open(site) {
                    return .openedSiteForMissingApp(name: appName, url: site)
                }
                return .failed("Could not open \(site.absoluteString).")
            }
            return .failed("Application \"\(appName)\" was not found.")
        }
    }
}
