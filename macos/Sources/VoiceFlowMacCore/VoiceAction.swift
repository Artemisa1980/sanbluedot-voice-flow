import Foundation

public enum VoiceActionType: Equatable, Sendable {
    case openApp(appName: String)
    /// `browserBundleID` is set only when the sentence named a browser ("abre safari y
    /// busca …"); `nil` opens the default one.
    case googleSearch(query: String, browserBundleID: String? = nil)
    case youtubeSearch(query: String)
    case githubSearch(query: String)
    case openURL(url: URL)
}

public struct VoiceAction: Equatable, Sendable {
    public let type: VoiceActionType
    public let displayDescription: String
    public let queryOrTarget: String
    public let originalSpeech: String

    public init(
        type: VoiceActionType,
        displayDescription: String,
        queryOrTarget: String,
        originalSpeech: String
    ) {
        self.type = type
        self.displayDescription = displayDescription
        self.queryOrTarget = queryOrTarget
        self.originalSpeech = originalSpeech
    }

    /// Privacy-safe description for on-screen console logging (D-82 / R7).
    public var logSummary: String {
        switch type {
        case .openApp:
            return "open app"
        case .googleSearch:
            return "google search"
        case .youtubeSearch:
            return "youtube search"
        case .githubSearch:
            return "github search"
        case .openURL:
            return "open url"
        }
    }
}

/// The search pages a spoken search opens.
///
/// `URLQueryItem` leaves `+` unescaped, and these sites read it as a space, so "c++"
/// arrived as "c  " (D-61). The plus is encoded after the query is built.
public enum SearchURL {
    public static func google(_ query: String) -> URL? {
        make("https://www.google.com/search", name: "q", query)
    }

    public static func youtube(_ query: String) -> URL? {
        make("https://www.youtube.com/results", name: "search_query", query)
    }

    public static func github(_ query: String) -> URL? {
        make("https://github.com/search", name: "q", query)
    }

    private static func make(_ base: String, name: String, _ query: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [URLQueryItem(name: name, value: query)]
        let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components.percentEncodedQuery = encoded
        return components.url
    }
}

/// Names that are a website here, not an application.
///
/// "abre youtube" used to resolve to `YouTube.app`, which does not exist, so the action
/// failed and the sentence was pasted instead. The lookup is consulted only after the
/// executor has searched this Mac for a real application, so an installed app always
/// wins: `abre spotify` opens Spotify, and only a name with no app behind it becomes a
/// site. A name that is neither is still a failure, so an ordinary word can never turn
/// into a browser window.
public enum WebDestination {
    /// Keyed by the lowercased application name the parser produced.
    public static let sites: [String: String] = [
        "youtube": "https://www.youtube.com",
        "gmail": "https://mail.google.com",
        "google": "https://www.google.com",
        "google drive": "https://drive.google.com",
        "drive": "https://drive.google.com",
        "github": "https://github.com",
        "linkedin": "https://www.linkedin.com",
        "whatsapp": "https://web.whatsapp.com",
        "instagram": "https://www.instagram.com",
        "facebook": "https://www.facebook.com",
        "netflix": "https://www.netflix.com",
        "chatgpt": "https://chatgpt.com",
        "claude": "https://claude.ai",
        "canva": "https://www.canva.com",
        "notion": "https://www.notion.so",
        "figma": "https://www.figma.com",
    ]

    /// The site to open when no application by this name exists on the machine.
    public static func url(forApplicationNamed name: String) -> URL? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let site = sites[key] else { return nil }
        return URL(string: site)
    }

    /// Whether this name has a site to fall back to. Exposed so a check can assert the
    /// table stays parseable without opening anything.
    public static func hasSite(forApplicationNamed name: String) -> Bool {
        url(forApplicationNamed: name) != nil
    }
}

/// Where a spoken application name is looked for, in order.
///
/// The list is pure so a check can assert the search order and the escaping rules
/// without touching the file system. `VoiceActionExecutor` walks it and takes the first
/// path that exists; only if none does is `WebDestination` consulted.
public enum ApplicationSearch {
    public static func candidatePaths(for appName: String, home: String) -> [String] {
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "\(home)/Applications",
        ]
        var names = [appName]
        // The parser capitalizes an unknown name, but an alias resolves to its real
        // one; both spellings are tried before the name is declared missing.
        if appName.capitalized != appName {
            names.append(appName.capitalized)
        }
        return names.flatMap { name in roots.map { "\($0)/\(name).app" } }
    }
}

public enum VoiceActionParser {
    /// Parse natural speech into a recognized system action.
    /// Handles both Spanish and English phrases with leading/trailing punctuation tolerance.
    public static func parse(text: String) -> VoiceAction? {
        let cleaned = sanitize(text)
        guard !cleaned.isEmpty else { return nil }

        // 1. URL / Domain Navigation: "ir a apple.com", "open github.com", "go to https://google.com"
        if let urlAction = parseURL(from: cleaned, original: text) {
            return urlAction
        }

        // 2. Open Browser & Search: "abre safari y busca amazon", "open chrome and search macbook"
        if let browserSearchAction = parseBrowserSearch(from: cleaned, original: text) {
            return browserSearchAction
        }

        // 3. YouTube Search: "busca en youtube tutorial swiftui", "search youtube for lofi"
        if let youtubeAction = parseYouTubeSearch(from: cleaned, original: text) {
            return youtubeAction
        }

        // 4. GitHub Search: "busca en github voice flow", "search github for whisper"
        if let githubAction = parseGitHubSearch(from: cleaned, original: text) {
            return githubAction
        }

        // 5. Google Search: "busca en google amazon", "search google for apple", "googlear precios macbook"
        if let googleAction = parseGoogleSearch(from: cleaned, original: text) {
            return googleAction
        }

        // 6. Open Application: "abre notas", "abrir visual studio code", "open terminal", "launch spotify"
        if let appAction = parseOpenApp(from: cleaned, original: text) {
            return appAction
        }

        return nil
    }

    private static let leadingPunctuation = CharacterSet(charactersIn: "¿¡\"'«“` \t\n\r")
    private static let trailingPunctuation = CharacterSet(charactersIn: ".?!,\" '»”` \t\n\r")

    private static func sanitize(_ text: String) -> String {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading inverted punctuation, quotes
        while let scalar = str.unicodeScalars.first, leadingPunctuation.contains(scalar) {
            str.removeFirst()
        }
        // Strip trailing punctuation, quotes
        while let scalar = str.unicodeScalars.last, trailingPunctuation.contains(scalar) {
            str.removeLast()
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let fileExtensions: Set<String> = [
        "md", "txt", "swift", "py", "json", "pdf", "doc", "docx", "xls", "xlsx", "csv",
        "png", "jpg", "jpeg", "gif", "sh", "js", "ts", "yml", "yaml", "toml", "zip", "wav",
    ]

    private static func parseURL(from text: String, original: String) -> VoiceAction? {
        let patterns = [
            #"^(?:ir\s+a|navega\s+a|navegar\s+a|abre|abrir|open|go\s+to|navigate\s+to)\s+((?:https?:\/\/)?(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:\/[^\s]*)?)$"#
        ]
        for pattern in patterns {
            if let target = matchRegex(pattern: pattern, in: text, captureGroup: 1) {
                let lower = target.lowercased()
                let hasScheme = lower.hasPrefix("http://") || lower.hasPrefix("https://")
                // "open README.md" is a file, not a site: a single name ending in a file
                // extension, with no scheme and no `www.`, is not opened as a URL (D-77).
                let labels = lower.split(separator: "/").first?.split(separator: ".") ?? []
                if !hasScheme, !lower.hasPrefix("www."), labels.count == 2,
                   let ext = labels.last, Self.fileExtensions.contains(String(ext)) {
                    continue
                }
                // The scheme is compared case-insensitively: "HTTPS://x" became "https://HTTPS://x".
                let urlString = hasScheme ? target : "https://\(target)"
                if let url = URL(string: urlString) {
                    return VoiceAction(
                        type: .openURL(url: url),
                        displayDescription: "Open URL: \(target)",
                        queryOrTarget: target,
                        originalSpeech: original
                    )
                }
            }
        }
        return nil
    }

    private static func parseBrowserSearch(from text: String, original: String) -> VoiceAction? {
        // Group 1 is the browser the sentence names, group 2 the query.
        let patterns = [
            #"^(?:abre|abrir|open|launch)\s+(safari|chrome|el\s+navegador|the\s+browser)\s+(?:y|and)\s+(?:busca|buscar|search\s+for|search)(?:\s+en\s+google|\s+on\s+google)?\s+(.+)$"#,
            #"^(?:abre|abrir|open)\s+(safari|chrome|el\s+navegador)\s+(?:con\s+la\s+búsqueda\s+de|searching\s+for)\s+(.+)$"#
        ]
        for pattern in patterns {
            if let query = matchRegex(pattern: pattern, in: text, captureGroup: 2) {
                let trimmed = sanitize(query)
                if !trimmed.isEmpty {
                    let named = matchRegex(pattern: pattern, in: text, captureGroup: 1)?.lowercased()
                    return VoiceAction(
                        type: .googleSearch(query: trimmed, browserBundleID: browserBundleID(for: named)),
                        displayDescription: "Google Search \"\(trimmed)\"",
                        queryOrTarget: trimmed,
                        originalSpeech: original
                    )
                }
            }
        }
        return nil
    }

    private static func parseYouTubeSearch(from text: String, original: String) -> VoiceAction? {
        let patterns = [
            #"^(?:busca|buscar|buscar\s+en|busca\s+en)\s+youtube\s+(?:para\s+|de\s+|sobre\s+|el\s+video\s+de\s+|videos?\s+de\s+)?(.+)$"#,
            #"^(?:search|search\s+for|search\s+on)\s+youtube\s+(?:for\s+|about\s+|videos?\s+of\s+)?(.+)$"#,
            #"^(?:youtube)\s+(?:search\s+for\s+|search\s+)(.+)$"#
        ]
        for pattern in patterns {
            if let query = matchRegex(pattern: pattern, in: text, captureGroup: 1) {
                let trimmed = sanitize(query)
                if !trimmed.isEmpty {
                    return VoiceAction(
                        type: .youtubeSearch(query: trimmed),
                        displayDescription: "YouTube \"\(trimmed)\"",
                        queryOrTarget: trimmed,
                        originalSpeech: original
                    )
                }
            }
        }
        return nil
    }

    private static func parseGitHubSearch(from text: String, original: String) -> VoiceAction? {
        let patterns = [
            #"^(?:busca|buscar|buscar\s+en|busca\s+en)\s+github\s+(?:el\s+repo\s+de\s+|repositorio\s+de\s+|para\s+|sobre\s+)?(.+)$"#,
            #"^(?:search|search\s+for|search\s+on)\s+github\s+(?:for\s+|repo\s+for\s+)?(.+)$"#,
            #"^(?:github)\s+(?:search\s+for\s+|search\s+)(.+)$"#
        ]
        for pattern in patterns {
            if let query = matchRegex(pattern: pattern, in: text, captureGroup: 1) {
                let trimmed = sanitize(query)
                if !trimmed.isEmpty {
                    return VoiceAction(
                        type: .githubSearch(query: trimmed),
                        displayDescription: "GitHub \"\(trimmed)\"",
                        queryOrTarget: trimmed,
                        originalSpeech: original
                    )
                }
            }
        }
        return nil
    }

    private static func parseGoogleSearch(from text: String, original: String) -> VoiceAction? {
        let patterns = [
            #"^(?:busca|buscar|busca\s+en|buscar\s+en)\s+google\s+(?:para\s+|sobre\s+|de\s+|acerca\s+de\s+)?(.+)$"#,
            #"^(?:search|search\s+for|search\s+on)\s+google\s+(?:for\s+|about\s+)?(.+)$"#,
            #"^(?:googlear|googlea)\s+(?:para\s+|sobre\s+|de\s+)?(.+)$"#,
            #"^(?:google)\s+(?:search\s+for\s+|search\s+)(.+)$"#,
            #"^(?:busca\s+en\s+la\s+web|buscar\s+en\s+la\s+web|search\s+the\s+web\s+for)\s+(.+)$"#
        ]
        for pattern in patterns {
            if let query = matchRegex(pattern: pattern, in: text, captureGroup: 1) {
                let trimmed = sanitize(query)
                if !trimmed.isEmpty {
                    return VoiceAction(
                        type: .googleSearch(query: trimmed),
                        displayDescription: "Google Search \"\(trimmed)\"",
                        queryOrTarget: trimmed,
                        originalSpeech: original
                    )
                }
            }
        }
        return nil
    }

    private static func parseOpenApp(from text: String, original: String) -> VoiceAction? {
        let patterns = [
            #"^(?:abre|abrir)\s+(?:la\s+app\s+de\s+|la\s+aplicaci[oó]n\s+de\s+|la\s+app\s+|la\s+aplicaci[oó]n\s+|el\s+|la\s+|los\s+|las\s+)?([\p{L}0-9\s]+)$"#,
            #"^(?:open|launch)\s+(?:the\s+app\s+|the\s+application\s+|app\s+|the\s+)?([\p{L}0-9\s]+)$"#
        ]
        for pattern in patterns {
            if let appCandidate = matchRegex(pattern: pattern, in: text, captureGroup: 1) {
                let trimmed = sanitize(appCandidate)
                guard !trimmed.isEmpty else { continue }
                
                // Guard against conversational false positives (e.g. "abre comillas", "open discussion")
                if isConversationalPhrase(trimmed) {
                    continue
                }

                let normalizedApp = normalizeAppName(trimmed)
                return VoiceAction(
                    type: .openApp(appName: normalizedApp),
                    displayDescription: "Open App: \(normalizedApp)",
                    queryOrTarget: normalizedApp,
                    originalSpeech: original
                )
            }
        }
        return nil
    }

    private static func isConversationalPhrase(_ candidate: String) -> Bool {
        let lower = candidate.lowercased()
        let nonAppKeywords = [
            "comillas", "pregunta", "preguntas", "sesion", "sesión", "debate", "discusion", "discusión",
            "cuenta", "puerta", "ventana", "documento", "archivo", "conversacion", "conversación",
            "discussion", "ticket", "pull request", "meeting", "dialogue", "file", "tab", "bracket"
        ]
        for keyword in nonAppKeywords {
            if lower == keyword || lower.hasPrefix("\(keyword) ") {
                return true
            }
        }
        // If it's more than 3 words and not a known app alias, reject as conversational
        let words = candidate.split(separator: " ")
        if words.count > 3 && !knownAppAliases.contains(lower) {
            return true
        }
        return false
    }

    private static let knownAppAliases: Set<String> = [
        "notas", "notes", "la app de notas", "las notas", "terminal", "la terminal", "the terminal",
        "visual studio code", "vs code", "vscode", "code", "spotify", "calculadora", "la calculadora",
        "calculator", "calc", "finder", "el finder", "safari", "el navegador", "the browser", "navegador",
        "google chrome", "chrome", "mensajes", "los mensajes", "messages", "mail", "el correo", "correo",
        "email", "calendario", "el calendario", "calendar", "recordatorios", "los recordatorios", "reminders",
        "musica", "música", "la musica", "la música", "music", "apple music", "configuracion",
        "configuración", "system settings", "preferencias", "ajustes"
    ]

    private static func normalizeAppName(_ raw: String) -> String {
        let lower = raw.lowercased()
        switch lower {
        case "notas", "notes", "la app de notas", "las notas": return "Notes"
        case "terminal", "la terminal", "the terminal": return "Terminal"
        case "visual studio code", "vs code", "vscode", "code": return "Visual Studio Code"
        case "spotify": return "Spotify"
        case "calculadora", "la calculadora", "calculator", "calc": return "Calculator"
        case "finder", "el finder": return "Finder"
        case "safari", "el navegador", "the browser", "navegador": return "Safari"
        case "google chrome", "chrome": return "Google Chrome"
        case "mensajes", "los mensajes", "messages": return "Messages"
        case "mail", "el correo", "correo", "email": return "Mail"
        case "calendario", "el calendario", "calendar": return "Calendar"
        case "recordatorios", "los recordatorios", "reminders": return "Reminders"
        case "musica", "música", "la musica", "la música", "music", "apple music": return "Music"
        case "configuracion", "configuración", "system settings", "preferencias", "ajustes": return "System Settings"
        default:
            return raw.capitalized
        }
    }

    /// The browser a search sentence named. "el navegador" and "the browser" name none,
    /// so they keep the default browser.
    private static func browserBundleID(for name: String?) -> String? {
        switch name {
        case "safari": return "com.apple.Safari"
        case "chrome": return "com.google.Chrome"
        default: return nil
        }
    }

    private static func matchRegex(pattern: String, in text: String, captureGroup: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > captureGroup else {
            return nil
        }
        let matchRange = match.range(at: captureGroup)
        guard matchRange.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: matchRange)
    }
}
