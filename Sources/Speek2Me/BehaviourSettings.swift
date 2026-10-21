import SwiftUI

struct BehaviourSettings: View {
    @ObservedObject var settings: AppSettings

    @State private var terminalList = ""

    var body: some View {
        Form {
            Section("What is spoken") {
                Toggle("Read the whole final message instead of a condensed version", isOn: $settings.readFull)
                Stepper(value: $settings.maxSentences, in: 1...10) {
                    Text("Keep \(settings.maxSentences) sentence\(settings.maxSentences == 1 ? "" : "s") when condensing or falling back")
                }
                Toggle("Speak idle nudges (\"… is waiting for you\")", isOn: $settings.speakIdle)
            }
            Section("When to stay quiet") {
                Toggle("Mute", isOn: $settings.muted)
                Toggle("Quiet while a terminal is the front window (sound only)", isOn: $settings.quietWhenTerminalFocused)
                TextField("Terminal bundle identifiers, one per line", text: $terminalList, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(4...8)
                    .onChange(of: terminalList) { _, value in
                        settings.terminalBundleIDs = value.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { terminalList = settings.terminalBundleIDs.joined(separator: "\n") }
    }
}
