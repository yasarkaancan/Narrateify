import SwiftUI

/// Aggregates estimated spend from the saved narration history. Cloud engines
/// (ElevenLabs / OpenAI) carry a per-record `estimatedCost`; local and Apple
/// voices are free.
enum Usage {
    struct Stats {
        var today: Double = 0
        var month: Double = 0
        var monthCredits: Double = 0
        var allTime: Double = 0
        /// This-month cost grouped by engine name (only > 0).
        var byEngine: [(engine: String, cost: Double)] = []
    }

    static func compute(_ records: [NarrationRecord], now: Date = Date()) -> Stats {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: now)
        let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startDay

        var s = Stats()
        var engineTotals: [String: Double] = [:]
        for r in records {
            s.allTime += r.estimatedCost
            if r.date >= startDay { s.today += r.estimatedCost }
            if r.date >= startMonth {
                s.month += r.estimatedCost
                s.monthCredits += r.credits
                if r.estimatedCost > 0 {
                    engineTotals[r.engine ?? "Unknown", default: 0] += r.estimatedCost
                }
            }
        }
        s.byEngine = engineTotals.sorted { $0.value > $1.value }
            .map { (engine: $0.key, cost: $0.value) }
        return s
    }

    static func money(_ v: Double) -> String { String(format: "$%.2f", v) }
}

/// The "Usage & cost" section in Settings → General.
struct UsageSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let stats = Usage.compute(state.history.records)
        Section("Usage & cost") {
            LabeledContent("Today", value: Usage.money(stats.today))
            LabeledContent("This month", value: Usage.money(stats.month))
            if stats.monthCredits > 0 {
                LabeledContent("Credits this month",
                               value: "\(Int(stats.monthCredits))")
            }
            LabeledContent("All time", value: Usage.money(stats.allTime))

            if !stats.byEngine.isEmpty {
                ForEach(stats.byEngine, id: \.engine) { row in
                    LabeledContent {
                        Text(Usage.money(row.cost)).foregroundStyle(.secondary).monospacedDigit()
                    } label: {
                        Text(row.engine).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("Monthly budget")
                Spacer()
                Text("$")
                TextField("0", value: $state.monthlyBudget, format: .number)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
            }

            if state.monthlyBudget > 0 {
                if stats.month > state.monthlyBudget {
                    Label("Over budget this month "
                          + "(\(Usage.money(stats.month)) of \(Usage.money(state.monthlyBudget)))",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else {
                    let remaining = state.monthlyBudget - stats.month
                    Label("\(Usage.money(remaining)) left this month",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }

            Text("Estimates are for cloud engines using your configured rates. "
                 + "Apple and the local models (Kokoro, Chatterbox) are free.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
