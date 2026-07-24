import AVFoundation
import Combine
import Foundation
import Speech

/// On-device speech-to-text over the glasses/phone mic stream.
///
/// Feeds the 16 kHz mono PCM published by `BluetoothSession.micPcm` into
/// `SFSpeechRecognizer`. Recognition is pinned to on-device
/// (`requiresOnDeviceRecognition`) so audio never leaves the phone — the rest
/// of this app makes no network requests and STT shouldn't be the exception.
/// That does mean a device/locale without a downloaded model reports
/// unavailable rather than silently falling back to Apple's servers.
@MainActor
final class SpeechTranscriber: ObservableObject {
    /// Text confirmed by the recogniser, accumulated across utterances.
    @Published private(set) var transcript = ""
    /// The in-progress hypothesis for the current utterance.
    @Published private(set) var partial = ""
    @Published private(set) var running = false
    @Published private(set) var error: String?

    /// Whether this device can transcribe locally for the current locale.
    var onDeviceAvailable: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    /// Locale used for recognition. Changing it rebuilds the recogniser and
    /// restarts an in-flight session so the switch takes effect immediately.
    @Published var localeIdentifier: String {
        didSet {
            guard localeIdentifier != oldValue else { return }
            UserDefaults.standard.set(localeIdentifier, forKey: Self.localeDefaultsKey)
            let wasRunning = running
            stop()
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
            error = nil
            if wasRunning { start() }
        }
    }

    /// Locales the OS can recognise, newest-first by display name. Note this is
    /// the full supported set — whether a given one works *on-device* depends on
    /// the model being downloaded, which `onDeviceAvailable` reports.
    static let availableLocales: [Locale] = SFSpeechRecognizer.supportedLocales()
        .sorted {
            let name = Locale.current.localizedString(forIdentifier:)
            return (name($0.identifier) ?? $0.identifier)
                .localizedCaseInsensitiveCompare(name($1.identifier) ?? $1.identifier)
                == .orderedAscending
        }

    static func displayName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private static let localeDefaultsKey = "even_template_stt_locale"

    private var recognizer: SFSpeechRecognizer?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.localeDefaultsKey)
        let identifier = saved ?? Locale.current.identifier
        localeIdentifier = identifier
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
            ?? SFSpeechRecognizer()
    }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 16 kHz mono Int16 — the format the mic pipeline emits.
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(MicPcmEvent.sampleRate),
        channels: AVAudioChannelCount(MicPcmEvent.channels),
        interleaved: true
    )

    func start() {
        guard !running else { return }
        error = nil

        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition is unavailable on this device."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            error = "On-device speech recognition isn't available for this locale."
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginSession(recognizer)
                case .denied, .restricted:
                    self.error = "Speech recognition permission was denied."
                case .notDetermined:
                    self.error = "Speech recognition permission wasn't granted."
                @unknown default:
                    self.error = "Speech recognition is unavailable."
                }
            }
        }
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        running = false
        partial = ""
    }

    func clear() {
        transcript = ""
        partial = ""
    }

    /// Push one mic frame. No-op unless a session is running, so the caller can
    /// forward every frame without gating.
    func append(_ pcm: Data) {
        guard running, let request, let format, !pcm.isEmpty else { return }
        guard let buffer = Self.makeBuffer(from: pcm, format: format) else { return }
        request.append(buffer)
    }

    private func beginSession(_ recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.transcript = self.transcript.isEmpty
                            ? text
                            : self.transcript + " " + text
                        self.partial = ""
                    } else {
                        self.partial = text
                    }
                }
                // A cancel during stop() surfaces here too; don't report it.
                if let taskError, self.running {
                    self.error = taskError.localizedDescription
                    self.stop()
                }
            }
        }
        running = true
    }

    /// Wrap interleaved Int16 PCM in an `AVAudioPCMBuffer` for the recogniser.
    private static func makeBuffer(from pcm: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = pcm.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let channel = buffer.int16ChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        pcm.withUnsafeBytes { raw in
            if let base = raw.bindMemory(to: Int16.self).baseAddress {
                channel[0].update(from: base, count: frameCount)
            }
        }
        return buffer
    }
}
