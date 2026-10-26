import AVFoundation
import Foundation
import VoiceFlowMacCore

enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case couldNotStart
    case notRecording
    case emptyRecording
    case temporaryAudioRetained(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "A recording is already active."
        case .couldNotStart: return "The microphone recording could not start."
        case .notRecording: return "No recording is active."
        case .emptyRecording: return "The recording did not contain audio."
        case .temporaryAudioRetained(let path):
            return "Privacy warning: a temporary recording could not be deleted at \(path)."
        }
    }
}

func removeTemporaryAudio(at url: URL) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else { return }
    do {
        try fileManager.removeItem(at: url)
    } catch {
        // Retry once in case an AVFoundation file handle closed a fraction late.
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    /// The take being written, so a sweep never deletes it.
    var liveTakeURL: URL? { outputURL }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func start() throws {
        guard recorder == nil else {
            throw AudioRecorderError.alreadyRecording
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(RecordingHygiene.temporaryAudioPrefix)\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            do {
                try removeTemporaryAudio(at: url)
            } catch {
                throw AudioRecorderError.temporaryAudioRetained(url.path)
            }
            throw error
        }
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            do {
                try removeTemporaryAudio(at: url)
            } catch {
                throw AudioRecorderError.temporaryAudioRetained(url.path)
            }
            throw AudioRecorderError.couldNotStart
        }

        self.recorder = recorder
        outputURL = url
    }

    /// Returns a normalized audio power level between 0.0 (silent) and 1.0 (peak).
    func currentAudioLevel() -> Float {
        guard let recorder, recorder.isRecording else { return 0.0 }
        recorder.updateMeters()
        let avgPower = recorder.averagePower(forChannel: 0)
        // A NaN level trapped where the meter converts it to a bar count (D-174).
        guard avgPower.isFinite else { return 0.0 }
        let minDb: Float = -50.0
        if avgPower < minDb { return 0.0 }
        if avgPower >= 0.0 { return 1.0 }
        return (avgPower - minDb) / (-minDb)
    }

    func stop() throws -> URL {
        guard let recorder, let outputURL else {
            throw AudioRecorderError.notRecording
        }

        recorder.stop()
        self.recorder = nil
        self.outputURL = nil

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        } catch {
            do {
                try removeTemporaryAudio(at: outputURL)
            } catch {
                throw AudioRecorderError.temporaryAudioRetained(outputURL.path)
            }
            throw error
        }
        let byteCount = attributes[.size] as? NSNumber
        guard byteCount?.intValue ?? 0 > 44 else {
            do {
                try removeTemporaryAudio(at: outputURL)
            } catch {
                throw AudioRecorderError.temporaryAudioRetained(outputURL.path)
            }
            throw AudioRecorderError.emptyRecording
        }
        return outputURL
    }
}
