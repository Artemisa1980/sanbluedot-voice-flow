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
    try check(defaults.cleaner == .literal, "Default cleaner is incorrect.")
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
            "--cleaner", "literal",
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
    try check(explicit.cleaner == .literal, "Explicit cleaner is incorrect.")
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
    try check(invocation.arguments.contains("--json"), "Structured engine output is missing.")
    try check(invocation.arguments.contains("/tmp/input.wav"), "Audio path is missing.")
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
    try check(!CleanerMode.ollama.isCloud, "Ollama must not be treated as a cloud provider.")
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
        CleanerMode.allCases.count == 3,
        "The provider list shown in the window is incomplete."
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
        cleaner: .ollama,
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

    print("VoiceFlowMacCore checks passed.")
} catch {
    FileHandle.standardError.write(Data("Check failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
