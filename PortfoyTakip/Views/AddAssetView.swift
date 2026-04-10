import SwiftUI
import SwiftData

struct AddAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Pass an asset to enter edit mode
    var editingAsset: Asset? = nil

    @State private var name = ""
    @State private var ticker = ""
    @State private var selectedType: AssetType = .hisse
    @State private var quantityText = ""
    @State private var purchasePriceText = ""
    @State private var currency = "TRY"
    @State private var notes = ""
    @State private var isManualPrice = false

    private let currencies = ["TRY", "USD", "EUR", "GBP"]
    private var isEditing: Bool { editingAsset != nil }

    private var isFormValid: Bool {
        !name.isEmpty
        && !quantityText.isEmpty
        && !purchasePriceText.isEmpty
        && Double(quantityText.replacingOccurrences(of: ",", with: ".")) != nil
        && Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Asset type picker
                Section("Varlık Türü") {
                    Picker("Tür", selection: $selectedType) {
                        ForEach(AssetType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedType) {
                        if currency.isEmpty { currency = selectedType.defaultCurrency }
                    }
                }

                // Basic info
                Section("Genel Bilgiler") {
                    TextField("Varlık adı (Ör: Türk Hava Yolları)", text: $name)

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Yahoo Finance Sembolü (opsiyonel)", text: $ticker)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                        Text(selectedType.tickerHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Manuel fiyat gir (sembol kullanma)", isOn: $isManualPrice)
                        .onChange(of: ticker) {
                            if ticker.isEmpty { isManualPrice = true }
                        }
                }

                // Quantity & price
                Section("Miktar ve Fiyat") {
                    HStack {
                        Text("Adet / Miktar")
                        Spacer()
                        TextField("0,00", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }

                    HStack {
                        Text("Alış Fiyatı")
                        Spacer()
                        TextField("0,00", text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Picker("", selection: $currency) {
                            ForEach(currencies, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 70)
                    }

                    // Show computed cost preview
                    if let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
                       let price = Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")) {
                        HStack {
                            Text("Toplam Maliyet")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text((qty * price).formatted(.currency(code: currency)))
                                .fontWeight(.semibold)
                        }
                    }
                }

                // Notes
                Section("Notlar (opsiyonel)") {
                    TextField("Notlarınız...", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(isEditing ? "Varlığı Düzenle" : "Yeni Varlık Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Güncelle" : "Ekle") {
                        save()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    private func save() {
        guard let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(purchasePriceText.replacingOccurrences(of: ",", with: ".")) else { return }

        let finalTicker = isManualPrice ? "" : ticker.trimmingCharacters(in: .whitespaces).uppercased()

        if let asset = editingAsset {
            asset.name = name
            asset.ticker = finalTicker
            asset.typeRaw = selectedType.rawValue
            asset.quantity = qty
            asset.purchasePrice = price
            asset.currency = currency
            asset.notes = notes
            asset.isManualPrice = isManualPrice || finalTicker.isEmpty
        } else {
            let asset = Asset(
                name: name,
                ticker: finalTicker,
                type: selectedType,
                quantity: qty,
                purchasePrice: price,
                currency: currency,
                notes: notes
            )
            asset.isManualPrice = isManualPrice || finalTicker.isEmpty
            modelContext.insert(asset)
        }

        dismiss()
    }

    private func populateIfEditing() {
        guard let asset = editingAsset else { return }
        name = asset.name
        ticker = asset.ticker
        selectedType = asset.type
        quantityText = String(asset.quantity)
        purchasePriceText = String(asset.purchasePrice)
        currency = asset.currency
        notes = asset.notes
        isManualPrice = asset.isManualPrice
    }
}
