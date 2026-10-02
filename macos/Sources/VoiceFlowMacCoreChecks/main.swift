import AppKit
import Foundation
import VoiceFlowMacCore

enum CheckFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

/// Every source file that draws the interface, with the token declaration removed.
///
/// A colour written as a literal beside the view that uses it is a copy of a token that
/// no longer moves with it. Four had already drifted this way — the gold, the dot blue,
/// the navy twice — with identical values, which is precisely why nothing failed.
func interfaceSourcesWithoutTokenDeclarations() throws -> [(String, String)] {
    let macos = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    // Every file in the target, not a hand-kept list. A list of three covered three of
    // fourteen: a colour written in any of the other eleven passed unseen, while the
    // check reported that the interface was clean.
    let sources = macos.appendingPathComponent("Sources/VoiceFlowMac")
    guard let found = try? FileManager.default.contentsOfDirectory(
        at: sources,
        includingPropertiesForKeys: nil
    ) else {
        throw CheckFailure.failed("Could not list \(sources.path).")
    }
    let files = found
        .filter { $0.pathExtension == "swift" }
        .map { "VoiceFlowMac/\($0.lastPathComponent)" }
        .sorted()
    guard files.count >= 10 else {
        throw CheckFailure.failed(
            "Only \(files.count) interface sources were found; the guard is looking in the wrong place."
        )
    }
    return try files.map { relative in
        let url = macos.appendingPathComponent("Sources/\(relative)")
        guard var body = try? String(contentsOf: url, encoding: .utf8) else {
            throw CheckFailure.failed("Could not read \(relative).")
        }
        // The token enum is where literals belong; everything after it is a copy.
        if let start = body.range(of: "public enum VoiceStationTokens {"),
           let end = body.range(of: "\n}\n", range: start.upperBound..<body.endIndex) {
            body.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return (relative, body)
    }
}

/// The modes the engine refuses with the literal cleaner, read out of `cli.py`.
///
/// Same reason as the mode-choices reader below: a list copied into Swift is what this
/// check exists to catch, so the copy cannot be what it compares against.
func enginesRewritingModes() throws -> Set<String> {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let cli = projectRoot.appendingPathComponent("src/sanbluedot_voiceflow/cli.py")
    guard let source = try? String(contentsOf: cli, encoding: .utf8) else {
        throw CheckFailure.failed("Could not read the engine CLI at \(cli.path).")
    }
    guard let declaration = source.range(of: "REWRITING_MODES = ("),
          let close = source[declaration.upperBound...].range(of: ")") else {
        throw CheckFailure.failed("The engine CLI no longer declares REWRITING_MODES.")
    }
    let values = source[declaration.upperBound..<close.lowerBound]
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"'")) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw CheckFailure.failed("The engine CLI's REWRITING_MODES parsed empty.")
    }
    return Set(values)
}

/// The `--mode` values the engine's `process` subcommand actually accepts.
///
/// Read out of `cli.py` at check time. Duplicating the list in Swift is what this check
/// exists to catch, so it must not be the thing the check compares against.
func enginesProcessModeChoices() throws -> Set<String> {
    // <root>/macos/Sources/VoiceFlowMacCoreChecks/main.swift -> <root>
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let cli = projectRoot.appendingPathComponent("src/sanbluedot_voiceflow/cli.py")
    guard let source = try? String(contentsOf: cli, encoding: .utf8) else {
        throw CheckFailure.failed("Could not read the engine CLI at \(cli.path).")
    }
    // The `process` subparser's own --mode block, not another subcommand's.
    guard let processRange = source.range(of: "process.add_argument(\n        \"--mode\",") else {
        throw CheckFailure.failed("The engine CLI no longer declares process --mode where this check looks.")
    }
    let tail = source[processRange.upperBound...]
    guard let choicesStart = tail.range(of: "choices=["),
          let choicesEnd = tail[choicesStart.upperBound...].range(of: "]") else {
        throw CheckFailure.failed("The engine CLI's process --mode declares no choices= list.")
    }
    let body = tail[choicesStart.upperBound..<choicesEnd.lowerBound]
    let values = body
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"'")) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw CheckFailure.failed("The engine CLI's process --mode choices list parsed empty.")
    }
    return Set(values)
}

do {
    let root = URL(fileURLWithPath: "/tmp/voiceflow-project")
    let defaults = try VoiceFlowConfiguration.parse(
        arguments: [],
        currentDirectory: root
    )
    try check(defaults.projectRoot == root, "Default project root is incorrect.")
    try check(
        defaults.whisperModel.path == "/tmp/voiceflow-project/models/ggml-large-v3-turbo.bin",
        "Default model path is incorrect."
    )
    try check(defaults.cleaner == .apple, "Default cleaner is incorrect.")
    try check(defaults.language == .auto, "Default language is incorrect.")
    try check(defaults.shortcut.displayName == "Fn/Globe", "Default shortcut is incorrect.")
    try check(defaults.shortcut.keyCode == nil, "Fn should be a modifier-only shortcut.")
    try check(defaults.acceptanceLog == nil, "Acceptance logging should be opt-in.")
    try check(
        chordReleaseRequired(isActive: true, modifiersStillMatch: false),
        "An active chord did not release when a modifier was lifted."
    )
    try check(
        !chordReleaseRequired(isActive: true, modifiersStillMatch: true),
        "A still-held chord released unexpectedly."
    )

    let explicit = try VoiceFlowConfiguration.parse(
        arguments: [
            "--project-root", "/tmp/project",
            "--whisper-model", "models/custom.bin",
            // Not literal: a rewriting mode with the literal cleaner is refused (D-23).
            "--cleaner", "gemini",
            "--mode", "translate",
            "--language", "es",
            "--shortcut", "command+shift+f8",
            "--acceptance-log", "user-data/results.jsonl",
        ],
        currentDirectory: URL(fileURLWithPath: "/tmp")
    )
    try check(explicit.projectRoot.path == "/tmp/project", "Explicit root is incorrect.")
    try check(
        explicit.whisperModel.path == "/tmp/project/models/custom.bin",
        "Explicit model path is incorrect."
    )
    try check(explicit.cleaner == .gemini, "Explicit cleaner is incorrect.")
    try check(explicit.mode == .translate, "Explicit mode is incorrect.")
    try check(explicit.language == .es, "Explicit language is incorrect.")
    try check(explicit.shortcut.displayName == "⇧⌘F8", "Explicit shortcut is incorrect.")
    try check(
        explicit.acceptanceLog?.path == "/tmp/project/user-data/results.jsonl",
        "Acceptance log path is incorrect."
    )

    do {
        _ = try Shortcut(specification: "control+option")
        throw CheckFailure.failed("A modifier-only shortcut was accepted.")
    } catch is ConfigurationError {
        // Expected.
    }

    do {
        _ = try Shortcut(specification: "control")
        throw CheckFailure.failed("An unsafe single modifier was accepted.")
    } catch is ConfigurationError {
        // Expected.
    }

    let invocation = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"]
    )
    try check(invocation.executableURL.path == "/usr/bin/env", "Engine executable is incorrect.")
    try check(invocation.currentDirectoryURL == root, "Engine working directory is incorrect.")
    try check(
        invocation.environment["PYTHONPATH"] == "/tmp/voiceflow-project/src",
        "Engine PYTHONPATH is incorrect."
    )
    try check(
        invocation.environment["PYTHONDONTWRITEBYTECODE"] == "1",
        "The engine may mutate signed Python resources with bytecode caches."
    )
    try check(
        invocation.environment["VOICEFLOW_DISABLE_KEYCHAIN_FALLBACK"] == "1",
        "The app did not disable the engine's independent keychain fallback."
    )
    try check(
        invocation.environment["PATH"]?.hasPrefix("/opt/homebrew/bin:/usr/local/bin:") == true,
        "Homebrew paths are missing."
    )
    try check(invocation.arguments.contains("--copy"), "Clipboard output is missing.")
    try check(
        invocation.standardInput == nil
            && !invocation.arguments.contains("--context-text-stdin"),
        "An ordinary dictation announced a selection it does not have."
    )

    try check(invocation.arguments.contains("--json"), "Structured engine output is missing.")
    try check(invocation.arguments.contains("/tmp/input.wav"), "Audio path is missing.")

    // The speech engine is named on every run, and Parakeet's run says where its model
    // and helper are: the engine must never fall back to a default the window hides.
    func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    try check(
        value(after: "--transcriber", in: invocation.arguments) == "whisper"
            && !invocation.arguments.contains("--parakeet-models"),
        "A Whisper run must name its engine and carry nothing of Parakeet's."
    )
    let parakeetRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"],
        speechEngine: .parakeet,
        parakeetHelperURL: URL(fileURLWithPath: "/tmp/App.app/Contents/MacOS/voiceflow-parakeet")
    )
    try check(
        value(after: "--transcriber", in: parakeetRun.arguments) == "parakeet"
            && value(after: "--parakeet-models", in: parakeetRun.arguments)
                == "/tmp/voiceflow-project/models/fluidaudio/parakeet-ultra"
            && value(after: "--parakeet-bin", in: parakeetRun.arguments)
                == "/tmp/App.app/Contents/MacOS/voiceflow-parakeet",
        "A Parakeet run must name its engine, its model directory and its helper."
    )
    try check(
        invocation.arguments.contains("--gemini-model"),
        "The Gemini model identifier is not passed to the engine."
    )
    try check(
        invocation.environment["VOICEFLOW_GEMINI_API_KEY"] == nil,
        "A local run must not carry a provider key."
    )

    // A cloud provider is selectable, names its own key variable, and is the only kind
    // of cleaner that may put a secret in the engine environment.
    try check(CleanerMode(rawValue: "gemini") == .gemini, "Gemini is not selectable.")
    try check(CleanerMode.gemini.isCloud, "Gemini must be treated as a cloud provider.")
    try check(CleanerMode(rawValue: "ollama") == nil, "Ollama was removed and must not be selectable.")
    try check(!CleanerMode.apple.isCloud, "Apple's on-device model must not be treated as a cloud provider.")
    try check(!CleanerMode.literal.isCloud, "Literal must not be treated as a cloud provider.")
    try check(
        CleanerMode.gemini.apiKeyVariable == "VOICEFLOW_GEMINI_API_KEY",
        "The Gemini key variable name is incorrect."
    )
    try check(
        ProviderCredentialEnvironment.variableName(for: "open-router")
            == "VOICEFLOW_OPEN_ROUTER_API_KEY",
        "A dashed provider name is incompatible with the Python credential reader."
    )
    try check(
        CleanerMode.gemini.apiKeySourceName == "Google AI Studio",
        "The Gemini credential source disclosure is missing."
    )
    try check(
        CleanerMode.allCases == [.literal, .apple, .gemini],
        "The engines shown in the window must be literal, Apple and Gemini, in that order."
    )

    let cloudRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"],
        cleaner: .gemini,
        providerAPIKey: "test-key"
    )
    try check(
        cloudRun.arguments.contains("gemini"),
        "The window's provider choice did not reach the engine."
    )
    try check(
        cloudRun.environment["VOICEFLOW_GEMINI_API_KEY"] == "test-key",
        "The Gemini key did not reach the engine environment."
    )
    try check(
        !cloudRun.arguments.contains("test-key"),
        "The key must never appear in the engine arguments."
    )

    let cloudRunWithoutKey = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"],
        cleaner: .gemini,
        providerAPIKey: ""
    )
    try check(
        cloudRunWithoutKey.environment["VOICEFLOW_GEMINI_API_KEY"] == nil,
        "An empty key must not be exported."
    )

    let inheritedSecretRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: [
            "PATH": "/usr/bin",
            "VOICEFLOW_GEMINI_API_KEY": "inherited-key",
            "VOICEFLOW_FUTURE_API_KEY": "future-key",
        ],
        cleaner: .gemini
    )
    try check(
        inheritedSecretRun.environment["VOICEFLOW_GEMINI_API_KEY"] == nil,
        "A cloud run must not inherit a provider key from its parent."
    )
    try check(
        inheritedSecretRun.environment["VOICEFLOW_FUTURE_API_KEY"] == nil,
        "A future provider key must not leak into an unrelated engine run."
    )

    let localRunWithKey = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"],
        cleaner: .apple,
        providerAPIKey: "test-key"
    )
    try check(
        localRunWithKey.environment["VOICEFLOW_GEMINI_API_KEY"] == nil,
        "A local cleaner must not receive a cloud key."
    )

    let bundledSource = URL(fileURLWithPath: "/tmp/signed-app/python/src")
    let bundledRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"],
        engineSourceRoot: bundledSource
    )
    try check(
        bundledRun.environment["PYTHONPATH"] == bundledSource.path,
        "A packaged app did not use its signed Python source."
    )

    // R4: terminals now receive synthesized paste per the owner's explicit approval on 2026-09-01.
    let terminalIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
    ]
    for termID in terminalIDs {
        try check(
            !PasteTarget.requiresClipboardDelivery(bundleIdentifier: termID),
            "\(termID) should receive a synthesized paste."
        )
        try check(
            PasteTarget.isTerminal(bundleIdentifier: termID),
            "\(termID) should be recognized as a terminal."
        )
    }
    try check(
        !PasteTarget.isTerminal(bundleIdentifier: "com.apple.Notes"),
        "Notes should not be classified as a terminal."
    )
    try check(
        !PasteTarget.isTerminal(bundleIdentifier: nil),
        "nil bundle ID should not be classified as a terminal."
    )
    try check(
        !PasteTarget.isTerminal(bundleIdentifier: ""),
        "empty bundle ID should not be classified as a terminal."
    )
    try check(
        PasteTarget.requiresClipboardDelivery(bundleIdentifier: nil),
        "An unidentifiable target must not receive a synthesized paste."
    )
    try check(
        PasteTarget.requiresClipboardDelivery(bundleIdentifier: ""),
        "An empty bundle identifier must not receive a synthesized paste."
    )
    try check(
        !PasteTarget.requiresClipboardDelivery(bundleIdentifier: "com.apple.Notes"),
        "An ordinary text application should receive the paste."
    )
    try check(
        !PasteTarget.requiresClipboardDelivery(bundleIdentifier: "com.microsoft.VSCode"),
        "VS Code should receive the paste."
    )

    // The window's model choice must reach the engine, or the picker is decoration.
    let pickedModel = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: [:],
        cleaner: .gemini,
        // Deliberately not the default, so the assertion below proves the choice won.
        geminiModel: .flash37,
        providerAPIKey: "test-key"
    )
    try check(
        pickedModel.arguments.contains("gemini-3.7-flash"),
        "The chosen cloud model did not reach the engine."
    )
    try check(
        !pickedModel.arguments.contains(GeminiModel.preferredDefault.rawValue),
        "The launch default overrode the speaker's chosen model."
    )
    let unpickedModel = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: [:],
        cleaner: .gemini
    )
    try check(
        unpickedModel.arguments.contains(defaults.geminiModel),
        "Without a choice the engine should use the configured model."
    )
    try check(
        GeminiModel(rawValue: defaults.geminiModel) != nil,
        "The configured default must be one of the models the window offers."
    )
    try check(
        GeminiModel.allCases.count == 3,
        "The window should offer the three measured models."
    )
    try check(
        Set(GeminiModel.fallbackOrder) == Set(GeminiModel.allCases),
        "The fallback order must cover exactly the models the window offers."
    )
    try check(
        GeminiModel.fallbackOrder.count == GeminiModel.allCases.count,
        "The fallback order must not repeat or drop a model."
    )
    try check(
        GeminiModel.fallbackOrder.first == GeminiModel.preferredDefault,
        "The default should be the most available model, which leads the fallback order."
    )

    // R4: the app must not synthesize a paste into its own window.
    try check(
        PasteTarget.requiresClipboardDelivery(bundleIdentifier: "dot.sanblue.voiceflow"),
        "VoiceFlow must not paste into itself."
    )
    // A rename must fail this build rather than silently reopen the hole.
    let bundleIdentifier = "dot.sanblue.voiceflow"
    try check(
        PasteTarget.clipboardOnlyBundleIdentifiers.contains(bundleIdentifier),
        "The excluded identifier drifted from the app's CFBundleIdentifier."
    )

    // History Tray and DictationRecord checks
    var historyStore = DictationHistoryStore()
    try check(historyStore.records.isEmpty, "Initial history store should be empty.")

    let record1 = DictationRecord(
        rawText: "hola esto es una prueba",
        personalizedText: "hola esto es una prueba",
        finalText: "Hola, esto es una prueba.",
        cleaner: "literal",
        mode: "clean",
        latencySeconds: 0.8
    )
    try check(record1.finalText == "Hola, esto es una prueba.", "DictationRecord finalText mismatch.")
    try check(record1.menuTitle.contains("CLEAN"), "DictationRecord clean mode tag missing.")
    try check(record1.menuPreview(maxLength: 10) == "Hola, esto…", "DictationRecord preview truncation incorrect.")

    let record2 = DictationRecord(
        rawText: "hola equipo",
        personalizedText: "hola equipo",
        finalText: "Hello team.",
        cleaner: "gemini",
        mode: "translate",
        model: "gemini-3.5-flash",
        latencySeconds: 1.5,
        didAutoPaste: true
    )
    try check(record2.menuTitle.contains("ES➔EN"), "DictationRecord translate mode tag missing.")

    historyStore.append(record1)
    historyStore.append(record2)
    try check(historyStore.records.count == 2, "History count should be 2.")
    try check(historyStore.records[0].id == record2.id, "Newest record should be at index 0.")

    // Test maxCapacity bounding (10 items maximum)
    for i in 3...15 {
        let rec = DictationRecord(
            rawText: "take \(i)",
            personalizedText: "take \(i)",
            finalText: "Take \(i).",
            cleaner: "literal",
            mode: "clean",
            latencySeconds: 0.5
        )
        historyStore.append(rec)
    }
    try check(historyStore.records.count == 10, "History store must cap at maxCapacity (10).")
    try check(historyStore.records[0].finalText == "Take 15.", "Latest item must be index 0.")
    try check(historyStore.records.last?.finalText == "Take 6.", "Oldest retained item must be Take 6.")

    // Test JSON Serialization / Deserialization
    guard let encodedData = historyStore.encode() else {
        throw CheckFailure.failed("Failed to encode DictationHistoryStore.")
    }
    guard let restoredStore = DictationHistoryStore.load(from: encodedData) else {
        throw CheckFailure.failed("Failed to decode DictationHistoryStore from JSON.")
    }
    try check(restoredStore.records.count == 10, "Restored history count mismatch.")
    try check(restoredStore.records == historyStore.records, "Restored records do not match original.")

    // Test clear
    historyStore.clear()
    try check(historyStore.records.isEmpty, "History clear failed.")

    // Voice Action Parser Checks (Bilingual: Spanish & English)
    let action1 = VoiceActionParser.parse(text: "busca en google amazon")
    try check(action1?.type == .googleSearch(query: "amazon"), "Google search ES parse failed.")

    let action2 = VoiceActionParser.parse(text: "search google for mechanical keyboard")
    try check(action2?.type == .googleSearch(query: "mechanical keyboard"), "Google search EN parse failed.")

    let action3 = VoiceActionParser.parse(text: "abre safari y busca amazon.")
    try check(action3?.type == .googleSearch(query: "amazon"), "Browser search ES parse failed.")

    let action4 = VoiceActionParser.parse(text: "open chrome and search macbook pro")
    try check(action4?.type == .googleSearch(query: "macbook pro"), "Browser search EN parse failed.")

    let action5 = VoiceActionParser.parse(text: "googlear swiftui tutorial")
    try check(action5?.type == .googleSearch(query: "swiftui tutorial"), "Google direct verb parse failed.")

    let action6 = VoiceActionParser.parse(text: "busca en youtube lofi music")
    try check(action6?.type == .youtubeSearch(query: "lofi music"), "YouTube search ES parse failed.")

    let action7 = VoiceActionParser.parse(text: "search youtube for steve jobs speech")
    try check(action7?.type == .youtubeSearch(query: "steve jobs speech"), "YouTube search EN parse failed.")

    let action8 = VoiceActionParser.parse(text: "busca en github whisper cpp")
    try check(action8?.type == .githubSearch(query: "whisper cpp"), "GitHub search ES parse failed.")

    let action9 = VoiceActionParser.parse(text: "search github for sanbluedot voice-flow")
    try check(action9?.type == .githubSearch(query: "sanbluedot voice-flow"), "GitHub search EN parse failed.")

    let action10 = VoiceActionParser.parse(text: "ir a apple.com")
    try check(action10?.type == .openURL(url: URL(string: "https://apple.com")!), "URL navigation ES parse failed.")

    let action11 = VoiceActionParser.parse(text: "open github.com")
    try check(action11?.type == .openURL(url: URL(string: "https://github.com")!), "URL navigation EN parse failed.")

    let action12 = VoiceActionParser.parse(text: "abre notas")
    try check(action12?.type == .openApp(appName: "Notes"), "App open Notes ES parse failed.")

    let action13 = VoiceActionParser.parse(text: "open terminal")
    try check(action13?.type == .openApp(appName: "Terminal"), "App open Terminal EN parse failed.")

    let action14 = VoiceActionParser.parse(text: "abre visual studio code")
    try check(action14?.type == .openApp(appName: "Visual Studio Code"), "App open VS Code parse failed.")

    let action15 = VoiceActionParser.parse(text: "launch spotify")
    try check(action15?.type == .openApp(appName: "Spotify"), "App open Spotify parse failed.")

    let action16 = VoiceActionParser.parse(text: "¿Abre notas?")
    try check(action16?.type == .openApp(appName: "Notes"), "Inverted punctuation open app failed.")

    let action17 = VoiceActionParser.parse(text: "¡Busca en google tutorial de C++!")
    try check(action17?.type == .googleSearch(query: "tutorial de C++"), "Inverted punctuation search failed.")

    let action18 = VoiceActionParser.parse(text: "«Abre el finder»")
    try check(action18?.type == .openApp(appName: "Finder"), "Quoted app open failed.")

    // Non-actions and conversational speech should return nil
    try check(VoiceActionParser.parse(text: "hoy es un gran dia para trabajar") == nil, "Regular speech misidentified as action.")
    try check(VoiceActionParser.parse(text: "hello team let's review the quarterly results") == nil, "Regular English speech misidentified as action.")
    try check(VoiceActionParser.parse(text: "Abre comillas y escribe la respuesta") == nil, "Conversational 'abre comillas' misidentified as action.")
    try check(VoiceActionParser.parse(text: "Abre una cuenta en Stripe") == nil, "Conversational 'abre una cuenta' misidentified as action.")
    try check(VoiceActionParser.parse(text: "Open a ticket for the authentication bug") == nil, "Conversational 'open a ticket' misidentified as action.")
    try check(VoiceActionParser.parse(text: "Start working on the design system") == nil, "Conversational 'start working' misidentified as action.")
    try check(VoiceActionParser.parse(text: "Google is releasing a new model today") == nil, "Conversational 'Google is' misidentified as action.")

    // Test DictationRecord menu formatting and edge cases
    let actionRecord = DictationRecord(
        rawText: "abre notas",
        personalizedText: "Abre notas",
        finalText: "Open App: Notes",
        cleaner: "literal",
        mode: "action",
        latencySeconds: 0.5
    )
    try check(actionRecord.menuTitle.contains("(ACTION)"), "Action record tag mismatch in menuTitle: \(actionRecord.menuTitle)")
    try check(actionRecord.menuPreview(maxLength: -1) == "…", "Negative maxLength preview failed: \(actionRecord.menuPreview(maxLength: -1))")

    // Test corrupted JSON loading
    try check(DictationHistoryStore.load(from: Data("corrupt json string".utf8)) == nil, "Corrupted JSON should fail gracefully.")

    // Test invalid mode CLI configuration error
    do {
        _ = try VoiceFlowConfiguration.parse(
            arguments: ["--mode", "invalid-mode-name"],
            currentDirectory: URL(fileURLWithPath: "/tmp")
        )
        try check(false, "Invalid mode should throw ConfigurationError.invalidMode.")
    } catch ConfigurationError.invalidMode(let val) {
        try check(val == "invalid-mode-name", "invalidMode payload mismatch.")
    } catch {
        try check(false, "Unexpected error thrown for invalid mode: \(error)")
    }

    // --- VoiceSnippetStore: the editor's store, not an expansion engine ---
    //
    // Expansion belongs to `snippets.py` alone. A second scan here, over text the engine
    // had already expanded, matched the payload of the first expansion and delivered a
    // string neither pass produces on its own. These checks cover what this type still
    // owns: editing, encoding, and refusing to lose a file it cannot read.
    let snippetStore = VoiceSnippetStore()
    let snip1 = snippetStore.add(trigger: "mi linkedin", expansion: "https://example.com/in/fixture-profile", description: "Profile link")
    _ = snippetStore.add(trigger: "mi linkedin corporativo", expansion: "https://linkedin.com/company/sanblue")
    _ = snippetStore.add(trigger: "mi correo", expansion: "user@example.com")
    _ = snippetStore.add(trigger: "precio oferta", expansion: "$100 USD")
    _ = snippetStore.add(trigger: "c++ library", expansion: "lib/libc++.dylib")
    _ = snippetStore.add(trigger: "mi dirección", expansion: "Quito, Ecuador")

    try check(snippetStore.snippets.count == 6, "Snippet store should contain 6 snippets.")
    try check(snippetStore.add(trigger: "   ", expansion: "   ") == nil, "Whitespace-only trigger/expansion should be rejected.")

    // Test encoding and decoding
    guard let snippetData = snippetStore.encode() else {
        throw CheckFailure.failed("Failed to encode snippet store.")
    }
    guard let decodedStore = VoiceSnippetStore.decode(from: snippetData) else {
        throw CheckFailure.failed("A store this process just encoded did not decode.")
    }
    try check(decodedStore.snippets.count == 6, "Decoded snippet store count mismatch.")

    // Test delete by trigger, delete by UUID, and clear
    try check(decodedStore.delete(trigger: "mi linkedin"), "Delete snippet by trigger should return true.")
    try check(!decodedStore.delete(trigger: "no existe"), "Delete non-existent snippet should return false.")
    if let targetId = snip1?.id {
        // snip1 ("mi linkedin") was already deleted above, so delete(id:) returns false
        try check(!decodedStore.delete(id: targetId), "Delete already removed snippet by id should return false.")
    }
    let snipToDelete = decodedStore.snippets[0]
    try check(decodedStore.delete(id: snipToDelete.id), "Delete by UUID should succeed.")
    decodedStore.clear()
    try check(decodedStore.snippets.isEmpty, "Clear should empty snippet store.")

    // A damaged store is preserved, reported, and never written over. Decoding it to an
    // empty store with no report is what let the next add from the window destroy the
    // speaker's real snippets.
    try check(
        VoiceSnippetStore.decode(from: Data("{ not json".utf8)) == nil,
        "A damaged payload decoded to a store instead of reporting failure."
    )

    let snippetFixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("voiceflow-snippet-checks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: snippetFixtureDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: snippetFixtureDirectory) }
    let snippetFixture = snippetFixtureDirectory.appendingPathComponent("snippets.local.json")

    try check(
        VoiceSnippetStore.loadReporting(from: snippetFixture).failure == nil,
        "A store that does not exist yet was reported as a failure."
    )

    try Data("{ not json".utf8).write(to: snippetFixture)
    let damaged = VoiceSnippetStore.loadReporting(from: snippetFixture)
    try check(damaged.failure != nil, "A damaged store loaded silently.")
    try check(damaged.store.snippets.isEmpty, "A damaged store returned snippets it could not read.")
    try check(
        !FileManager.default.fileExists(atPath: snippetFixture.path),
        "A damaged store was left in place, where the next save would overwrite it."
    )
    let preserved = try FileManager.default
        .contentsOfDirectory(atPath: snippetFixtureDirectory.path)
        .filter { $0.hasPrefix("snippets.local.json.corrupt-") }
    try check(preserved.count == 1, "The damaged store was not preserved under a dated name.")

    // A healthy store survives the round trip through the same locked path.
    let savedStore = VoiceSnippetStore()
    _ = savedStore.add(trigger: "mi correo", expansion: "user@example.com")
    savedStore.save(to: snippetFixture)
    let reloaded = VoiceSnippetStore.loadReporting(from: snippetFixture)
    try check(reloaded.failure == nil, "A store this process just wrote did not load.")
    try check(reloaded.store.snippets.count == 1, "A saved snippet did not survive the round trip.")
    try check(
        VoiceSnippetStore.lockURL(for: snippetFixture).lastPathComponent == ".snippets.local.json.lock",
        "The Swift lock sidecar does not match the name memory.py takes."
    )

    // D-40: the window and `vf snippet add` write the same file. An edit from the window
    // must keep what the engine added after the window loaded its list.
    let engineWrite = """
        {"schema_version": 1, "snippets": [
          {"trigger": "mi correo", "expansion": "user@example.com"},
          {"trigger": "mi firma", "expansion": "Added from the terminal"}
        ]}
        """
    try Data(engineWrite.utf8).write(to: snippetFixture)
    let afterWindowAdd = VoiceSnippetStore.edit(at: snippetFixture) {
        _ = $0.add(trigger: "mi web", expansion: "https://example.com")
    }
    let survivingTriggers = Set(VoiceSnippetStore.load(from: snippetFixture).snippets.map(\.trigger))
    try check(
        afterWindowAdd != nil && survivingTriggers == ["mi correo", "mi firma", "mi web"],
        "An edit from the window erased a snippet the engine added: \(survivingTriggers.sorted())."
    )
    try Data("{ not json".utf8).write(to: snippetFixture)
    try check(
        VoiceSnippetStore.edit(at: snippetFixture, { _ = $0.add(trigger: "x", expansion: "y") }) == nil,
        "An edit wrote over a store it could not read."
    )

    // Keeping dictated text on disk is opt-in. An ordinary run must not carry the
    // flag, and cloud cleanup alone must not add it: the store fills only when the
    // speaker turned the setting on.
    let ordinaryRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: [:]
    )
    try check(
        !ordinaryRun.arguments.contains("--distill"),
        "An ordinary dictation asked the engine to store the spoken text."
    )

    let cloudRunWithoutConsent = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: [:],
        cleaner: .gemini,
        providerAPIKey: "not-a-real-key-fixture"
    )
    try check(
        !cloudRunWithoutConsent.arguments.contains("--distill"),
        "Cloud cleanup by itself enabled distillation recording."
    )

    let consentedRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: [:],
        cleaner: .gemini,
        providerAPIKey: "not-a-real-key-fixture",
        recordDistillationPair: true
    )
    try check(
        consentedRun.arguments.contains("--distill"),
        "The distillation setting did not reach the engine."
    )
    try check(
        consentedRun.arguments.last == "--distill",
        "The distillation flag must be appended after the fixed argument list."
    )

    // --- Processing modes and the mode switch (Feature 9) ---

    // The engine's own vocabulary, read from `cli.py` rather than copied here. `--mode
    // actions` was sent verbatim once and argparse rejected the whole run, so every
    // dictation failed while ACTION was selected. A hand-kept duplicate of this list
    // would pass while the two drifted apart, so the check reads the real `choices=`.
    let engineModes = try enginesProcessModeChoices()
    try check(
        engineModes.contains("translate") && engineModes.contains("meeting"),
        "The engine CLI's mode list parsed as \(engineModes.sorted()), which is not the real list."
    )
    for mode in ProcessingMode.allCases {
        try check(
            engineModes.contains(mode.engineMode),
            "Mode \(mode.rawValue) maps to '\(mode.engineMode)', which the engine rejects."
        )
    }
    try check(
        ProcessingMode.actions.engineMode == "clean",
        "Voice actions are parsed in the app, so the engine should run an ordinary cleanup."
    )

    // R3c: exactly one mode looks for a spoken command.
    let parsingModes = ProcessingMode.allCases.filter(\.parsesVoiceActions)
    try check(
        parsingModes == [.actions],
        "Voice-action parsing is not confined to the ACTION mode: \(parsingModes)."
    )

    // The toggle visits every mode once and comes back.
    var visited: [ProcessingMode] = [.clean]
    var cursor = ProcessingMode.clean
    for _ in 1..<ProcessingMode.allCases.count {
        cursor = cursor.next
        visited.append(cursor)
    }
    try check(
        Set(visited).count == ProcessingMode.allCases.count,
        "Cycling the mode did not reach every mode."
    )
    try check(
        cursor.next == .clean,
        "Cycling past the last mode did not return to the first."
    )
    try check(
        Set(ProcessingMode.allCases.map(\.badgeName)).count == ProcessingMode.allCases.count,
        "Two modes share a badge, so the HUD cannot say which one is on."
    )

    try check(
        defaults.modeShortcut.displayName == "⌃⌥M",
        "Default mode shortcut is incorrect."
    )
    try check(
        defaults.modeShortcut.keyCode != nil,
        "The mode switch is a tap, so it needs a key and not modifiers alone."
    )
    try check(
        defaults.modeShortcut != defaults.shortcut,
        "The mode switch and the push-to-talk trigger are the same chord."
    )

    let customModeShortcut = try VoiceFlowConfiguration.parse(
        arguments: ["--mode-shortcut", "control+option+p"],
        currentDirectory: root
    )
    try check(
        customModeShortcut.modeShortcut.displayName == "⌃⌥P",
        "An explicit mode shortcut was not applied."
    )

    // D-23: a rewriting mode with the literal cleaner was refused by the engine after the
    // recording was spent. The press and the launch both read this rule now.
    for mode in ProcessingMode.allCases {
        for cleaner in CleanerMode.allCases {
            let refused = mode.refusal(with: cleaner) != nil
            try check(
                refused == (mode.needsRewritingCleaner && cleaner == .literal),
                "\(mode.rawValue) with \(cleaner.rawValue) was "
                    + (refused ? "refused although it can run." : "accepted although the engine refuses it.")
            )
        }
    }
    var literalTranslateRejected = false
    do {
        _ = try VoiceFlowConfiguration.parse(
            arguments: ["--cleaner", "literal", "--mode", "translate"],
            currentDirectory: root
        )
    } catch ConfigurationError.modeNeedsRewritingCleaner {
        literalTranslateRejected = true
    }
    try check(
        literalTranslateRejected,
        "--cleaner literal --mode translate was accepted, so every dictation would be refused after recording."
    )

    var conflictRejected = false
    do {
        _ = try VoiceFlowConfiguration.parse(
            arguments: ["--mode-shortcut", "fn"],
            currentDirectory: root
        )
    } catch ConfigurationError.shortcutConflict {
        conflictRejected = true
    }
    try check(
        conflictRejected,
        "A mode shortcut equal to the push-to-talk trigger was accepted."
    )

    // A modifier alone can only be held, and the mode switch is tapped. Accepting one
    // and dropping it later left the switch dead while the menu bar still named it.
    var modifierOnlyRejected = false
    do {
        _ = try VoiceFlowConfiguration.parse(
            arguments: ["--shortcut", "command+shift+f8", "--mode-shortcut", "fn"],
            currentDirectory: root
        )
    } catch ConfigurationError.modifierOnlyModeShortcut {
        modifierOnlyRejected = true
    }
    try check(
        modifierOnlyRejected,
        "A modifier-only mode shortcut was accepted instead of refused at launch."
    )

    let actionsRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: [:],
        mode: .actions
    )
    try check(
        !actionsRun.arguments.contains("actions"),
        "The engine was asked for a mode it does not define."
    )
    if let modeIndex = actionsRun.arguments.firstIndex(of: "--mode") {
        try check(
            actionsRun.arguments[modeIndex + 1] == "clean",
            "The ACTION mode did not run an ordinary cleanup in the engine."
        )
    } else {
        throw CheckFailure.failed("The engine run carries no --mode argument.")
    }

    // --- Spoken app names that are really websites ---
    //
    // The executor searches this Mac first, so an installed app always wins. The table
    // only catches a name with no app behind it, which used to fail the action and paste
    // the sentence instead.
    guard let youtubeAction = VoiceActionParser.parse(text: "abre youtube"),
          case .openApp(let youtubeName) = youtubeAction.type else {
        throw CheckFailure.failed("\"abre youtube\" no longer parses as an application name.")
    }
    try check(
        WebDestination.hasSite(forApplicationNamed: youtubeName),
        "\(youtubeName) has no site to fall back to, so \"abre youtube\" still fails."
    )
    try check(
        WebDestination.url(forApplicationNamed: "YOUTUBE")?.host == "www.youtube.com",
        "The site lookup is case-sensitive; the parser capitalizes what it returns."
    )

    // A name with a real application must never be diverted to a website.
    for installed in [
        "Spotify", "Safari", "Notes", "Terminal", "Mail", "Calculator",
        "Finder", "Messages", "Calendar", "Reminders", "Music", "Google Chrome",
        "System Settings", "Visual Studio Code",
    ] {
        try check(
            !WebDestination.hasSite(forApplicationNamed: installed),
            "\(installed) is an application; the site table must not claim it."
        )
    }

    for (name, site) in WebDestination.sites {
        try check(
            URL(string: site)?.scheme == "https",
            "The site for \(name) is not an https URL: \(site)."
        )
    }

    // The measured figures are dated, and the date is shown beside them. A number with
    // no date reads as today's ranking, and nothing in this app re-measures.
    try check(
        GeminiModel.measurementDate == "2026-08-31",
        "The displayed measurement date no longer matches the figures in measuredNote."
    )
    try check(
        GeminiModel.allCases.allSatisfy { !$0.measuredNote.isEmpty },
        "A model offers no measured figure to date."
    )

    // --- Logic lifted out of the executable target so a check can reach it ---
    //
    // `VoiceFlowMac` is an executable and cannot be imported, so anything decided there
    // is decided untested. These four rules moved to the library rather than staying
    // where nothing could read them.

    // The activity log's own category rule. A line naming a provider is about that
    // provider even when it also says the request failed.
    let logExpectations: [(String, LogCategory)] = [
        ("gemini is at capacity (503)", .gemini),
        ("cloud key verified for Gemini — cloud, text only", .gemini),
        ("provider: Local cleanup — Apple", .apple),
        ("whisper heard: hola", .stt),
        ("⚡ action: Open site: youtube.com", .action),
        ("no action recognized · dictated instead: \"hola\"", .action),
        ("added voice snippet [mi correo]", .snippet),
        ("pasted into Notes", .paste),
        ("snippets could not be read (the file is not a valid snippet store)", .snippet),
        ("mode switched to: actions", .system),
        ("recording started…", .system),
    ]
    for (message, expected) in logExpectations {
        let actual = LogCategory.inferred(from: message)
        try check(
            actual == expected,
            "\"\(message)\" was filed under \(actual.rawValue), not \(expected.rawValue)."
        )
    }
    // Whole words only: an ordinary sentence must not be filed under actions because it
    // happens to contain the letters.
    try check(
        LogCategory.inferred(from: "the transaction cleared") == .system,
        "A substring match filed an ordinary sentence under a category."
    )

    // What the floating capsule says. Every mode names itself while recording, and only
    // the action mode names no provider while processing.
    for mode in ProcessingMode.allCases {
        let recording = HUDBadge.recording(mode: mode)
        try check(recording.hasPrefix("ON AIR"), "The recording badge stopped saying ON AIR.")
        if mode != .clean {
            try check(
                recording.contains(mode.badgeName) || recording.contains("MEETING"),
                "\(mode.rawValue) does not name itself while recording: \(recording)."
            )
        }
    }
    try check(
        HUDBadge.processing(mode: .actions, cleanerName: "gemini") == "PARSING ACTION",
        "The action mode named a cleaner for work no cleaner does."
    )
    try check(
        HUDBadge.processing(mode: .clean, cleanerName: "gemini").contains("GEMINI"),
        "The processing badge no longer names the provider receiving the text."
    )
    try check(
        HUDBadge.shortModelName("gemini-3.6-flash") == "3.6",
        "The capsule's short model name is wrong."
    )

    // App context awareness resolution and context-aware HUD badges.
    let vscodeCtx = AppContext.resolve(bundleIdentifier: "com.microsoft.VSCode", localizedName: "Code")
    try check(vscodeCtx.shortName == "VSCODE" && vscodeCtx.category == .code, "VS Code failed to resolve to CODE category.")
    let cursorCtx = AppContext.resolve(bundleIdentifier: "com.todesktop.230313mzl4w4u92", localizedName: "Cursor")
    try check(cursorCtx.shortName == "CURSOR" && cursorCtx.category == .code, "Cursor failed to resolve to CODE category.")
    let terminalCtx = AppContext.resolve(bundleIdentifier: "com.apple.Terminal", localizedName: "Terminal")
    try check(terminalCtx.shortName == "TERMINAL" && terminalCtx.category == .code, "Terminal failed to resolve to CODE category.")
    let claudeCtx = AppContext.resolve(bundleIdentifier: "com.anthropic.claudefordesktop", localizedName: "Claude")
    try check(claudeCtx.shortName == "CLAUDE" && claudeCtx.category == .aiPrompt, "Claude desktop failed to resolve to PROMPT category.")
    let chatgptCtx = AppContext.resolve(bundleIdentifier: "com.openai.chat", localizedName: "ChatGPT")
    try check(chatgptCtx.shortName == "CHATGPT" && chatgptCtx.category == .aiPrompt, "ChatGPT failed to resolve to PROMPT category.")
    let slackCtx = AppContext.resolve(bundleIdentifier: "com.tinyspeck.slackmacgap", localizedName: "Slack")
    try check(slackCtx.shortName == "SLACK" && slackCtx.category == .chat, "Slack failed to resolve to CHAT category.")
    let mailCtx = AppContext.resolve(bundleIdentifier: "com.apple.mail", localizedName: "Mail")
    try check(mailCtx.shortName == "MAIL" && mailCtx.category == .document, "Mail failed to resolve to DOCS category.")
    let desktopCtx = AppContext.resolve(bundleIdentifier: nil, localizedName: nil)
    try check(desktopCtx.category == .general, "Nil bundle failed to default to general category.")

    try check(
        HUDBadge.recording(mode: .clean, context: vscodeCtx) == "ON AIR • VSCODE",
        "Clean mode in VS Code did not display ON AIR • VSCODE: \(HUDBadge.recording(mode: .clean, context: vscodeCtx))."
    )
    try check(
        HUDBadge.recording(mode: .translate, context: slackCtx) == "ES➔EN • SLACK",
        "Translate mode in Slack did not display ES➔EN • SLACK: \(HUDBadge.recording(mode: .translate, context: slackCtx))."
    )
    try check(
        HUDBadge.recording(mode: .clean, context: desktopCtx) == "ON AIR",
        "General desktop context modified standard ON AIR badge unexpectedly."
    )

    // An unlisted application falls back to its full localized name. The recording badge
    // is drawn with `fixedSize()`, so a long one does not truncate: it pushes the
    // wordmark out of the row. Measured budget is 24 characters, and `TRANSFORM • `
    // already spends 12 of them.
    let longNameCtx = AppContext.resolve(
        bundleIdentifier: "com.example.unlisted",
        localizedName: "Microsoft Outlook Preview"
    )
    try check(
        longNameCtx.shortName.count <= AppContext.shortNameLimit,
        "An unlisted application's short name exceeds what the capsule can draw: \(longNameCtx.shortName)."
    )
    try check(
        HUDBadge.recording(mode: .translate, context: longNameCtx).count <= 24,
        "The recording badge is wider than the row it is drawn in: \(HUDBadge.recording(mode: .translate, context: longNameCtx))."
    )

    // A dictation was filed in the history menu as CLEAN, because the label switch
    // never learned the mode it ran under.
    let modeLabelRecord = DictationRecord(
        rawText: "juan revisa el codigo hoy",
        personalizedText: "juan revisa el codigo hoy",
        finalText: "- [ ] Juan: revisar el código hoy",
        cleaner: "gemini",
        mode: ProcessingMode.meeting.rawValue,
        model: nil,
        latencySeconds: 1.0,
        usedFallback: false,
        didAutoPaste: true
    )
    try check(
        modeLabelRecord.menuTitle.contains("(NOTES)"),
        "A dictation is filed under another mode: \(modeLabelRecord.menuTitle)."
    )

    // The window must be able to hold what is drawn in it. Two places sized the capsule
    // and only one was updated by the redesign, so the window kept being resized back to
    // the previous design and clipped the new one by 17pt on every show. Nothing failed,
    // because both numbers were correct on the day they were written.
    try check(
        HUDLayout.panelWidth >= HUDLayout.contentWidth,
        "The HUD window is narrower than its content: \(HUDLayout.panelWidth) < \(HUDLayout.contentWidth)."
    )
    try check(
        HUDLayout.panelHeight >= HUDLayout.contentHeight,
        "The HUD window is shorter than its content: \(HUDLayout.panelHeight) < \(HUDLayout.contentHeight)."
    )

    // Escape has to work in the state a recording is actually in. Requiring no modifiers
    // at all meant it was accepted only while nothing was being recorded: the trigger is
    // `Fn`, so every key pressed during a recording carries `maskSecondaryFn`, and the
    // capsule advertised a way out for the whole window in which it could not be taken.
    let escape = ShortcutMatch.escapeKeyCode
    try check(
        ShortcutMatch.isCancel(keyCode: escape, flags: [], trigger: [.fn]),
        "A bare Escape no longer cancels."
    )
    try check(
        ShortcutMatch.isCancel(keyCode: escape, flags: [.maskSecondaryFn], trigger: [.fn]),
        "Escape does not cancel while the Fn trigger is held — the only state a recording is in."
    )
    try check(
        ShortcutMatch.isCancel(
            keyCode: escape,
            flags: [.maskControl, .maskAlternate],
            trigger: [.control, .option]
        ),
        "Escape does not cancel while a chord trigger is held."
    )
    try check(
        !ShortcutMatch.isCancel(keyCode: escape, flags: [.maskCommand], trigger: [.fn]),
        "Command-Escape was read as a cancellation; it belongs to another application."
    )
    try check(
        !ShortcutMatch.isCancel(keyCode: 8, flags: [.maskSecondaryFn], trigger: [.fn]),
        "A key that is not Escape cancelled the recording."
    )

    // The capsule's text has to fit the rows it is drawn in, and "it fits" is a
    // measurement or it is nothing. `design-system.md` quotes these figures; they are
    // computed here from the same layout constants and the same fonts the views use, so
    // the contract is checked rather than asserted. The numbers were previously taken
    // from throwaway scripts against an assumed row width — right arithmetic on a wrong
    // premise, which is how a clipped capsule measured as fitting.
    func width(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        (text as NSString).size(
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: weight)]
        ).width
    }

    let wordmark = width("sanblue", size: 10, weight: .bold) + width("dot", size: 7, weight: .heavy)
    // Row 1: on-air dot, its spacing, the minimum spacer, and the wordmark.
    let badgeBudget = HUDLayout.contentColumn - 7 - 5 - 4 - wordmark
    let widestBadge = HUDBadge.recording(
        mode: .translate,
        context: AppContext(
            bundleIdentifier: "com.example.unlisted",
            localizedName: "Twelve Chars",
            shortName: String(repeating: "M", count: AppContext.shortNameLimit),
            category: .code
        )
    )
    try check(
        width(widestBadge, size: 10, weight: .heavy) <= badgeBudget,
        "The widest recording badge overruns its row: \(width(widestBadge, size: 10, weight: .heavy)) > \(badgeBudget)."
    )

    // The mode strip divides the row evenly between every mode, so adding one narrows
    // all of them. The widest label has to survive that division.
    let modeCount = CGFloat(ProcessingMode.allCases.count)
    let perSegment = (HUDLayout.contentColumn - (modeCount - 1) * 3) / modeCount
    for mode in ProcessingMode.allCases {
        try check(
            width(mode.badgeName, size: 7, weight: .heavy) <= perSegment,
            "Mode segment \(mode.badgeName) overruns its \(perSegment)pt share of the strip."
        )
    }

    // The order a spoken application name is looked for.
    let searched = ApplicationSearch.candidatePaths(for: "Notes", home: "/Users/fixture")
    try check(
        searched.first == "/Applications/Notes.app",
        "The application search no longer starts in /Applications."
    )
    try check(
        searched.contains("/System/Applications/Notes.app"),
        "The application search skips the system applications directory."
    )
    try check(
        searched.contains("/System/Applications/Utilities/Notes.app"),
        "The application search skips Utilities, where Terminal lives."
    )
    try check(
        searched.contains("/Users/fixture/Applications/Notes.app"),
        "The application search skips the speaker's own Applications directory."
    )
    try check(
        ApplicationSearch.candidatePaths(for: "youtube", home: "/Users/fixture")
            .contains("/Applications/Youtube.app"),
        "A lowercase spoken name is not also tried capitalized."
    )
    try check(
        searched.allSatisfy { $0.hasSuffix(".app") },
        "The application search produced a path that is not a bundle."
    )

    // --- The engine information sheet ---
    //
    // A panel built to help someone choose is the worst place for a number nobody
    // measured. R9 applies hardest here: an invented latency would make the decision.
    for cleaner in CleanerMode.allCases {
        let facts = cleaner.facts
        try check(!facts.isEmpty, "\(cleaner.rawValue) offers no facts to decide on.")
        try check(
            facts.contains { $0.label == "PRIVACY" },
            "\(cleaner.rawValue) does not say whether the text leaves this Mac."
        )
        try check(
            !cleaner.recommendation.isEmpty,
            "\(cleaner.rawValue) offers no recommendation."
        )
        try check(
            facts.allSatisfy { !$0.value.isEmpty && !$0.label.isEmpty },
            "\(cleaner.rawValue) has an empty fact."
        )
    }

    // A cloud engine must disclose that the text leaves the machine; a local one must
    // not claim it does.
    for cleaner in CleanerMode.allCases {
        let privacy = cleaner.facts.first { $0.label == "PRIVACY" }?.value ?? ""
        if cleaner.isCloud {
            try check(
                privacy.lowercased().contains("leaves this mac"),
                "\(cleaner.rawValue) is a cloud provider and does not say the text leaves."
            )
        } else {
            try check(
                privacy.lowercased().contains("nothing leaves this mac"),
                "\(cleaner.rawValue) runs locally and does not say so plainly."
            )
        }
    }

    // Every figure carries its date, and an engine with no measurement states none.
    try check(
        CleanerMode.gemini.factsMeasuredOn == "2026-08-31",
        "The cloud figures lost the date they were measured on."
    )
    // A date exists exactly when figures do, and a latency may be stated only by an
    // engine that was measured. Until 2026-09-18 this was written as "no local engine
    // has figures", which was true then and became a false rule the moment the two
    // local engines faced the same corpus the cloud one had faced.
    for cleaner in CleanerMode.allCases {
        let measured = cleaner.corpusNote != nil || cleaner.isCloud
        try check(
            (cleaner.factsMeasuredOn != nil) == measured,
            "\(cleaner.rawValue) disagrees with itself about whether it has been measured."
        )
        if !measured {
            try check(
                !cleaner.facts.contains { $0.value.contains("s median") },
                "\(cleaner.rawValue) states a latency nothing measured."
            )
        }
    }

    // --- The hold delay before the microphone opens ---
    try check(
        defaults.holdDelaySeconds == 0.5,
        "The default hold delay changed; the microphone opens at a different moment."
    )
    try check(
        defaults.holdDelaySeconds > 0,
        "A zero hold delay opens the microphone on a brush against the trigger."
    )
    let slowHold = try VoiceFlowConfiguration.parse(
        arguments: ["--hold-delay", "1.5"],
        currentDirectory: root
    )
    try check(slowHold.holdDelaySeconds == 1.5, "An explicit hold delay was not applied.")

    for rejected in ["-1", "4", "abc", ""] {
        var refused = false
        do {
            _ = try VoiceFlowConfiguration.parse(
                arguments: ["--hold-delay", rejected],
                currentDirectory: root
            )
        } catch ConfigurationError.invalidHoldDelay {
            refused = true
        }
        try check(refused, "A hold delay of \"\(rejected)\" was accepted.")
    }

    // The line speech recognition now writes must reach the MIC/STT filter, and the
    // fallback line must reach the errors filter rather than hiding among routine ones.
    try check(
        LogCategory.inferred(from: "whisper heard: \"hola mundo\"") == .stt,
        "The per-dictation recognition line does not reach the MIC/STT filter."
    )
    try check(
        LogCategory.inferred(from: "fallback · the provider did not answer · the transcript was delivered instead") == .warn,
        "A fallback line does not reach the errors filter."
    )
    try check(
        LogCategory.inferred(from: "fallback · the cleanup changed too much to verify") == .warn,
        "A guard rejection does not reach the errors filter."
    )

    // No colour outside the token declaration. The palette drifts by copy, not by
    // decision, and every copy so far had the right value on the day it was written.
    for (name, body) in try interfaceSourcesWithoutTokenDeclarations() {
        for spelling in ["Color(red:", "NSColor(red:", "Color(hue:", "Color(white:"] {
            try check(
                !body.contains(spelling),
                "\(name) writes a colour as a literal. Declare it in VoiceStationTokens "
                    + "and reference the token, so the palette moves in one place."
            )
        }
        // The system's adaptive colours are the bug design-system.md opens with:
        // `Color.green` changed the ready state with the viewer's macOS settings, and a
        // guard that only looked for RGB literals would not have seen it.
        for adaptive in [
            "Color.green", "Color.red", "Color.blue", "Color.orange", "Color.yellow",
            "Color.purple", "Color.pink", "Color.mint", "Color.teal", "Color.indigo",
            "Color.brown", "Color.cyan", "Color.accentColor",
        ] {
            try check(
                !body.contains(adaptive),
                "\(name) uses \(adaptive), which follows the viewer's system settings "
                    + "rather than this interface's palette. Use a VoiceStationTokens value."
            )
        }
    }

    // A refusal the speaker cannot hear.
    //
    // R3c asks for two things when a switch is pressed mid-run: the switch is refused,
    // and the refusal is reported. `guard viewModel.isSelectionEnabled else { return }`
    // does the first and drops the second, which leaves a live button that answers a
    // press with nothing — indistinguishable, from the speaker's side, from a break.
    // Every such guard must now carry a `reportRefusal` before it returns.
    for (name, body) in try interfaceSourcesWithoutTokenDeclarations() {
        try check(
            !body.contains("isSelectionEnabled else { return }"),
            "\(name) refuses a selection in silence. Report the refusal with "
                + "viewModel.reportRefusal(_:) before returning, as R3c requires."
        )
    }

    // A count nobody can read.
    //
    // ChassisCount draws a bare number. On screen the chassis title beside it says what
    // is being counted; read aloud the badge arrives alone, so the noun travels with it.
    for (name, body) in try interfaceSourcesWithoutTokenDeclarations() {
        var searched = Substring(body)
        while let call = searched.range(of: "ChassisCount(") {
            let rest = searched[call.upperBound...]
            guard let close = rest.firstIndex(of: ")") else { break }
            try check(
                rest[..<close].contains("noun:"),
                "\(name) builds a ChassisCount without a noun. A number read on its own "
                    + "counts nothing; name what it counts."
            )
            searched = rest[close...]
        }
    }

    // The interface must decline exactly the pairings the engine declines.
    //
    // The refusal shipped in the engine first, for `transform` alone, and the tiles went
    // on offering every mode with every cleaner: the speaker spent a recording to be told
    // no. Both sides now answer from one rule, and this check reads the engine's own list
    // rather than a second copy of it.
    let engineRewriting = try enginesRewritingModes()
    let swiftRewriting = Set(
        ProcessingMode.allCases.filter { $0.needsRewritingCleaner }.map { $0.engineMode }
    )
    try check(
        swiftRewriting == engineRewriting,
        "The modes needing a rewriting cleaner disagree: the engine refuses "
            + "\(engineRewriting.sorted()), the interface declines \(swiftRewriting.sorted())."
    )
    try check(
        !ProcessingMode.clean.needsRewritingCleaner && !ProcessingMode.actions.needsRewritingCleaner,
        "clean or actions was marked as needing a rewriting cleaner. clean is the default "
            + "pairing and actions reaches the engine as clean, so the refusal would stop "
            + "ordinary dictation."
    )

    // Apple's helper is found by path, never by PATH.
    //
    // The engine runs a binary that lives inside the signed bundle, where nothing the
    // child searches would find it. A run that selects this engine and does not carry
    // the path reaches the engine's own default and fails on a Mac that has the model.
    let appleRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"],
        cleaner: .apple,
        appleCleanerURL: URL(fileURLWithPath: "/Apps/VoiceFlow.app/Contents/MacOS/voiceflow-apple-cleaner")
    )
    try check(
        appleRun.arguments.contains("--apple-bin"),
        "An Apple cleanup run does not tell the engine where the helper is."
    )
    try check(
        appleRun.arguments.contains("/Apps/VoiceFlow.app/Contents/MacOS/voiceflow-apple-cleaner"),
        "The Apple helper path did not reach the engine's arguments."
    )
    try check(
        appleRun.environment["VOICEFLOW_APPLE_API_KEY"] == nil,
        "A local engine was handed a credential it has no use for."
    )

    let localRun = EngineInvocation.make(
        configuration: defaults,
        audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
        baseEnvironment: ["PATH": "/usr/bin"],
        cleaner: .apple
    )
    try check(
        !localRun.arguments.contains("--apple-bin"),
        "A build with no helper still pointed the engine at one."
    )

    // framework.md R3d: a shortcut's text was written, not dictated, and nothing on
    // screen would say it was leaving this Mac.
    let shortcutRun = try EngineInvocation.makeTextRun(
        configuration: defaults,
        text: "hola mundo",
        mode: .clean,
        cleaner: .apple
    )
    try check(
        shortcutRun.arguments.contains("--no-memory"),
        "A shortcut's text run applies corrections and snippets meant for speech."
    )
    try check(
        shortcutRun.standardInput == "hola mundo" && !shortcutRun.arguments.contains("hola mundo"),
        "A shortcut's text must travel on standard input, never in the process arguments."
    )
    for cleaner in CleanerMode.allCases where cleaner.isCloud {
        var refused = false
        do {
            _ = try EngineInvocation.makeTextRun(
                configuration: defaults,
                text: "hola mundo",
                mode: .clean,
                cleaner: cleaner
            )
        } catch TextRunRefusal.cloudEngine(let named) {
            refused = named == cleaner
        }
        try check(
            refused,
            "A shortcut built a run that sends text to \(cleaner.shortName) with nothing on screen."
        )
    }

    // Words: the window asks the engine, which owns both stores and their locks.
    let learnRun = EngineInvocation.makeWordsRun(
        configuration: defaults,
        command: .learn(heard: "olama", intended: "Ollama", everywhere: true, source: .fix)
    )
    try check(
        Array(learnRun.arguments.dropFirst(3)) == [
            "correct", "--heard", "olama", "--intended", "Ollama", "--source", "fix", "--allow-global",
        ]
            && learnRun.standardInput == nil,
        "LEARN did not ask the engine to confirm the pair with its source and consent."
    )
    try check(
        !EngineInvocation.makeWordsRun(
            configuration: defaults,
            command: .learn(heard: "sun blue dot", intended: "sanblue", everywhere: false, source: .window)
        ).arguments.contains("--allow-global"),
        "A correction the speaker did not mark as everywhere was confirmed as everywhere."
    )
    let snapshotJSON = """
    {"vocabulary": ["UTEL", "Gim", "PowerShell"], "in_prompt": 2, "corrections": [
      {"heard": "chequeen", "intended": "checking", "confirmed_at": "2026-09-18T10:00:00+00:00", "source": "", "everywhere": true},
      {"heard": "sun blue dot", "intended": "sanblueᵈᵒᵗ", "confirmed_at": "2026-09-26T10:00:00+00:00", "source": "fix", "everywhere": false},
      {"heard": "olama", "intended": "Ollama", "confirmed_at": "2026-09-27T10:00:00+00:00", "source": "window", "everywhere": true}
    ]}
    """
    let snapshot = try JSONDecoder().decode(WordsSnapshot.self, from: Data(snapshotJSON.utf8))
    try check(
        snapshot.isRead("Gim") && !snapshot.isRead("PowerShell"),
        "A term past the prompt budget must read as unread, and one inside it as read."
    )
    try check(
        snapshot.corrections(filter: .all, search: "").map(\.heard)
            == ["olama", "sun blue dot", "chequeen"],
        "The Words list must show the newest correction first."
    )
    try check(
        snapshot.corrections(filter: .learnedFromFix, search: "").map(\.heard) == ["sun blue dot"]
            && snapshot.corrections(filter: .addedHere, search: "").map(\.heard) == ["olama"],
        "A Words filter showed a pair from the wrong source."
    )
    try check(
        snapshot.corrections(filter: .all, search: "SANBLUE").map(\.heard) == ["sun blue dot"]
            && snapshot.corrections(filter: .all, search: "chequeen").count == 1,
        "The Words search must match either side, ignoring case and accents."
    )
    try check(
        snapshot.corrections[1].confirmedDay == "26 Sept",
        "A correction's date must read as the day it was confirmed."
    )

    // A fix is kept in the row it came from. As a row of its own it duplicated the
    // dictation and, with ten slots, pushed a real one out of History.
    let dictated = DictationRecord(
        rawText: "manda el reporte el lunes no perdon el martes",
        personalizedText: "manda el reporte el lunes no perdon el martes",
        finalText: "Manda el reporte el lunes, no, perdón, el martes.",
        cleaner: "apple",
        mode: "clean",
        latencySeconds: 1.0
    )
    var fixStore = DictationHistoryStore(records: [dictated])
    try check(
        fixStore.attachFix("Manda el reporte el martes.", to: dictated.id)
            && fixStore.records.count == 1
            && fixStore.records[0].id == dictated.id
            && fixStore.records[0].currentText == "Manda el reporte el martes."
            && fixStore.records[0].finalText == dictated.finalText,
        "A fix must stay in its own row, keep the delivered text, and add no row."
    )
    try check(
        !fixStore.attachFix("x", to: UUID()),
        "A fix for a row History no longer holds must be reported, not stored."
    )
    try check(
        DictationRecord.sameWords("google.com", "Google.com.")
            && DictationRecord.sameWords("la reunion es hoy", "La reunión es hoy.")
            && !DictationRecord.sameWords("el lunes no el martes", "El martes."),
        "A fix that changes no word must read as nothing to correct, and only then."
    )
    // FIX applies the pair it teaches to the dictation it came from, the way the engine
    // applies a pair: whole words, any case, the replacement taking the case it replaces.
    try check(
        CorrectionApplication.apply(
            heard: "co-rational", intended: "core rationale",
            to: "Identify the co-rational behind the data."
        ) == "Identify the core rationale behind the data."
            && CorrectionApplication.apply(heard: "reporte", intended: "informe", to: "Reporte y reporte.")
                == "Informe y informe."
            && CorrectionApplication.apply(heard: "utel", intended: "Utel", to: "UTEL y utel")
                == "UTEL y Utel",
        "FIX must replace the heard words in that dictation, keeping the case they had."
    )
    try check(
        CorrectionApplication.apply(heard: "gim", intended: "Gim", to: "the gimbal is ready") == nil
            && CorrectionApplication.apply(heard: "mas", intended: "más", to: "Thomas llega") == nil
            && CorrectionApplication.apply(heard: "lunes", intended: "martes", to: "El viernes.") == nil,
        "FIX must not rewrite part of a longer word, and must report a pair it cannot find."
    )
    // FIX by editing the sentence: each run of changed words becomes a pair, and applying
    // the pairs to what was heard gives back exactly what the speaker wrote.
    let heardSentence = "creo que se multiplicaria todo por -1 y el el reporte sale mal"
    let editedSentences = [
        "creo que se multiplicaría todo por menos uno y el reporte sale bien",
        "creo que se multiplicaria todo multiplicado por -1 y el el reporte sale mal",
        "creo que se multiplicaria todo por -1 y el el informe sale mal",
    ]
    for edited in editedSentences {
        let pairs = CorrectionDiff.pairs(original: heardSentence, edited: edited, everywhere: false)
        var rebuilt = heardSentence
        for pair in pairs {
            rebuilt = CorrectionApplication.apply(heard: pair.heard, intended: pair.intended, to: rebuilt)
                ?? rebuilt
        }
        try check(
            rebuilt == edited && !pairs.isEmpty && pairs.allSatisfy { !$0.isOneWord },
            "An edited sentence must turn into pairs that rebuild it, none of them one word: \(edited)"
        )
    }
    try check(
        CorrectionDiff.pairs(original: "abre oyama ahora", edited: "abre Ollama ahora", everywhere: true)
            == [CorrectionPair(heard: "oyama", intended: "Ollama")]
            && CorrectionDiff.pairs(original: "abre oyama ahora", edited: "abre Ollama ahora", everywhere: false)
                == [CorrectionPair(heard: "abre oyama ahora", intended: "abre Ollama ahora")]
            && CorrectionDiff.pairs(original: "sin cambios", edited: "sin  cambios ", everywhere: false).isEmpty,
        "A one-word change is learned alone only when the speaker asked for it everywhere."
    )
    let legacyRecord = try JSONDecoder().decode(
        DictationRecord.self,
        from: try JSONEncoder().encode(dictated)
    )
    try check(
        legacyRecord.fixedText == nil && legacyRecord.currentText == dictated.finalText,
        "A record written before fixes existed must still decode and show its text."
    )

    print("VoiceFlowMacCore checks passed.")
} catch {
    FileHandle.standardError.write(Data("Check failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
