import SwiftUI

struct DisplayScreen: View {
    @EnvironmentObject private var session: BluetoothSession

    @State private var text = "Hello from Even Template"
    @State private var status: String?

    var body: some View {
        Form {
            Section("Glasses display") {
                Text("Sends a text wall to connected G1 or G2 glasses. The R1 ring has no display. G2 renders on a 576×288 canvas; G1 supports a limited Latin glyph set.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 80)
                Button("Send to glasses") {
                    send()
                }
                Button("Clear display") {
                    clear()
                }
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func send() {
        let sdk = session.sdk
        let text = text
        Task {
            do {
                try await sdk.displayText(text)
                status = "Sent"
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func clear() {
        let sdk = session.sdk
        Task {
            do {
                try await sdk.clearDisplay()
                status = "Display cleared"
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
