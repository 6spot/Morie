import Foundation
import SwiftData

struct CaptureHistorySignature: Equatable {
    let count: Int
    let latestUpdatedAt: Date?
}

enum CaptureHistoryQuery {
    static func descriptor(limit: Int) -> FetchDescriptor<CaptureRecord> {
        let capturing = CaptureLifecycle.capturing.rawValue
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.lifecycleRawValue != capturing },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.propertiesToFetch = [
            \CaptureRecord.id,
            \CaptureRecord.createdAt,
            \CaptureRecord.lifecycleRawValue,
            \CaptureRecord.deliveryModeRawValue,
            \CaptureRecord.recognizedText,
            \CaptureRecord.finalText,
            \CaptureRecord.sourceApplicationName,
        ]
        return descriptor
    }

    static func signature(in context: ModelContext) throws -> CaptureHistorySignature {
        let capturing = CaptureLifecycle.capturing.rawValue
        let base = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.lifecycleRawValue != capturing }
        )
        let count = try context.fetchCount(base)

        var latest = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.lifecycleRawValue != capturing },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        latest.fetchLimit = 1
        latest.propertiesToFetch = [\CaptureRecord.updatedAt]

        return CaptureHistorySignature(
            count: count,
            latestUpdatedAt: try context.fetch(latest).first?.updatedAt
        )
    }
}
