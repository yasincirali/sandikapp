import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.addedDate, order: .reverse) private var assets: [Asset]

    @State private var viewModel = PortfolioViewModel()
    @State private var showingAddAsset = false
    @State private var selectedAsset: Asset?
    @State private var searchText = ""
    @State private var selectedFilter: AssetType? = nil

    private var filteredAssets: [Asset] {
        assets.filter { asset in
            let matchesType = selectedFilter == nil || asset.type == selectedFilter
            let matchesSearch = searchText.isEmpty
                || asset.name.localizedCaseInsensitiveContains(searchText)
                || asset.ticker.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PortfolioSummaryView(viewModel: viewModel, assets: assets)
                        .padding(.horizontal)

                    // Filter chips
                    filterChips
                        .padding(.horizontal)

                    // Asset list
                    if filteredAssets.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredAssets) { asset in
                                Button {
                                    selectedAsset = asset
                                } label: {
                                    AssetRowView(asset: asset, viewModel: viewModel)
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)

                                if asset.id != filteredAssets.last?.id {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Portföyüm")
            .searchable(text: $searchText, prompt: "Varlık veya sembol ara...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddAsset = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await viewModel.refreshPrices(assets: assets) }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showingAddAsset) {
                AddAssetView()
            }
            .sheet(item: $selectedAsset) { asset in
                AssetDetailView(asset: asset, viewModel: viewModel)
            }
            .task {
                await viewModel.refreshPrices(assets: assets)
            }
            .refreshable {
                await viewModel.refreshPrices(assets: assets)
            }
        }
    }

    // MARK: - Subviews

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Tümü", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }
                ForEach(AssetType.allCases, id: \.self) { type in
                    FilterChip(
                        label: type.rawValue,
                        color: type.color,
                        isSelected: selectedFilter == type
                    ) {
                        selectedFilter = selectedFilter == type ? nil : type
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty && selectedFilter == nil
                 ? "Henüz varlık eklenmedi"
                 : "Sonuç bulunamadı")
                .font(.headline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty && selectedFilter == nil {
                Button {
                    showingAddAsset = true
                } label: {
                    Label("İlk varlığı ekle", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    var color: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : color.opacity(0.12))
                .foregroundStyle(isSelected ? .white : color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
