import SwiftUI

/// A small window for starting a timer with any duration.
struct CustomTimerView: View {
    let start: (_ duration: TimeInterval, _ label: String?) -> Void
    let cancel: () -> Void

    @State private var hours = 0
    @State private var minutes = 20
    @State private var seconds = 0
    @State private var label = ""

    private var duration: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    var body: some View {
        Form {
            LabeledContent("Duration") {
                HStack(spacing: 4) {
                    unitPicker("Hours", unit: "h", selection: $hours, range: 0..<24)
                    unitPicker("Minutes", unit: "m", selection: $minutes, range: 0..<60)
                    unitPicker("Seconds", unit: "s", selection: $seconds, range: 0..<60)
                }
            }
            TextField("Name", text: $label, prompt: Text("Optional"))
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start Timer") { start(duration, label) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(duration < 1)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func unitPicker(_ title: String, unit: String, selection: Binding<Int>, range: Range<Int>) -> some View {
        HStack(spacing: 2) {
            Picker(title, selection: selection) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
