import SwiftData
import SwiftUI

struct CaptureHistoryView: View {
    @Query(sort: \CaptureRecord.createdAt, order: .reverse)
    private var captures: [CaptureRecord]

    var body: some View {
        NavigationStack {
            List(captures) { capture in
                VStack(alignment: .leading, spacing: 6) {
                    Text(capture.finalText.isEmpty ? capture.recognizedText : capture.finalText)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        Text(capture.createdAt, format: .dateTime)
                        if let applicationName = capture.sourceApplicationName {
                            Text(applicationName)
                        }
                        Text(capture.lifecycleRawValue)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if captures.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "waveform",
                        description: Text("Completed voice captures will appear here.")
                    )
                }
            }
            .navigationTitle("History")
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}
