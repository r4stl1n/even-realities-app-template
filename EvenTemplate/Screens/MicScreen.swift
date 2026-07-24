import AVFoundation
import SwiftUI

struct MicScreen: View {
    @EnvironmentObject private var session: BluetoothSession

    @State private var enabled = false
    @State private var useGlassesMic = true
    @State private var frames = 0
    @State private var bytes = 0
    @State private var level: Double = 0
    @State private var error: String?

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
                    get: { useGlassesMic },
                    set: { setMic(enabled: enabled, useGlassesMic: $0) }
                ))
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
        }
        .onReceive(session.micPcm.collect(.byTime(DispatchQueue.main, .milliseconds(100)))) { events in
            guard enabled, !events.isEmpty else { return }
            frames += events.count
            bytes += events.reduce(0) { $0 + $1.pcm.count }
            if let last = events.last {
                level = rms(of: last.pcm)
            }
        }
        .onDisappear {
            // Release the mic when leaving the tab.
            if enabled {
                session.sdk.setMicState(enabled: false)
                enabled = false
                level = 0
            }
        }
    }

    private func setMic(enabled newEnabled: Bool, useGlassesMic newUseGlassesMic: Bool) {
        error = nil
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
