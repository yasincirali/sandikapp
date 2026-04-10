import SwiftUI
import SwiftData

struct AssetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let asset: Asset
    let viewModel: PortfolioViewModel

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var manualPriceText = ""

    private var valueTRY: Double { viewModel.assetValueTRY(asset) }
    private var isPositive: Bool { asset.gainLoss >= 0 }

    var body: some View {
        NavigationStack {
            List {
                // Header section
                Section {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(asset.type.color.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Image(systemName: asset.type.icon)
                                .font(.system(size: 28))
                                .foregroundStyle(asset.type.color)
                        }
                        .frame(maxWidth: .infinity)

                        Text(asset.name)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(valueTRY, format: .currency(code: "TRY"))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))

                        HStack(spacing: 4) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            Text(asset.gainLoss, format: .currency(code: asset.currency))
                            Text("(\(asset.gainLossPercentage, specifier: "%.2f")%)")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isPositive ? .green : .red)
                    }
                    .padding(.vertical, 8)
                }

                // Details
                Section("Varlık Bilgileri") {
                    detailRow(label: "Tür", value: asset.type.rawValue)
                    if !asset.ticker.isEmpty {
                        detailRow(label: "Sembol", value: asset.ticker)
                    }
                    detailRow(label: "Miktar / Adet", value: String(format: "%.4f", asset.quantity))
                    detailRow(label: "Alış Fiyatı", value: "\(asset.purchasePrice.formatted(.number.precision(.fractionLength(4)))) \(asset.currency)")
                    detailRow(label: "Güncel Fiyat", value: "\(asset.currentPrice.formatted(.number.precision(.fractionLength(4)))) \(asset.currency)")
                    detailRow(label: "Toplam Maliyet", value: asset.totalCost.formatted(.currency(code: asset.currency)))
                    detailRow(label: "Güncel Değer (TL)", value: valueTRY.formatted(.currency(code: "TRY")))
                    if let updated = asset.lastUpdated {
                        detailRow(label: "Son Güncelleme", value: updated.formatted(.dateTime.day().month().hour().minute()))
                    }
                }

                // Manual price override (only when no ticker or manual mode)
                if asset.isManualPrice || asset.ticker.isEmpty {
                    Section("Fiyat Güncelle") {
                        HStack {
                            TextField("Güncel fiyat", text: $manualPriceText)
                                .keyboardType(.decimalPad)
                            Text(asset.currency)
                                .foregroundStyle(.secondary)
                            Button("Kaydet") {
                                if let price = Double(manualPriceText.replacingOccurrences(of: ",", with: ".")) {
                                    asset.currentPrice = price
                                    asset.lastUpdated = Date()
                                    manualPriceText = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                // Notes
                if !asset.notes.isEmpty {
                    Section("Notlar") {
                        Text(asset.notes)
                            .foregroundStyle(.secondary)
                    }
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Varlığı Sil", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(asset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Düzenle") { showingEdit = true }
                }
            }
            .sheet(isPresented: $showingEdit) {
                AddAssetView(editingAsset: asset)
            }
            .confirmationDialog("Varlığı silmek istediğinize emin misiniz?",
                                isPresented: $showingDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    modelContext.delete(asset)
                    dismiss()
                }
            }
            .onAppear {
                manualPriceText = ""
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}
