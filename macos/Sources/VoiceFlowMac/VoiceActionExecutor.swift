import AppKit
import Foundation
import VoiceFlowMacCore

enum VoiceActionExecutionResult {
    case openedApp(String)
    case openedURL(URL)
    case failed(String)

    var isSuccess: Bool {
        switch self {
        case .openedApp, .openedURL: return true
        case .failed: return false
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

        case .googleSearch(let query):
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
            guard let url = components?.url else {
                return .failed("Invalid search query: \(query)")
            }
            if NSWorkspace.shared.open(url) {
                return .openedURL(url)
            } else {
                return .failed("Could not open browser for query: \(query)")
            }

        case .youtubeSearch(let query):
            var components = URLComponents(string: "https://www.youtube.com/results")
            components?.queryItems = [URLQueryItem(name: "search_query", value: query)]
            guard let url = components?.url else {
                return .failed("Invalid search query: \(query)")
            }
            if NSWorkspace.shared.open(url) {
                return .openedURL(url)
            } else {
                return .failed("Could not open YouTube for query: \(query)")
            }

        case .githubSearch(let query):
            var components = URLComponents(string: "https://github.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
            guard let url = components?.url else {
                return .failed("Invalid search query: \(query)")
            }
            if NSWorkspace.shared.open(url) {
                return .openedURL(url)
            } else {
                return .failed("Could not open GitHub for query: \(query)")
            }

        case .openApp(let appName):
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let appURLCandidates = [
                "/Applications/\(appName).app",
                "/System/Applications/\(appName).app",
                "/System/Applications/Utilities/\(appName).app",
                "/System/Library/CoreServices/\(appName).app",
                "\(home)/Applications/\(appName).app",
                "/Applications/\(appName.capitalized).app",
                "/System/Applications/\(appName.capitalized).app",
                "/System/Library/CoreServices/\(appName.capitalized).app"
            ]
            for path in appURLCandidates {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                    return .openedApp(appName)
                }
            }
            return .failed("Application \"\(appName)\" was not found.")
        }
    }
}
