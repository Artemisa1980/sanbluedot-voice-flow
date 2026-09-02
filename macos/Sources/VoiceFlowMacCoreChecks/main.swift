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

    // Test VoiceSnippetStore
    let snippetStore = VoiceSnippetStore()
    let snip1 = snippetStore.add(trigger: "mi linkedin", expansion: "https://example.com/in/fixture-profile", description: "Profile link")
    _ = snippetStore.add(trigger: "mi linkedin corporativo", expansion: "https://linkedin.com/company/sanblue")
    _ = snippetStore.add(trigger: "mi correo", expansion: "user@example.com")
    _ = snippetStore.add(trigger: "precio oferta", expansion: "$100 USD (código: \\g<1>)")
    _ = snippetStore.add(trigger: "c++ library", expansion: "lib/libc++.dylib")
    _ = snippetStore.add(trigger: "mi dirección", expansion: "Quito, Ecuador")

    try check(snippetStore.snippets.count == 6, "Snippet store should contain 6 snippets.")
    try check(snippetStore.add(trigger: "   ", expansion: "   ") == nil, "Whitespace-only trigger/expansion should be rejected.")

    // Test case-insensitive word-boundary and longest-match expansion
    let textToExpand = "Hola, visita Mi LinkedIn Corporativo o escríbeme a Mi Correo. El precio es precio oferta para c++ library en Mi Dirección."
    let expandedText = snippetStore.expand(text: textToExpand)
    let expectedText = "Hola, visita https://linkedin.com/company/sanblue o escríbeme a user@example.com. El precio es $100 USD (código: \\g<1>) para lib/libc++.dylib en Quito, Ecuador."
    try check(
        expandedText == expectedText,
        "Snippet expansion mismatch: expected [\(expectedText)], got [\(expandedText)]"
    )

    // Test word boundary protection: trigger "correo" must not match inside "anticorreo"
    _ = snippetStore.add(trigger: "correo", expansion: "CORREO_EXPANDED")
    let boundaryText = "Este es un mensaje anticorreo."
    try check(snippetStore.expand(text: boundaryText) == boundaryText, "Word boundary check failed for substring trigger.")

    // Test encoding and decoding
    guard let snippetData = snippetStore.encode() else {
        throw NSError(domain: "VoiceFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode snippet store."])
    }
    let decodedStore = VoiceSnippetStore.decode(from: snippetData)
    try check(decodedStore.snippets.count == 7, "Decoded snippet store count mismatch.")

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

    // Test non-cascading expansion: Snippet 1 expands "mi correo" -> "hello@example.dev", Snippet 2 expands "sanblue" -> "Sanblue LLC".
    let nonCascadeStore = VoiceSnippetStore()
    _ = nonCascadeStore.add(trigger: "mi correo", expansion: "hello@example.dev")
    _ = nonCascadeStore.add(trigger: "sanblue", expansion: "Sanblue LLC")
    let cascadeInput = "Escríbeme a mi correo o visita sanblue"
    let expectedNonCascade = "Escríbeme a hello@example.dev o visita Sanblue LLC"
    let nonCascadeResult = nonCascadeStore.expand(text: cascadeInput)
    try check(nonCascadeResult == expectedNonCascade, "Non-cascading snippet check failed: expected [\(expectedNonCascade)], got [\(nonCascadeResult)]")

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

    print("VoiceFlowMacCore checks passed.")
} catch {
    FileHandle.standardError.write(Data("Check failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
