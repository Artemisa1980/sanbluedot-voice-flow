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
        case words = "Words"
        case diagnostics = "Diagnostics"

        var symbol: String {
            switch self {
            case .home: return "house"
            case .history: return "clock.arrow.circlepath"
            case .words: return "textformat"
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
                case .words:
                    wordsPanel
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
        // FIX on a History row, on either surface, opens Words with that dictation.
        .onChange(of: viewModel.pageRequest) { request in
            guard request != nil else { return }
            viewModel.pageRequest = nil
            navigate(to: .words)
        }
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

    /// Words: what the engine hears and what it should write, in one section.
    ///
    /// Corrections are the guide every engine shares — applied before any model sees the
    /// text — so they are taught and edited here, and FIX on a History row opens this
    /// page with that dictation. Vocabulary is what Whisper reads before it listens, and
    /// the modes sit beside them because all three answer what happens to what was said.
    private var wordsPanel: some View {
        PaperChassis(
            viewModel: viewModel,
            system: "WORDS.SYS",
            subtitle: "WHAT IT HEARS, WHAT IT WRITES"
        ) {
            if let count = viewModel.words?.corrections.count {
                ChassisCount(value: count, noun: "corrections")
            }
        } content: {
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        wordsTabs
                        if geo.size.width >= 820 {
                            HStack(alignment: .top, spacing: 16) {
                                wordsMain.frame(maxWidth: .infinity, alignment: .leading)
                                wordsSide.frame(width: 280)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                wordsMain
                                wordsSide
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
        }
    }

    private var wordsTabs: some View {
        HStack(spacing: 8) {
            ForEach(WordsTab.allCases, id: \.self) { tab in
                Button {
                    viewModel.wordsTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Text(wordsTabTitle(tab)).font(T.mono(size: 10, weight: .bold)).tracking(0.8)
                        if tab == .vocabulary {
                            Text("· what Whisper listens for")
                                .font(T.mono(size: 9))
                                .foregroundColor(viewModel.wordsTab == tab ? T.gold : T.textMuted)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(viewModel.wordsTab == tab ? T.navy : T.inputCream)
                    .foregroundColor(viewModel.wordsTab == tab ? T.inputCream : T.navy)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.navy, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .voiceFlowNoFocusRing()
                .accessibilityAddTraits(viewModel.wordsTab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { T.consoleBg.opacity(0.45).frame(height: 1) }
    }

    private func wordsTabTitle(_ tab: WordsTab) -> String {
        if tab == .corrections, let count = viewModel.words?.corrections.count {
            return "CORRECTIONS \(count)"
        }
        return tab.rawValue
    }

    @ViewBuilder
    private var wordsMain: some View {
        switch viewModel.wordsTab {
        case .corrections: correctionsTab
        case .vocabulary: vocabularyTab
        case .modes: modesTab
        }
    }

    // MARK: Corrections

    private var correctionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            teachCard
            if let notice = viewModel.wordsNotice {
                Text(notice)
                    .font(T.mono(size: 10.5, weight: .bold))
                    .foregroundColor(T.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                wordsLabel("SEARCH")
                TextField("heard or written", text: $viewModel.wordsSearch)
                    .textFieldStyle(.plain)
                    .font(T.mono(size: 11))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 220)
                    .background(T.inputCream)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.consoleBg.opacity(0.6), lineWidth: 1.5))
                Spacer(minLength: 8)
                ForEach(WordsFilter.allCases, id: \.self) { filter in
                    Button { viewModel.wordsFilter = filter } label: {
                        Text(filter.rawValue)
                            .font(T.mono(size: 9.5, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(viewModel.wordsFilter == filter ? T.navy : T.inputCream)
                            .foregroundColor(viewModel.wordsFilter == filter ? T.inputCream : T.navy)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(T.navy, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .voiceFlowNoFocusRing()
                    .accessibilityAddTraits(viewModel.wordsFilter == filter ? .isSelected : [])
                }
            }
            correctionsList
        }
    }

    private var teachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                wordsLabel(viewModel.editingHeard == nil ? "TEACH A CORRECTION" : "EDIT A CORRECTION")
                if let context = viewModel.teachContext {
                    wordsTag("FROM HISTORY · \(context.timeString)", fill: T.gold)
                }
                Spacer(minLength: 0)
            }
            if let context = viewModel.teachContext {
                sentenceFix(context)
            } else {
                typedPair
            }
            Toggle(isOn: $viewModel.teachEverywhere) {
                Text(viewModel.teachContext == nil
                     ? "One word: replace it wherever it is heard"
                     : "A one-word change: replace that word wherever it is heard")
                    .font(T.mono(size: 10.5))
                    .foregroundColor(T.textMuted)
            }
            .toggleStyle(.checkbox)
            if viewModel.editingHeard != nil || viewModel.teachContext != nil {
                wordsButton("CANCEL") {
                    viewModel.teachHeard = ""
                    viewModel.teachIntended = ""
                    viewModel.teachSentence = ""
                    viewModel.teachEverywhere = false
                    viewModel.teachContext = nil
                    viewModel.editingHeard = nil
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.inputCream)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.consoleBg.opacity(0.6), lineWidth: 1))
    }

    /// FIX from History: the speaker clicks into what the engine heard and corrects it in
    /// place. Each run of changed words becomes a pair, shown before LEARN stores it.
    private func sentenceFix(_ context: DictationRecord) -> some View {
        let pairs = CorrectionDiff.pairs(
            original: context.rawText,
            edited: viewModel.teachSentence,
            everywhere: viewModel.teachEverywhere
        )
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                wordsLabel("WHAT IT HEARD · CLICK AND CORRECT IT")
                TextField("", text: $viewModel.teachSentence, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(T.mono(size: 12))
                    .lineLimit(1...8)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(T.panelBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.consoleBg.opacity(0.6), lineWidth: 1.5))
            }
            HStack(alignment: .center, spacing: 10) {
                if pairs.isEmpty {
                    Text("Change the words it got wrong. Each change is learned, and fixed in that dictation.")
                        .font(T.mono(size: 10.5))
                        .foregroundColor(T.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        wordsLabel("WILL LEARN")
                        ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                            HStack(spacing: 8) {
                                Text(pair.heard)
                                    .font(T.mono(size: 11))
                                    .strikethrough(true, color: T.rec)
                                    .foregroundColor(T.textMuted)
                                Text("→").font(T.mono(size: 11)).foregroundColor(T.textMuted)
                                Text(pair.intended).font(T.mono(size: 11, weight: .bold))
                                if pair.isOneWord { wordsTag("EVERYWHERE", fill: T.panelBg) }
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                wordsButton("LEARN", primary: true) {
                    viewModel.onLearnCorrection?(
                        WordsLearnRequest(
                            pairs: pairs,
                            everywhere: viewModel.teachEverywhere,
                            source: .fix,
                            replacing: nil,
                            dictation: context.id
                        )
                    )
                }
                .disabled(pairs.isEmpty)
                .opacity(pairs.isEmpty ? 0.5 : 1)
            }
        }
    }

    /// A pair typed in the Words section, or one being edited from the list.
    private var typedPair: some View {
        let heard = viewModel.teachHeard.trimmingCharacters(in: .whitespacesAndNewlines)
        let intended = viewModel.teachIntended.trimmingCharacters(in: .whitespacesAndNewlines)
        // A one-word trigger rewrites that word everywhere, so the engine asks for a
        // second consent. The box is that consent. LEARN stays pressable without it and
        // says so: greyed out in silence, it read as FIX doing nothing, and most fixes
        // are one word.
        let oneWord = heard.split(whereSeparator: \.isWhitespace).count == 1
        let ready = !heard.isEmpty && !intended.isEmpty

        return HStack(alignment: .bottom, spacing: 10) {
            teachField("IT HEARD", placeholder: "e.g. Oyama", text: $viewModel.teachHeard)
            Text("→").font(T.mono(size: 12)).foregroundColor(T.textMuted).padding(.bottom, 8)
            teachField("IT SHOULD WRITE", placeholder: "e.g. Ollama", text: $viewModel.teachIntended)
            wordsButton("LEARN", primary: true) {
                guard !oneWord || viewModel.teachEverywhere else {
                    NSSound.beep()
                    viewModel.wordsNotice = "\"\(heard)\" is one word, so it will be replaced "
                        + "wherever it is heard. Tick \"One word: replace it wherever it is "
                        + "heard\" to confirm, then LEARN."
                    return
                }
                viewModel.onLearnCorrection?(
                    WordsLearnRequest(
                        pairs: [CorrectionPair(heard: heard, intended: intended)],
                        everywhere: oneWord && viewModel.teachEverywhere,
                        source: .window,
                        replacing: viewModel.editingHeard,
                        dictation: nil
                    )
                )
            }
            .disabled(!ready)
            .opacity(ready ? 1 : 0.5)
        }
    }

    private func teachField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            wordsLabel(label)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(T.mono(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(T.panelBg)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.consoleBg.opacity(0.6), lineWidth: 1.5))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var correctionsList: some View {
        if let snapshot = viewModel.words {
            let pairs = snapshot.corrections(filter: viewModel.wordsFilter, search: viewModel.wordsSearch)
            if pairs.isEmpty {
                Text(snapshot.corrections.isEmpty
                     ? "No corrections yet. Press FIX on a dictation in History, or teach one above."
                     : "No correction matches.")
                    .font(T.mono(size: 11))
                    .foregroundColor(T.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pairs.enumerated()), id: \.element.id) { index, pair in
                        correctionRow(pair)
                        if index < pairs.count - 1 {
                            T.consoleBg.opacity(0.45).frame(height: 1)
                        }
                    }
                }
                .background(T.inputCream)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.consoleBg.opacity(0.6), lineWidth: 1))
            }
        } else {
            Text("Reading your corrections…")
                .font(T.mono(size: 11))
                .foregroundColor(T.textMuted)
        }
    }

    private func correctionRow(_ pair: WordsCorrection) -> some View {
        HStack(spacing: 10) {
            Text(pair.heard)
                .font(T.mono(size: 11.5))
                .strikethrough(true, color: T.rec)
                .foregroundColor(T.textMuted)
            Text("→").font(T.mono(size: 11)).foregroundColor(T.textMuted)
            Text(pair.intended).font(T.mono(size: 11.5, weight: .bold))
            Spacer(minLength: 8)
            if pair.source == CorrectionSource.fix.rawValue { wordsTag("FIX", fill: T.dotBlue) }
            if pair.everywhere { wordsTag("EVERYWHERE", fill: T.panelBg) }
            if let day = pair.confirmedDay {
                Text(day).font(T.mono(size: 10)).foregroundColor(T.textMuted)
            }
            wordsButton("EDIT") {
                viewModel.teachHeard = pair.heard
                viewModel.teachIntended = pair.intended
                viewModel.teachEverywhere = pair.everywhere
                viewModel.teachContext = nil
                viewModel.editingHeard = pair.heard
                viewModel.wordsNotice = nil
            }
            wordsButton("DELETE") { viewModel.onForgetCorrection?(pair.heard) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Vocabulary

    private var vocabularyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                wordsLabel("ADD A WORD")
                HStack(spacing: 10) {
                    TextField("e.g. PowerShell, Gim", text: $viewModel.newWord)
                        .textFieldStyle(.plain)
                        .font(T.mono(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(T.panelBg)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.consoleBg.opacity(0.6), lineWidth: 1.5))
                    let word = viewModel.newWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    wordsButton("+ ADD", primary: true) { viewModel.onAddWord?(word) }
                        .disabled(word.isEmpty)
                        .opacity(word.isEmpty ? 0.5 : 1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.inputCream)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.consoleBg.opacity(0.6), lineWidth: 1))

            if let notice = viewModel.wordsNotice {
                Text(notice)
                    .font(T.mono(size: 10.5, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let snapshot = viewModel.words {
                vocabularyBudget(snapshot)
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.vocabulary.enumerated()), id: \.offset) { index, term in
                        let read = index < snapshot.inPrompt
                        HStack(spacing: 10) {
                            Text(term)
                                .font(T.mono(size: 11.5, weight: read ? .bold : .regular))
                                .foregroundColor(read ? T.navy : T.textMuted)
                            Spacer(minLength: 8)
                            wordsTag(read ? "READ" : "UNREAD", fill: read ? T.dotBlue : T.panelBg)
                            wordsButton("DELETE") { viewModel.onRemoveWord?(term) }
                            wordsButton("TO CORRECTION") {
                                viewModel.teachHeard = ""
                                viewModel.teachIntended = term
                                viewModel.teachEverywhere = false
                                viewModel.teachContext = nil
                                viewModel.editingHeard = nil
                                viewModel.wordsNotice = nil
                                viewModel.wordsTab = .corrections
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if index < snapshot.vocabulary.count - 1 {
                            T.consoleBg.opacity(0.45).frame(height: 1)
                        }
                    }
                }
                .background(T.inputCream)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.consoleBg.opacity(0.6), lineWidth: 1))
            } else {
                Text("Reading your vocabulary…").font(T.mono(size: 11)).foregroundColor(T.textMuted)
            }
        }
    }

    private func vocabularyBudget(_ snapshot: WordsSnapshot) -> some View {
        let total = snapshot.vocabulary.count
        let share = total == 0 ? 0 : CGFloat(snapshot.inPrompt) / CGFloat(total)
        return VStack(alignment: .leading, spacing: 7) {
            wordsLabel("WHAT WHISPER READS BEFORE IT LISTENS")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(T.panelBg)
                    RoundedRectangle(cornerRadius: 5).fill(T.ok).frame(width: geo.size.width * share)
                }
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(T.navy, lineWidth: 1.5))
            }
            .frame(height: 10)
            Text(snapshot.inPrompt >= total
                 ? "All \(total) words fit in what Whisper reads."
                 : "\(snapshot.inPrompt) of \(total) words fit in what Whisper reads. The rest are stored but unread, so a word added now changes nothing yet. A word it keeps getting wrong works today as a correction.")
                .font(T.mono(size: 11))
                .foregroundColor(T.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.inputCream)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.consoleBg.opacity(0.6), lineWidth: 1))
    }

    // MARK: Modes

    private var modesTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose what your next dictation does")
                .font(T.mono(size: 14, weight: .bold))
            modeBank
            ForEach(ProcessingMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.displayName).font(T.mono(size: 12, weight: .bold))
                    Text(modeDescription(mode))
                        .font(T.mono(size: 11.5))
                        .foregroundColor(T.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Modes cannot change while a dictation is in flight.")
                .font(T.mono(size: 11))
                .foregroundColor(T.textMuted)
        }
    }

    // MARK: Side panels

    private var wordsSide: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW IT WORKS").font(T.pixel(9)).padding(.bottom, 2)
                Text("The speech model writes what it heard. Every phrase on the heard side is swapped for what it should write before anything is pasted, on every engine.")
                    .font(T.mono(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Fastest way to add one: press FIX on a dictation in History. It opens here with what it heard.")
                    .font(T.mono(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.inputCream)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(T.navy, lineWidth: 2))

            VStack(alignment: .leading, spacing: 10) {
                Text("TAKE IT BACK OUT LOUD").font(T.pixel(9)).foregroundColor(T.gold)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(["borra eso", "me equivoqué", "no, mejor", "perdón, no", "scratch that", "sorry, no"], id: \.self) { cue in
                        Text(cue)
                            .font(T.mono(size: 9.5))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .overlay(Capsule().stroke(T.inputCream, lineWidth: 1))
                    }
                }
                (Text("\"a las tres, ") + Text("perdón, no,").strikethrough(true, color: T.rec) + Text(" a las cuatro\"\n→ ") + Text("\"a las cuatro\"").bold().foregroundColor(T.gold))
                    .font(T.mono(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Said in a CLEAN dictation, the part you took back is gone before it is pasted.")
                    .font(T.mono(size: 10))
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.navy)
            .foregroundColor(T.inputCream)
            .clipShape(RoundedRectangle(cornerRadius: 11))

            Text("Nothing is learned from your screen or your keys. A correction is kept only when you press LEARN.")
                .font(T.mono(size: 10))
                .foregroundColor(T.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Words pieces

    private func wordsLabel(_ title: String) -> some View {
        Text(title)
            .font(T.mono(size: 9, weight: .bold))
            .tracking(1.1)
            .foregroundColor(T.textMuted)
    }

    private func wordsTag(_ title: String, fill: Color) -> some View {
        Text(title)
            .font(T.mono(size: 8.5, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill)
            .foregroundColor(T.navy)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(T.navy, lineWidth: 1))
    }

    private func wordsButton(_ title: String, primary: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(T.mono(size: 9.5, weight: .bold))
                .tracking(0.6)
                .padding(.horizontal, 10)
                .padding(.vertical, primary ? 8 : 4)
                .background(primary ? T.gold : T.inputCream)
                .foregroundColor(T.navy)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(T.navy, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
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
            // What turns the recording into text, chosen before the cleanup that follows.
            VStack(alignment: .leading, spacing: 10) {
                Text("SPEECH").font(T.mono(size: 11, weight: .bold))
                HStack(spacing: 10) {
                    ForEach(SpeechEngine.allCases, id: \.self) { engine in
                        enginePill(
                            title: engine.shortName,
                            detail: engine.measuredNote,
                            isOn: viewModel.selectedSpeechEngine == engine
                        ) {
                            guard viewModel.isSelectionEnabled else {
                                viewModel.reportRefusal(
                                    "this run keeps \(viewModel.selectedSpeechEngine.shortName) · the speech engine changes once it is delivered")
                                return
                            }
                            viewModel.selectedSpeechEngine = engine
                            viewModel.onSpeechEngineSelect?(engine)
                        }
                    }
                }
                Text("Words wrong / engine time on your 19 recordings, measured \(SpeechEngine.measurementDate). Nothing re-measures, so read them as that day's figures.")
                    .font(T.mono(size: 10))
                    .foregroundColor(T.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Whisper reads your vocabulary before it listens. Parakeet reads none and writes its own punctuation, so with it CLEAN asks no engine: fillers go by rule. The engine below is asked only when you take words back, and for ES➔EN and NOTES. Your corrections apply to both.")
                    .font(T.mono(size: 10))
                    .foregroundColor(T.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("ENGINE").font(T.mono(size: 11, weight: .bold))
                providers
            }

            // A local engine has no model to choose and still has something to say.
            // Selecting Apple used to leave this page blank below the engine row, while
            // Gemini filled it: the same page answered one choice and ignored another.
            if let model = viewModel.selectedCleaner.localModelName {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LOCAL MODEL").font(T.mono(size: 11, weight: .bold))
                    Text(model)
                        .font(T.mono(size: 12, weight: .bold))
                        .foregroundColor(T.navy)
                    if let corpus = viewModel.selectedCleaner.corpusNote,
                       let day = viewModel.selectedCleaner.factsMeasuredOn {
                        Text("\(corpus), measured \(day). Nothing re-measures, so read them as that day's figures.")
                            .font(T.mono(size: 10))
                            .foregroundColor(T.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Cleanup that changes more than punctuation is refused by the output guard, and the refused text is offered on the station so you can read it and decide.")
                        .font(T.mono(size: 10))
                        .foregroundColor(T.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                    // The engine refuses this pairing, so selecting it here buys a failed
                    // dictation and a recording the speaker has to make twice. Declined
                    // where the choice is made, and out loud, as R3c asks.
                    if let refusal = mode.refusal(with: viewModel.selectedCleaner) {
                        viewModel.reportRefusal(refusal)
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
        case .words: viewModel.onRefreshWords?()
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
        case .words: return "\(destination.rawValue), \(count) corrections"
        default: return destination.rawValue
        }
    }

    private func count(for destination: Page) -> Int? {
        switch destination {
        case .history: return viewModel.recentDictations.count
        case .words: return viewModel.words?.corrections.count
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
        }
    }

    private func modeDescription(_ mode: ProcessingMode) -> String {
        switch mode {
        case .clean: return "Dictate in your own language. The selected engine controls cleanup."
        case .translate: return "Translate Spanish or mixed speech into English. Choose a text-cleanup engine."
        case .meeting: return "Structure spoken notes into a summary and checklist. This is not meeting audio capture."
        case .actions: return "Explicitly interpret supported spoken actions, such as opening an app or searching."
        }
    }
}
