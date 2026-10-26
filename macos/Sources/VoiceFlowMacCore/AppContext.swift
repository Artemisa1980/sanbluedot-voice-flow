import Foundation

/// The functional category of an active frontmost application.
public enum AppCategory: String, CaseIterable, Equatable {
    /// Code editors, IDEs, and terminal emulators.
    case code = "CODE"
    /// AI chat applications and desktop prompt tools.
    case aiPrompt = "PROMPT"
    /// Instant messaging and team chat clients.
    case chat = "CHAT"
    /// Email clients, word processors, and note-taking applications.
    case document = "DOCS"
    /// General desktop applications and system surfaces.
    case general = "GENERAL"
}

/// Resolved context of the application where text will be delivered.
public struct AppContext: Equatable {
    public let bundleIdentifier: String?
    public let localizedName: String
    public let shortName: String
    public let category: AppCategory

    public init(
        bundleIdentifier: String?,
        localizedName: String,
        shortName: String,
        category: AppCategory
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.shortName = shortName
        self.category = category
    }

    /// Formatted badge string displayed in the HUD or telemetry status.
    public var badgeLabel: String {
        switch category {
        case .general:
            return shortName.isEmpty ? "DESKTOP" : shortName
        default:
            return "\(shortName) • \(category.rawValue)"
        }
    }

    /// Known application bundle identifier mappings.
    private static let knownApps: [String: (shortName: String, category: AppCategory)] = [
        // --- Code Editors & IDEs ---
        "com.microsoft.VSCode": ("VSCODE", .code),
        "com.microsoft.VSCodeInsiders": ("VSCODE", .code),
        "com.visualstudio.code.oss": ("VSCODE", .code),
        "com.todesktop.230313mzl4w4u92": ("CURSOR", .code),
        "com.apple.dt.Xcode": ("XCODE", .code),
        "com.sublimetext.4": ("SUBLIME", .code),
        "com.sublimetext.3": ("SUBLIME", .code),
        "com.jetbrains.intellij": ("INTELLIJ", .code),
        "com.jetbrains.pycharm": ("PYCHARM", .code),
        "com.panic.Nova": ("NOVA", .code),

        // --- Terminal Emulators ---
        "com.apple.Terminal": ("TERMINAL", .code),
        "com.googlecode.iterm2": ("ITERM", .code),
        "dev.warp.Warp-Stable": ("WARP", .code),
        "co.zeit.hyper": ("HYPER", .code),
        "net.kovidgoyal.kitty": ("KITTY", .code),
        "org.alacritty": ("ALACRITTY", .code),
        "com.github.wez.wezterm": ("WEZTERM", .code),
        "com.mitchellh.ghostty": ("GHOSTTY", .code),

        // --- AI Desktop Apps & Prompt Tools ---
        "com.anthropic.claudefordesktop": ("CLAUDE", .aiPrompt),
        "com.openai.chat": ("CHATGPT", .aiPrompt),
        "com.electron.ollama": ("OLLAMA", .aiPrompt),
        "com.lmstudio.app": ("LMSTUDIO", .aiPrompt),

        // --- Chat & Messaging ---
        "com.tinyspeck.slackmacgap": ("SLACK", .chat),
        "net.whatsapp.WhatsApp": ("WHATSAPP", .chat),
        "net.whatsapp.WhatsApp.desktop": ("WHATSAPP", .chat),
        "com.apple.MobileSMS": ("MESSAGES", .chat),
        "ru.keepcoder.Telegram": ("TELEGRAM", .chat),
        "com.tdesktop.Telegram": ("TELEGRAM", .chat),
        "com.hnc.Discord": ("DISCORD", .chat),

        // --- Documents, Notes & Mail ---
        "com.apple.mail": ("MAIL", .document),
        "com.microsoft.Outlook": ("OUTLOOK", .document),
        "com.apple.Notes": ("NOTES", .document),
        "notion.id": ("NOTION", .document),
        "com.microsoft.Word": ("WORD", .document),
        "com.apple.Pages": ("PAGES", .document),
        "com.apple.TextEdit": ("TEXTEDIT", .document),
        "md.obsidian": ("OBSIDIAN", .document),
    ]

    /// The longest short name the HUD capsule can show.
    ///
    /// A mapped application supplies its own short name and is well inside this. The
    /// heuristic below has no such name and falls back to the full localized one, which
    /// is where the limit matters: the recording badge is drawn with `fixedSize()`, so it
    /// does not truncate — it pushes the wordmark out of a 226pt row instead. Measured at
    /// 10pt heavy monospaced, the badge has 153.7pt, or 24 characters; half is kept for the
    /// badge's own prefix, which leaves 12 for the name.
    public static let shortNameLimit = 12

    /// Shorten a full application name to something the capsule can carry.
    public static func shortName(from localizedName: String) -> String {
        let upper = localizedName.uppercased()
        if upper.count <= shortNameLimit {
            return upper
        }
        // A first word beats a cut word: "VISUAL STUDIO CODE" reads better as "VISUAL"
        // than as "VISUAL STUDI".
        if let firstWord = upper.split(separator: " ").first, firstWord.count <= shortNameLimit {
            return String(firstWord)
        }
        return String(upper.prefix(shortNameLimit))
    }

    /// Resolve the target application context from bundle ID and localized name.
    public static func resolve(bundleIdentifier: String?, localizedName: String?) -> AppContext {
        let name = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false) ? name! : "Desktop"

        guard let bundleId = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleId.isEmpty else {
            return AppContext(
                bundleIdentifier: nil,
                localizedName: resolvedName,
                shortName: shortName(from: resolvedName),
                category: .general
            )
        }

        if let match = knownApps[bundleId] {
            return AppContext(
                bundleIdentifier: bundleId,
                localizedName: resolvedName,
                shortName: match.shortName,
                category: match.category
            )
        }

        // Heuristic fallback by localized name for unlisted apps
        let lowerName = resolvedName.lowercased()
        if lowerName.contains("code") || lowerName.contains("terminal") || lowerName.contains("cursor") {
            return AppContext(bundleIdentifier: bundleId, localizedName: resolvedName, shortName: shortName(from: resolvedName), category: .code)
        }
        if lowerName.contains("slack") || lowerName.contains("chat") || lowerName.contains("whatsapp") || lowerName.contains("telegram") {
            return AppContext(bundleIdentifier: bundleId, localizedName: resolvedName, shortName: shortName(from: resolvedName), category: .chat)
        }
        if lowerName.contains("mail") || lowerName.contains("notes") || lowerName.contains("docs") || lowerName.contains("word") {
            return AppContext(bundleIdentifier: bundleId, localizedName: resolvedName, shortName: shortName(from: resolvedName), category: .document)
        }

        return AppContext(
            bundleIdentifier: bundleId,
            localizedName: resolvedName,
            shortName: shortName(from: resolvedName),
            category: .general
        )
    }
}
