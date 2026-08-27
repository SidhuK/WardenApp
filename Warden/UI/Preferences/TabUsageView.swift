import CoreData
import SwiftUI
import Charts

/// Usage & cost dashboard: totals, daily cost chart, per-model breakdown.
@MainActor
struct TabUsageView: View {
    @Environment(\.managedObjectContext) private var viewContext

    enum TimeWindow: String, CaseIterable, Identifiable {
        case sevenDays = "7 Days"
        case thirtyDays = "30 Days"
        case allTime = "All Time"

        var id: String { rawValue }

        var startDate: Date? {
            switch self {
            case .sevenDays:
                return Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))
            case .thirtyDays:
                return Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))
            case .allTime:
                return nil
            }
        }

        var dayCountForChart: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .allTime: return nil
            }
        }
    }

    @State private var window: TimeWindow = .thirtyDays
    /// Bumped whenever usage records change so computed cards/chart re-render.
    @State private var refreshTrigger = 0

    private let service = UsageTrackingService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                totalsCards

                if window.dayCountForChart != nil {
                    dailyChartCard
                }

                modelBreakdownCard
            }
            .padding(20)
        }
        .id(refreshTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { note in
            // Re-render when any save touches a UsageRecordEntity (e.g. a completion
            // finishing in another window while this tab is open).
            if let objects = note.object as? Set<NSManagedObject>,
               objects.contains(where: { $0 is UsageRecordEntity }) {
                refreshTrigger &+= 1
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            SettingsSectionHeader(title: "Usage & Cost")
            Spacer()
            Picker("Time Window", selection: $window) {
                ForEach(TimeWindow.allCases) { window in
                    Text(window.rawValue).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
    }

    private var totalsCards: some View {
        let totals = service.totals(from: window.startDate)
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            usageStatCard(
                title: "Estimated Spend",
                value: formatUSD(totals.costUSD),
                icon: "dollarsign.circle.fill",
                color: .mint,
                subtitle: window == .allTime ? "since tracking began" : "last \(window.rawValue.lowercased())"
            )
            usageStatCard(
                title: "Input Tokens",
                value: formatTokenCount(totals.inputTokens),
                icon: "arrow.down.circle",
                color: .blue,
                subtitle: ""
            )
            usageStatCard(
                title: "Output Tokens",
                value: formatTokenCount(totals.outputTokens),
                icon: "arrow.up.circle",
                color: .purple,
                subtitle: ""
            )
            usageStatCard(
                title: "Requests",
                value: "\(totals.requestCount)",
                icon: "bubble.left.and.bubble.right",
                color: .orange,
                subtitle: ""
            )
        }
    }

    private func usageStatCard(title: String, value: String, icon: String, color: Color, subtitle: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var dailyChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily Cost")
                    .font(.system(size: 13, weight: .medium))

                let days = service.dailyTotals(days: window.dayCountForChart ?? 30)
                if days.allSatisfy({ $0.totals.costUSD == 0 }) && !days.isEmpty {
                    Text("No recorded spend in this window yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    Chart(days, id: \.date) { entry in
                        BarMark(
                            x: .value("Day", entry.date, unit: .day),
                            y: .value("Cost", entry.totals.costUSD)
                        )
                        .foregroundStyle(Color.mint.gradient)
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 9))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisValueLabel()
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 180)
                }
            }
            .padding(16)
        }
    }

    private var modelBreakdownCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("By Model")
                    .font(.system(size: 13, weight: .medium))

                let breakdown = service.breakdownByModel(from: window.startDate)
                if breakdown.isEmpty {
                    Text("No usage recorded in this window yet. Send a message to start tracking.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(breakdown) { entry in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.providerName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(entry.modelId)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formatUSD(entry.totals.costUSD))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Text("\(formatTokenCount(entry.totals.inputTokens)) in · \(formatTokenCount(entry.totals.outputTokens)) out")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)

                            if entry.id != breakdown.last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Formatting

    private func formatUSD(_ amount: Double) -> String {
        // Locale-aware currency formatting, pinned to USD (pricing source is USD).
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        if amount >= 100 {
            formatter.maximumFractionDigits = 0
        } else if amount >= 1 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = amount > 0 ? 4 : 2
        }
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func formatTokenCount(_ count: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal  // Respects the user's grouping/decimal separators
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", locale: Locale.current, Double(count) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", locale: Locale.current, Double(count) / 1_000)
        default:
            return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        }
    }
}
