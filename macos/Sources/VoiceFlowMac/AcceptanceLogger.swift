import Foundation

private struct AcceptanceRecord: Encodable {
    let sequence: Int
    let recordedAt: String
    let latencySeconds: TimeInterval
    let rawText: String
    let personalizedText: String
    let finalText: String
    let usedFallback: Bool
    let audioFile: String?

    private enum CodingKeys: String, CodingKey {
        case sequence
        case recordedAt = "recorded_at"
        case latencySeconds = "latency_seconds"
        case rawText = "raw_text"
        case personalizedText = "personalized_text"
        case finalText = "final_text"
        case usedFallback = "used_fallback"
        case audioFile = "audio_file"
    }
}

private struct SequenceOnly: Decodable {
    let sequence: Int
}

private enum AcceptanceLoggerError: LocalizedError {
    case invalidExistingRecord(Int)

    var errorDescription: String? {
        switch self {
        case .invalidExistingRecord(let line):
            return "The existing acceptance log is invalid at line \(line)."
        }
    }
}

final class AcceptanceLogger {
    private let outputURL: URL

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func append(result: EngineResult, latency: TimeInterval, audioURL: URL?) throws -> Int {
        let fileManager = FileManager.default
        let directory = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let sequence = try existingRecordCount() + 1
        let storedAudio = try audioURL.map {
            try storeAudio(from: $0, sequence: sequence)
        }
        var committed = false
        defer {
            if !committed, let storedAudio {
                let storedURL = directory.appendingPathComponent(storedAudio)
                try? fileManager.removeItem(at: storedURL)
            }
        }
        let record = AcceptanceRecord(
            sequence: sequence,
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            latencySeconds: latency,
            rawText: result.rawText,
            personalizedText: result.personalizedText,
            finalText: result.finalText,
            usedFallback: result.outcome == .safeFallback,
            audioFile: storedAudio
        )
        var data = try JSONEncoder().encode(record)
        data.append(Data("\n".utf8))

        var contents = Data()
        if fileManager.fileExists(atPath: outputURL.path) {
            contents = try Data(contentsOf: outputURL)
        }
        contents.append(data)
        try contents.write(to: outputURL, options: .atomic)
        committed = true
        return sequence
    }

    /// Keep the recording beside its result so a later run can replay the same audio.
    /// Only the opt-in acceptance mode reaches here; ordinary launches keep deleting.
    private func storeAudio(from source: URL, sequence: Int) throws -> String {
        let fileManager = FileManager.default
        // The folder is named after its own log. A shared "audio" folder let a second
        // run overwrite the first run's recordings, which destroyed one of them.
        let stem = outputURL.deletingPathExtension().lastPathComponent
        let folder = "\(stem)-audio"
        let directory = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = String(format: "%03d.wav", sequence)
        let destination = directory.appendingPathComponent(name)
        try fileManager.copyItem(at: source, to: destination)
        return "\(folder)/\(name)"
    }

    /// The highest sequence already written, not the number of lines.
    ///
    /// Counting breaks the moment a record is removed: the next take reuses a number
    /// that another record still points at, and its recording is overwritten. Reading
    /// the numbers themselves survives editing the log.
    private func existingRecordCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return 0
        }
        let contents = try String(contentsOf: outputURL, encoding: .utf8)
        let decoder = JSONDecoder()
        var highest = 0
        for (offset, line) in contents
            .split(whereSeparator: \Character.isNewline)
            .enumerated() {
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(SequenceOnly.self, from: data) else {
                throw AcceptanceLoggerError.invalidExistingRecord(offset + 1)
            }
            highest = max(highest, record.sequence)
        }
        return highest
    }
}
