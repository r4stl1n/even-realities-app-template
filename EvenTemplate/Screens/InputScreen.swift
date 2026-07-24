import SwiftUI

struct InputScreen: View {
    @EnvironmentObject private var session: BluetoothSession

    private struct LogEntry: Identifiable {
        let id: Int
        let time: String
        let text: String
    }

    private static let maxLogEntries = 50
    @State private var log: [LogEntry] = []
    @State private var nextId = 0

    var body: some View {
        Form {
            Section("Input events") {
                Text("Live feed of touchpad gestures from the glasses, gestures from the R1 ring, button presses, head-up state, and battery updates. Tap or swipe on a connected device to see events arrive.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button("Clear log") {
                    log = []
                }
                if log.isEmpty {
                    Text("No events yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(log) { entry in
                    Text("\(entry.time)  \(entry.text)")
                        .font(.footnote.monospaced())
                }
            }
        }
        .onReceive(session.events) { event in
            handle(event)
        }
    }

    private func handle(_ event: BluetoothEvent) {
        switch event {
        case let .touch(touch):
            append("touch \(touch.gestureName ?? "?") (\(touch.deviceModel ?? "?"))")
        case let .buttonPress(press):
            append("button \(press.buttonId) \(press.pressType)")
        case let .raw(name, values):
            switch name {
            case "head_up":
                if let up = values["up"] as? Bool {
                    append("head \(up ? "up" : "down")")
                }
            case "battery_status":
                if let level = values["level"] as? Int {
                    let charging = values["charging"] as? Bool ?? false
                    append("battery \(level)%\(charging ? " charging" : "")")
                }
            default:
                break
            }
        default:
            break
        }
    }

    private func append(_ text: String) {
        let entry = LogEntry(
            id: nextId,
            time: Date().formatted(date: .omitted, time: .standard),
            text: text
        )
        nextId += 1
        log = Array([entry] + log.prefix(Self.maxLogEntries - 1))
    }
}
