import Foundation
import Observation

enum StatsTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case reviews = "Reviews"
    case cards = "Cards"
    case intervals = "Intervals"
    case ease = "Ease"
    case futureDue = "Future Due"
    case added = "Added"
    case retention = "Retention"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
            case .today: "calendar"
            case .reviews: "chart.bar"
            case .cards: "rectangle.stack"
            case .intervals: "clock"
            case .ease: "gauge.medium"
            case .futureDue: "calendar.badge.clock"
            case .added: "plus.circle"
            case .retention: "checkmark.circle"
        }
    }
}

enum StatsTimeRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case allTime = "All"

    var id: String {
        rawValue
    }

    var days: UInt32 {
        switch self {
            case .oneMonth: 30
            case .threeMonths: 90
            case .oneYear: 365
            case .allTime: 0
        }
    }
}

@Observable
@MainActor
final class StatsModel {
    var graphs: Anki_Stats_GraphsResponse?
    var isLoading: Bool = false
    var error: AnkiError?

    var search: String = ""
    var days: UInt32 = 365

    var selectedTab: StatsTab = .today
    var selectedTimeRange: StatsTimeRange = .oneYear

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            graphs = try await service.getGraphs(search: search, days: selectedTimeRange.days)
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    // MARK: - Review chart data

    struct ReviewDataPoint: Identifiable {
        let id = UUID()
        let day: Int
        let learn: UInt32
        let relearn: UInt32
        let young: UInt32
        let mature: UInt32
    }

    var reviewCountData: [ReviewDataPoint] {
        guard let reviews = graphs?.reviews else { return [] }
        return reviews.count.sorted(by: { $0.key < $1.key }).map { day, reviewCount in
            ReviewDataPoint(day: Int(day), learn: reviewCount.learn, relearn: reviewCount.relearn, young: reviewCount.young, mature: reviewCount.mature)
        }
    }

    // MARK: - Card counts

    var cardCountsData: Anki_Stats_GraphsResponse.CardCounts.Counts? {
        graphs?.cardCounts.excludingInactive
    }

    var totalCards: UInt32 {
        guard let counts = cardCountsData else { return 0 }
        return counts.newCards + counts.learn + counts.relearn + counts.young + counts.mature + counts.suspended + counts.buried
    }

    // MARK: - Intervals

    struct IntervalDataPoint: Identifiable {
        let id = UUID()
        let intervalDays: UInt32
        let count: UInt32
    }

    var intervalData: [IntervalDataPoint] {
        guard let intervals = graphs?.intervals else { return [] }
        return intervals.intervals.sorted(by: { $0.key < $1.key }).map {
            IntervalDataPoint(intervalDays: $0.key, count: $0.value)
        }
    }

    // MARK: - Ease

    struct EaseDataPoint: Identifiable {
        let id = UUID()
        let ease: UInt32
        let count: UInt32
    }

    var easeData: [EaseDataPoint] {
        guard let eases = graphs?.eases else { return [] }
        return eases.eases.sorted(by: { $0.key < $1.key }).map {
            EaseDataPoint(ease: $0.key, count: $0.value)
        }
    }

    var averageEase: Float {
        graphs?.eases.average ?? 0
    }

    // MARK: - Future Due

    struct FutureDueDataPoint: Identifiable {
        let id = UUID()
        let day: Int
        let count: UInt32
    }

    var futureDueData: [FutureDueDataPoint] {
        guard let futureDue = graphs?.futureDue else { return [] }
        return futureDue.futureDue.sorted(by: { $0.key < $1.key }).map {
            FutureDueDataPoint(day: Int($0.key), count: $0.value)
        }
    }

    // MARK: - Added

    struct AddedDataPoint: Identifiable {
        let id = UUID()
        let day: Int
        let count: UInt32
    }

    var addedData: [AddedDataPoint] {
        guard let added = graphs?.added else { return [] }
        return added.added.sorted(by: { $0.key < $1.key }).map {
            AddedDataPoint(day: Int($0.key), count: $0.value)
        }
    }

    // MARK: - Today

    var todayStats: Anki_Stats_GraphsResponse.Today? {
        graphs?.today
    }

    // MARK: - True Retention

    var trueRetention: Anki_Stats_GraphsResponse.TrueRetentionStats? {
        graphs?.trueRetention
    }
}
