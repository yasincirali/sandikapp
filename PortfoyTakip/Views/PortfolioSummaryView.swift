import SwiftUI

struct PortfolioSummaryView: View {
    let viewModel: PortfolioViewModel
    let assets: [Asset]

    private var totalValue: Double { viewModel.totalValue(assets: assets) }
    private var gainLoss: Double { viewModel.totalGainLoss(assets: assets) }
    private var gainLossPercent: Double { viewModel.totalGainLossPercent(assets: assets) }
    private var isPositive: Bool { gainLoss >= 0 }

    var body: some View {
        VStack(spacing: 12) {
            // Header row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Toplam Portföy Değeri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalValue, format: .currency(code: "TRY"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            Divider()

            // Gain/Loss row
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kar / Zarar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        Text(gainLoss, format: .currency(code: "TRY"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPositive ? .green : .red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Getiri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(gainLossPercent / 100, format: .percent.precision(.fractionLength(2)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isPositive ? .green : .red)
                }
            }

            // Exchange rate info
            HStack(spacing: 12) {
                rateChip(label: "USD", value: viewModel.usdTry)
                rateChip(label: "EUR", value: viewModel.eurTry)
                rateChip(label: "GBP", value: viewModel.gbpTry)
                Spacer()
                if let date = viewModel.lastUpdated {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func rateChip(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}
