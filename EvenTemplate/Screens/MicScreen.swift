import AVFoundation
import SwiftUI

struct MicScreen: View {
    @EnvironmentObject private var session: BluetoothSession

    @State private var enabled = false
    // Defaults to the phone mic: the glasses mic needs a live EvenHub page, and
    // the first enable after a connect can land while the dashboard still owns
    // the screen, which requires a second toggle to come up.
    @State private var useGlassesMic = false
    @State private var frames = 0
    @State private var bytes = 0
    @State private var level: Double = 0
    @State private var error: String?
    @State private var screenBusy = false

    @StateObject private var stt = SpeechTranscriber()

    var body: some View {
        Form {
            Section("Microphone") {
                Text("Streams 16 kHz mono PCM to the app. With \"glasses mic\" on, audio comes from the connected G1/G2 (LC3 over BLE, decoded natively); otherwise the phone microphone is used. The R1 ring has no microphone.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Toggle("Mic enabled", isOn: Binding(
                    get: { enabled },
                    set: { setMic(enabled: $0, useGlassesMic: useGlassesMic) }
                ))
                Toggle("Use glasses mic", isOn: Binding(
                    get: { useGlassesMic && session.glasses.connected },
                    set: { setMic(enabled: enabled, useGlassesMic: $0) }
                ))
                .disabled(!session.glasses.connected)
                if !session.glasses.connected {
                    // Without a connection there is no SGC to ask, so the mic
                    // silently falls back to the phone — which looks like the
                    // switch being ignored. Say so instead.
                    Text("Connect the glasses on the Devices tab to use their microphone. The phone mic is used until then.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: geometry.size.width * min(1, level * 3))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                Text("Frames received: \(frames)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Audio data: \(String(format: "%.1f", Double(bytes) / 1024)) KB")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            Section("Speech to text") {
                Text("Transcribes the mic stream above on-device — the same 16 kHz PCM, whether it comes from the glasses or the phone. Nothing is uploaded. Turn the mic on first.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Picker("Language", selection: $stt.localeIdentifier) {
                    ForEach(SpeechTranscriber.availableLocales, id: \.identifier) { locale in
                        Text(SpeechTranscriber.displayName(for: locale.identifier))
                            .tag(locale.identifier)
                    }
                }
                Toggle("Transcribe", isOn: Binding(
                    get: { stt.running },
                    set: { $0 ? stt.start() : stt.stop() }
                ))
                .disabled(!enabled)
                if !enabled {
                    Text("Enable the microphone to start transcribing.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if stt.running, stt.partial.isEmpty, stt.transcript.isEmpty {
                    Text("Listening…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if !stt.transcript.isEmpty {
                    Text(stt.transcript)
                }
                if !stt.partial.isEmpty {
                    // In-progress hypothesis — it can still be revised.
                    Text(stt.partial)
                        .foregroundColor(.secondary)
                }
                if !stt.transcript.isEmpty || !stt.partial.isEmpty {
                    Button("Clear transcript") { stt.clear() }
                }
                if let sttError = stt.error {
                    Text(sttError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .onReceive(session.micPcm.collect(.byTime(DispatchQueue.main, .milliseconds(100)))) { events in
            guard enabled, !events.isEmpty else { return }
            frames += events.count
            bytes += events.reduce(0) { $0 + $1.pcm.count }
            if let last = events.last {
                level = rms(of: last.pcm)
            }
            // Forward every frame in order — append() no-ops unless a
            // recognition session is running, so this needs no extra gating.
            for event in events {
                stt.append(event.pcm)
            }
        }
        .alert("Glasses screen is busy", isPresented: $screenBusy) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The glasses dashboard is on screen. Close it — look down, or wait for the dashboard auto-close — then turn the microphone on again. The glasses mic needs the display to be free.")
        }
        .onDisappear {
            // Release the mic when leaving the tab.
            stt.stop()
            if enabled {
                session.sdk.setMicState(enabled: false)
                enabled = false
                level = 0
            }
        }
    }

    private func setMic(enabled newEnabled: Bool, useGlassesMic newUseGlassesMic: Bool) {
        error = nil
        // The glasses mic lives inside our EvenHub page, and the firmware won't
        // create that page while the dashboard is up. Say so rather than letting
        // the enable silently fall back to the phone mic.
        if newEnabled, newUseGlassesMic, session.sdk.glassesScreenOccupied {
            screenBusy = true
            return
        }
        // Transcription has no audio source once the mic is off.
        if !newEnabled {
            stt.stop()
        }
        let apply = {
            session.sdk.setMicState(enabled: newEnabled, useGlassesMic: newUseGlassesMic)
            enabled = newEnabled
            useGlassesMic = newUseGlassesMic
            if newEnabled {
                frames = 0
                bytes = 0
                level = 0
            }
        }
        if newEnabled, !newUseGlassesMic {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        apply()
                    } else {
                        error = "Microphone permission is required for the phone mic."
                    }
                }
            }
        } else {
            apply()
        }
    }

    private func rms(of pcm: Data) -> Double {
        pcm.withUnsafeBytes { buffer in
            let samples = buffer.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }
            var sumSquares = 0.0
            for sample in samples {
                let value = Double(sample)
                sumSquares += value * value
            }
            return (sumSquares / Double(samples.count)).squareRoot() / 32768
        }
    }
}
