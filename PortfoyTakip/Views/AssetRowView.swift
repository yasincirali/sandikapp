import SwiftUI

struct AssetRowView: View {
    let asset: Asset
    let viewModel: PortfolioViewModel

    private var valueTRY: Double { viewModel.assetValueTRY(asset) }
    private var isPositive: Bool { asset.gainLoss >= 0 }
    private var gainColor: Color { isPositive ? .green : .red }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(asset.type.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: asset.type.icon)
                    .foregroundStyle(asset.type.color)
                    .font(.system(size: 18, weight: .medium))
            }

            // Name & ticker
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(asset.type.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(asset.type.color, in: Capsule())
                    if !asset.ticker.isEmpty {
                        Text(asset.ticker)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Value & gain
            VStack(alignment: .trailing, spacing: 2) {
                Text(valueTRY, format: .currency(code: "TRY"))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 2) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text(asset.gainLossPercentage / 100, format: .percent.precision(.fractionLength(2)))
                        .font(.caption)
                }
                .foregroundStyle(gainColor)
            }
        }
        .padding(.vertical, 4)
    }
}
