import Foundation
import SwiftData

enum CaptureHistoryQuery {
    static func descriptor(limit: Int) -> FetchDescriptor<CaptureRecord> {
        let capturing = CaptureLifecycle.capturing.rawValue
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.lifecycleRawValue != capturing },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
