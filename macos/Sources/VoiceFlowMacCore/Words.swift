import Foundation

/// What the Words section asks of the engine.
public enum WordsCommand: Equatable, Sendable {
    case read
    /// Confirm a pair. `everywhere` is the second consent a single-word trigger needs.
    case learn(heard: String, intended: String, everywhere: Bool, source: CorrectionSource)
    case forget(heard: String)
    case addWord(String)
    case removeWord(String)

    public var arguments: [String] {
        switch self {
        case .read:
            return ["memory", "--json"]
        case .learn(let heard, let intended, let everywhere, let source):
            return ["correct", "--heard", heard, "--intended", intended, "--source", source.rawValue]
                + (everywhere ? ["--allow-global"] : [])
        case .forget(let heard):
            return ["forget", "--heard", heard]
        case .addWord(let term):
            return ["vocab", "add", "--term", term]
        case .removeWord(let term):
            return ["vocab", "remove", "--term", term]
        }
    }
}

/// Where a correction was confirmed. Mirrors `CORRECTION_SOURCES` in `memory.py`.
public enum CorrectionSource: String, Sendable {
    /// Taught from a History row's FIX.
    case fix
    /// Typed in the Words section.
    case window
}

/// One confirmed pair, as `vf memory --json` reports it.
public struct WordsCorrection: Decodable, Equatable, Identifiable, Sendable {
    public let heard: String
    public let intended: String
    public let confirmedAt: String
    /// "fix", "window", or empty for a pair stored from the terminal or before sources.
    public let source: String
    /// A single-word trigger, which rewrites that word wherever it is heard.
    public let everywhere: Bool

    public var id: String { heard.lowercased() }

    private enum CodingKeys: String, CodingKey {
        case heard, intended, source, everywhere
        case confirmedAt = "confirmed_at"
    }

    public init(heard: String, intended: String, confirmedAt: String, source: String, everywhere: Bool) {
        self.heard = heard
        self.intended = intended
        self.confirmedAt = confirmedAt
        self.source = source
        self.everywhere = everywhere
    }

    /// The day it was confirmed, as "18 Sept", or nil when the store kept no date.
    public var confirmedDay: String? {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: confirmedAt) else { return nil }
        let day = Calendar(identifier: .gregorian).component(.day, from: date)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "June", "July", "Aug", "Sept", "Oct", "Nov", "Dec"]
        let month = Calendar(identifier: .gregorian).component(.month, from: date)
        return "\(day) \(months[month - 1])"
    }
}

/// One confirmed pair applied to one delivered dictation.
///
/// FIX used to teach the next dictations and leave the one it was opened from wrong, so
/// pressing it fixed nothing the speaker could see. The pair is applied here the way
/// `apply_corrections` in `memory.py` applies it to a transcript: whole words only, in any
/// case, the replacement taking the case of what it replaces. Nil when the heard side is
/// not in the text, so the caller can say the row was left as it was.
public enum CorrectionApplication {
    public static func apply(heard: String, intended: String, to text: String) -> String? {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let intended = intended.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !intended.isEmpty else { return nil }
        // The boundary is dropped at an edge that is not a word character, where `\b`
        // would never match — the same rule as `_bounded_pattern`.
        let isWordCharacter: (Character?) -> Bool = { character in
            guard let character else { return false }
            return character.isLetter || character.isNumber || character == "_"
        }
        let pattern = (isWordCharacter(heard.first) ? "\\b" : "")
            + NSRegularExpression.escapedPattern(for: heard)
            + (isWordCharacter(heard.last) ? "\\b" : "")
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let source = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return nil }
        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let matched = source.substring(with: match.range)
            result.replaceCharacters(in: match.range, with: matchingCase(of: matched, intended))
        }
        return result as String
    }

    /// `_match_case` in `memory.py`: an all-caps match stays all caps, a capitalised one
    /// keeps its capital, anything else takes the replacement as written.
    private static func matchingCase(of matched: String, _ replacement: String) -> String {
        let isAllCaps = matched.count > 1
            && matched == matched.uppercased()
            && matched != matched.lowercased()
        if isAllCaps { return replacement.uppercased() }
        if let first = matched.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}

/// One heard → intended pair.
public struct CorrectionPair: Equatable, Sendable {
    public let heard: String
    public let intended: String

    public init(heard: String, intended: String) {
        self.heard = heard
        self.intended = intended
    }

    /// A one-word heard side rewrites that word wherever it is heard.
    public var isOneWord: Bool {
        heard.split(whereSeparator: \.isWhitespace).count == 1
    }
}

/// The pairs one edit of a dictation teaches.
///
/// The speaker fixes the sentence itself rather than typing both sides of a pair. Each run
/// of changed words becomes one pair. A run that only adds or only removes words takes the
/// words around it, because a pair needs both sides. A one-word change takes them too
/// unless the speaker asked for it everywhere, so fixing one "por" in one sentence never
/// rewrites every "por" they say.
public enum CorrectionDiff {
    public static func pairs(original: String, edited: String, everywhere: Bool) -> [CorrectionPair] {
        let old = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = edited.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !old.isEmpty, !new.isEmpty, old != new else { return [] }

        // Longest common subsequence, word by word.
        var common = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                common[i][j] = old[i] == new[j]
                    ? common[i + 1][j + 1] + 1
                    : max(common[i + 1][j], common[i][j + 1])
            }
        }

        // Walk it, collecting each run of words that differ as (old range, new range).
        var runs: [(Range<Int>, Range<Int>)] = []
        var i = 0, j = 0
        var runStart: (Int, Int)?
        func closeRun() {
            if let start = runStart {
                runs.append((start.0..<i, start.1..<j))
                runStart = nil
            }
        }
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i] == new[j] {
                closeRun()
                i += 1
                j += 1
                continue
            }
            if runStart == nil { runStart = (i, j) }
            if j < new.count, i == old.count || common[i][j + 1] >= common[i + 1][j] {
                j += 1
            } else {
                i += 1
            }
        }
        closeRun()

        return runs.compactMap { run in
            var (removed, added) = run
            let needsContext = removed.isEmpty || added.isEmpty
                || (removed.count == 1 && !everywhere)
            if needsContext {
                // The words on either side are unchanged in both versions, so the same
                // neighbour is added to both sides.
                if removed.lowerBound > 0 {
                    removed = (removed.lowerBound - 1)..<removed.upperBound
                    added = (added.lowerBound - 1)..<added.upperBound
                }
                if removed.upperBound < old.count {
                    removed = removed.lowerBound..<(removed.upperBound + 1)
                    added = added.lowerBound..<(added.upperBound + 1)
                }
            }
            guard !removed.isEmpty, !added.isEmpty else { return nil }
            return CorrectionPair(
                heard: old[removed].joined(separator: " "),
                intended: new[added].joined(separator: " ")
            )
        }
    }
}

/// Which corrections the Words list shows.
public enum WordsFilter: String, CaseIterable, Sendable {
    case all = "All"
    case learnedFromFix = "Learned from a fix"
    case addedHere = "Added here"
}

/// The vocabulary and corrections as the engine holds them right now.
public struct WordsSnapshot: Decodable, Equatable, Sendable {
    public let vocabulary: [String]
    /// How many terms, from the top, the engine reads before it listens.
    public let inPrompt: Int
    public let corrections: [WordsCorrection]

    private enum CodingKeys: String, CodingKey {
        case vocabulary, corrections
        case inPrompt = "in_prompt"
    }

    public init(vocabulary: [String], inPrompt: Int, corrections: [WordsCorrection]) {
        self.vocabulary = vocabulary
        self.inPrompt = inPrompt
        self.corrections = corrections
    }

    /// Whether Whisper reads this term before it listens, or it is stored and unread.
    public func isRead(_ term: String) -> Bool {
        guard let index = vocabulary.firstIndex(of: term) else { return false }
        return index < inPrompt
    }

    /// The corrections a filter and a search leave, newest first.
    public func corrections(filter: WordsFilter, search: String) -> [WordsCorrection] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return corrections.reversed().filter { item in
            switch filter {
            case .all: break
            case .learnedFromFix: guard item.source == CorrectionSource.fix.rawValue else { return false }
            case .addedHere: guard item.source == CorrectionSource.window.rawValue else { return false }
            }
            guard !needle.isEmpty else { return true }
            return [item.heard, item.intended].contains {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    .contains(needle)
            }
        }
    }
}
