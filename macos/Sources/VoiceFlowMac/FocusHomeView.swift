import SwiftUI
import VoiceFlowMacCore

/// Navigation and presentation only. Capture, delivery, providers and personal stores
/// remain behind the station's existing callbacks.
struct FocusHomeView: View {
    @ObservedObject var viewModel: VoiceStationViewModel
    let signalChain: AnyView
    let controlCard: AnyView
    let providers: AnyView
    let console: AnyView
    let snippetsPanel: AnyView
    let historyPanel: AnyView
    let diagnosticsPanel: AnyView

    private enum Page: String, CaseIterable {
        // Declaration order is the sidebar's order: the station first, then what
        // configures it, then what it produced.
        case home = "Station"
        case settings = "Settings"
        case history = "History"
        case snippets = "Snippets"
        case modes = "Modes"
        case diagnostics = "Diagnostics"

        var symbol: String {
            switch self {
            case .home: return "house"
            case .history: return "clock.arrow.circlepath"
            case .modes: return "square.on.square"
            case .snippets: return "text.quote"
            case .settings: return "gearshape"
            case .diagnostics: return "waveform.path.ecg"
            }
        }
    }

    @State private var page: Page = .home
    private typealias T = VoiceStationTokens

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 16) {
                // Home names its own state: the READY badge, the CANCEL button beside it
                // and the console's status bar all sit inside the station, so a heading
                // here only pushed the signal chain down.
                // A held-back cleanup is drawn on Station and nowhere else. Repeating it
                // above every page put the same question on six screens, and pushed each
                // section's chassis down to make room for a card that belongs with the
                // controls that answer it.
                if let refusal = viewModel.refusalNotice { refusalBanner(refusal) }
                switch page {
                case .home:
                    stationDeck
                case .snippets:
                    snippetsPanel
                case .history:
                    historyPanel
                case .modes:
                    modesPanel
                case .settings:
                    settingsPanel
                case .diagnostics:
                    diagnosticsPanel
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundColor(T.navy)
        .background(T.appBg)
        // The existing console's shortcuts and tabs share one route with the sidebar.
        .onChange(of: viewModel.activeRightTab) { tab in
            guard page == .history || page == .snippets || page == .diagnostics else { return }
            switch tab {
            case .activityLog: page = .diagnostics
            case .historyTray: page = .history
            case .snippets: page = .snippets
            }
        }
    }

    /// A refusal, drawn on the page the press happened on.
    ///
    /// It sits above the page rather than inside one, because the presses it answers
    /// come from the sidebar and from the mode bank, which are not on the same screen.
    private func refusalBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "hand.raised.fill").font(.system(size: 11, weight: .bold))
            Text(message)
                .font(T.mono(size: 10.5, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.gold)
        .foregroundColor(T.navy)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(T.navy, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("VOICEFLOW")
                .font(T.mono(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundColor(T.navy)
                .padding(.horizontal, 12)
            VStack(spacing: 9) {
                ForEach(Page.allCases, id: \.self) { destination in
                    Button { navigate(to: destination) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: destination.symbol).frame(width: 16)
                            Text(destination.rawValue)
                            Spacer(minLength: 0)
                            if let count = count(for: destination) {
                                Text("\(count)").font(T.mono(size: 10))
                            }
                        }
                        .font(T.mono(size: 12, weight: page == destination ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 43)
                        .background(page == destination ? T.gold : T.panelHeader)
                        .foregroundColor(T.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(
                            page == destination ? T.navy : T.panelHeader, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .voiceFlowNoFocusRing()
                    .accessibilityLabel(accessibilityName(for: destination))
                    .accessibilityAddTraits(page == destination ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 9) {
                Label(viewModel.selectedCleaner.isCloud ? "CLOUD TEXT ON" : "LOCAL BY DEFAULT",
                      systemImage: viewModel.selectedCleaner.isCloud ? "cloud" : "lock.shield")
                    .font(T.mono(size: 10, weight: .bold))
                    .foregroundColor(T.navy)
                Text(viewModel.selectedCleaner.isCloud
                     ? "Audio stays on this Mac. Text is sent to Gemini when you dictate."
                     : "Audio stays on this Mac. Cloud text cleanup is off.")
                    .font(T.mono(size: 10))
                    .foregroundColor(T.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.navy.opacity(0.45)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 24)
        .frame(width: 184)
        .frame(maxHeight: .infinity)
        .background(T.panelHeader)
        .overlay(alignment: .trailing) { T.navy.frame(width: 2) }
    }

    /// Home is the station itself: the chain a dictation travels, the engine row, the
    /// control card and the console, all present at once rather than reached by scrolling.
    private var stationDeck: some View {
        VStack(spacing: 12) {
            signalChain
            providers

            GeometryReader { geo in
                let spacing: CGFloat = 16
                let availableWidth = max(0, geo.size.width - spacing)
                // 38 / 62, the owner's choice: the console carries the reading, the
                // control card only has to hold the capsule and the mode switch. The
                // floor keeps the two-by-two switch from squeezing at the minimum width.
                let leftWidth = min(
                    max(floor(availableWidth * 0.38), 320),
                    max(availableWidth - 320, 0)
                )
                HStack(alignment: .top, spacing: spacing) {
                    controlCard.frame(width: leftWidth, height: geo.size.height)
                    console.frame(width: availableWidth - leftWidth, height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            historyStrip
                .padding(.top, 8)
        }
    }

    private var historyStrip: some View {
        card(fill: T.panelHeader, padding: 9) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Keep your words within reach").font(T.mono(size: 12, weight: .bold))
                    Text("Recent text stays in History. Ordinary dictation audio is deleted.")
                        .font(T.mono(size: 11))
                }
                Spacer(minLength: 0)
                action("OPEN HISTORY") { navigate(to: .history) }
            }
        }
    }

    /// Modes and personal memory in one section: both answer the same question, which is
    /// what happens to what was just said. Engine selection is not here — it lives in
    /// Settings, so one control is not offered in two places.
    private var modesPanel: some View {
        PaperChassis(
            viewModel: viewModel,
            system: "MODES.SYS",
            subtitle: "DICTATION & MEMORY"
        ) {
            ChassisCount(value: ProcessingMode.allCases.count, noun: "modes")
        } content: {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose what your next dictation does")
                        .font(T.mono(size: 16, weight: .bold))
                    modeBank
                    ForEach(ProcessingMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.displayName).font(T.mono(size: 12, weight: .bold))
                            Text(modeDescription(mode))
                                .font(T.mono(size: 12))
                                .foregroundColor(T.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider().overlay(T.navy.opacity(0.25))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR MEMORY").font(T.mono(size: 11, weight: .bold))
                        Text("Vocabulary and confirmed corrections live in the engine commands. Nothing is learned from your edits, your screen or your keystrokes.")
                            .font(T.mono(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            action("VIEW HISTORY") { navigate(to: .history) }
                            action("EDIT SNIPPETS", fill: T.dotBlue) { navigate(to: .snippets) }
                        }
                    }

                    Text("Modes cannot change while a dictation is in flight.")
                        .font(T.mono(size: 11))
                        .foregroundColor(T.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
        }
    }

    /// Settings: the decisions, and a plain statement of what the app does with what it
    /// hears. The measurements moved out — those are evidence and belong in Diagnostics.
    private var settingsPanel: some View {
        PaperChassis(
            viewModel: viewModel,
            system: "SETTINGS.SYS",
            subtitle: "THIS COMPUTER"
        ) {
            EmptyView()
        } content: {
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: true) {
                    let wide = geo.size.width >= 720
                    if wide {
                        HStack(alignment: .top, spacing: 20) {
                            settingsControls.frame(maxWidth: .infinity, alignment: .leading)
                            settingsDisclosure.frame(width: 280)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsControls
                            settingsDisclosure
                        }
                    }
                }
            }
        }
    }

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ENGINE").font(T.mono(size: 11, weight: .bold))
                providers
            }

            // The key used to be the smallest thing on this page, inside the dark
            // telemetry strip. It is the one control that decides whether text leaves
            // the Mac, so it is a card of its own.
            // Three engines, then three models: the same shape for the same kind of
            // choice, so the second one reads as a continuation of the first.
            if viewModel.selectedCleaner.isCloud {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CLOUD MODEL").font(T.mono(size: 11, weight: .bold))
                    HStack(spacing: 10) {
                        ForEach(GeminiModel.allCases, id: \.self) { model in
                            enginePill(
                                title: "Gemini \(model.shortName) Flash",
                                detail: model.measuredNote,
                                isOn: viewModel.selectedGeminiModel == model
                            ) {
                                guard viewModel.isSelectionEnabled else {
                                    viewModel.reportRefusal(
                                        "this run keeps Gemini \(viewModel.selectedGeminiModel.shortName) Flash · the model changes once it is delivered")
                                    return
                                }
                                viewModel.selectedGeminiModel = model
                                viewModel.onGeminiModelSelect?(model)
                            }
                        }
                    }
                    // What the figures are, and what happens when the chosen model is
                    // the one that is busy. Both were on the console strip this card
                    // replaced, and neither is obvious from the buttons alone.
                    Text("Delivered / median, measured \(GeminiModel.measurementDate). Nothing re-measures, so read them as that day's figures.")
                        .font(T.mono(size: 10))
                        .foregroundColor(T.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If the model you picked is busy, VoiceFlow walks the rest in measured order — \(fallbackOrder) — and delivers the plain transcript if none of them answers.")
                        .font(T.mono(size: 10))
                        .foregroundColor(T.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("API KEY").font(T.mono(size: 11, weight: .bold))
                    HStack(spacing: 8) {
                        paperChip(
                            title: viewModel.hasKey ? "Key stored" : "Set key…",
                            detail: viewModel.hasKey ? "in the macOS keychain" : "required for Gemini",
                            isOn: viewModel.hasKey
                        ) {
                            viewModel.onSetAPIKey?(viewModel.selectedCleaner)
                        }
                        if viewModel.hasKey {
                            paperChip(title: "Remove", detail: nil, isOn: false) {
                                viewModel.onForgetAPIKey?(viewModel.selectedCleaner)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("SHORTCUT & PERMISSIONS").font(T.mono(size: 11, weight: .bold))
                Text("Hold \(viewModel.shortcutName) anywhere to dictate.")
                    .font(T.mono(size: 12))
                Text("The shortcut is shown here, not edited here. Permission changes are handled by macOS.")
                    .font(T.mono(size: 10))
                    .foregroundColor(T.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                permissionActions
            }
        }
    }

    /// What this Mac does with what it hears, in plain words rather than in a document.
    private var settingsDisclosure: some View {
        VStack(alignment: .leading, spacing: 18) {
            disclosureBlock(
                "Processing",
                viewModel.selectedCleaner.isCloud
                    ? "Speech recognition and your confirmed memory stay on this Mac. The transcript text — never the audio — is sent to Gemini for cleanup."
                    : "Speech recognition, cleanup and your confirmed memory all stay on this Mac. No cloud provider is connected.",
                chip: viewModel.selectedCleaner.isCloud ? "Cloud text" : "Local only"
            )
            disclosureBlock(
                "Recording audio",
                "Each recording is deleted after it is processed, and immediately if you cancel it.",
                chip: "Not retained"
            )
            disclosureBlock(
                "Recent dictations",
                "The last ten stay in this app's preferences on this Mac, so they survive a restart. Clear them from History at any time.",
                chip: "Last 10"
            )
        }
    }

    private func disclosureBlock(_ title: String, _ body: String, chip: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(T.mono(size: 12, weight: .bold))
            Text(body)
                .font(T.mono(size: 11))
                .foregroundColor(T.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(chip)
                .font(T.mono(size: 10, weight: .bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(T.inputCream)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(T.consoleBg.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Divider().overlay(T.navy.opacity(0.18))
        }
    }

    /// The order the engine actually walks when the chosen model reports capacity.
    private var fallbackOrder: String {
        GeminiModel.fallbackOrder
            .filter { $0 != viewModel.selectedGeminiModel }
            .map(\.shortName)
            .joined(separator: " → ")
    }

    /// A model option drawn like an engine option: same pill, same lamp, same weight.
    private func enginePill(
        title: String,
        detail: String,
        isOn: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 9) {
                Circle()
                    .fill(isOn ? T.ok : Color.clear)
                    .overlay(Circle().stroke(isOn ? T.ok : T.navy.opacity(0.45), lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(T.mono(size: 12, weight: .bold)).lineLimit(1)
                    Text(detail).font(T.mono(size: 9)).opacity(0.7).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? T.navy : T.inputCream)
            .foregroundColor(isOn ? T.panelBg : T.navy)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(T.navy, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
    }

    /// A chip on paper: gold when it is the one in use, outlined when it is not.
    private func paperChip(
        title: String,
        detail: String?,
        isOn: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? T.ok : T.navy.opacity(0.22))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(T.mono(size: 11, weight: .bold)).lineLimit(1)
                    if let detail {
                        Text(detail).font(T.mono(size: 9)).opacity(0.75).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn ? T.gold : T.inputCream)
            .foregroundColor(T.navy)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(T.consoleBg.opacity(isOn ? 0.5 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
        .disabled(!viewModel.isSelectionEnabled)
    }

    private var modeBank: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach(ProcessingMode.allCases, id: \.self) { mode in
                action(modeTitle(mode), fill: viewModel.selectedMode == mode ? T.gold : T.inputCream) {
                    // R3c: the switch is refused while a dictation is in flight, and the
                    // refusal is reported rather than silent. A disabled tile did the
                    // first half and skipped the second.
                    guard viewModel.isSelectionEnabled else {
                        viewModel.reportRefusal(
                            "this run keeps \(modeTitle(viewModel.selectedMode)) · the mode changes once it is delivered")
                        return
                    }
                    viewModel.selectedMode = mode
                    viewModel.onModeSelect?(mode)
                    viewModel.addLog("mode switched to: \(mode.rawValue)")
                }
                .accessibilityAddTraits(viewModel.selectedMode == mode ? .isSelected : [])
            }
        }
    }

    private var permissionActions: some View {
        HStack(spacing: 8) {
            action("INPUT MONITORING", fill: T.inputCream) { viewModel.onOpenInputMonitoring?() }
            action("ACCESSIBILITY", fill: T.inputCream) { viewModel.onOpenAccessibility?() }
            action("RECHECK") { viewModel.onRetryPermissions?() }
        }
        .disabled(!viewModel.isSelectionEnabled)
    }

    private func navigate(to destination: Page) {
        // The only navigation a run has ever needed to refuse is the one that would
        // unmount the microphone while a finger is still holding it: that button is
        // what delivers the release, and a release nobody delivers records forever.
        // Every other move — between pages, back to the station, during the cleanup
        // that follows the release — is safe, and used to be frozen with it.
        if viewModel.isRecording, page == .home, destination != .home {
            viewModel.reportRefusal(
                "still on the station: the capsule you are holding is the control that ends this dictation")
            return
        }
        page = destination
        switch destination {
        case .history: viewModel.activeRightTab = .historyTray
        case .snippets: viewModel.activeRightTab = .snippets
        case .diagnostics: viewModel.activeRightTab = .activityLog
        default: break
        }
    }

    /// What VoiceOver reads for a sidebar row.
    ///
    /// Three rows carry a trailing number. Read as the button's own label it arrives as
    /// a bare digit after a name — "History, 3" — which does not say three of what.
    private func accessibilityName(for destination: Page) -> String {
        guard let count = count(for: destination) else { return destination.rawValue }
        switch destination {
        case .history: return "\(destination.rawValue), \(count) dictations"
        case .snippets: return "\(destination.rawValue), \(count) snippets"
        case .modes: return "\(destination.rawValue), \(count) modes"
        default: return destination.rawValue
        }
    }

    private func count(for destination: Page) -> Int? {
        switch destination {
        case .history: return viewModel.recentDictations.count
        case .modes: return ProcessingMode.allCases.count
        case .snippets: return viewModel.snippets.count
        default: return nil
        }
    }

    private func card<Content: View>(
        fill: Color = T.panelBg,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(T.navy, lineWidth: 2))
            .retroExtrusion(radius: 15, offset: 5)
    }

    private func action(_ title: String, fill: Color = T.gold, ink: Color = T.navy,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(T.mono(size: 10, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 13)
                .frame(minHeight: 42)
                .background(fill).foregroundColor(ink)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.navy, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
    }

    private func modeTitle(_ mode: ProcessingMode) -> String {
        switch mode {
        case .clean: return "DICTATE"
        case .translate: return "ES → EN"
        case .meeting: return "NOTES"
        case .actions: return "ACTIONS"
        case .transform: return "TRANSFORM"
        }
    }

    private func modeDescription(_ mode: ProcessingMode) -> String {
        switch mode {
        case .clean: return "Dictate in your own language. The selected engine controls cleanup."
        case .translate: return "Translate Spanish or mixed speech into English. Choose a text-cleanup engine."
        case .meeting: return "Structure spoken notes into a summary and checklist. This is not meeting audio capture."
        case .actions: return "Explicitly interpret supported spoken actions, such as opening an app or searching."
        case .transform: return "Apply a spoken instruction to text selected in another app. Requires a text-cleanup engine; with Gemini, the selection is sent to the cloud."
        }
    }
}
