# Opsiyonel Alış Fiyatı Özelliği

## 📋 Yapılan Değişiklikler

### **1. AddAssetScreen Güncellemeleri** (`lib/screens/add_asset_screen.dart`)

#### Fiyat Alanını Opsiyonel Yapma
- **Label**: "Alış Fiyatı" → "Alış Fiyatı (opsiyonel)"
- **Validator**: Zorunlu kontrol kaldırıldı
- **Kaydetme**: Fiyat boşsa `0.0` olarak kaydedilir

#### Toplam Önizleme Güncellemesi
- Fiyat `0` veya boşsa toplam gösterilmez
- Geçerli fiyat varsa toplam hesaplanır

### **2. AssetRowWidget Güncellemeleri** (`lib/widgets/asset_row_widget.dart`)

#### Fiyat Bilinmiyorsa Özel Gösterim
```dart
// Eski: Her zaman fiyat gösterimi
Text(tryFmt.format(_valueTRY))

// Yeni: Fiyat bilinmiyorsa özel gösterim
Text(isPriceKnown ? tryFmt.format(_valueTRY) : 'Fiyat bilinmiyor')
```

#### Gain/Loss Hesaplaması
- Fiyat bilinmiyorsa gain/loss yüzdesi gösterilmez
- Bunun yerine "Güncel: ₺X.XX" gösterilir

### **3. AssetDetailScreen Güncellemeleri** (`lib/screens/asset_detail_screen.dart`)

#### Header'da Gain/Loss
- Fiyat bilinmiyorsa gain/loss gösterilmez
- "Alış fiyatı bilinmiyor" mesajı gösterilir

#### Detaylar Bölümü
- **Alış Fiyatı**: Bilinmiyorsa "Bilinmiyor" gösterilir
- **Toplam Maliyet**: Fiyat bilinmiyorsa gösterilmez

---

## 🎯 Kullanım Senaryoları

### **Fiyat Biliniyorsa (Normal Kullanım)**
1. Varlık ekle → Fiyat gir → Kaydet
2. Gain/Loss hesaplanır ve gösterilir
3. Toplam maliyet hesaplanır

### **Fiyat Bilinmiyorsa (Yeni Özellik)**
1. Varlık ekle → Fiyat alanını boş bırak → Kaydet
2. Ana ekranda: "Fiyat bilinmiyor" + "Güncel: ₺X.XX"
3. Detayda: "Alış fiyatı bilinmiyor"
4. Gain/Loss hesaplanmaz

### **Sonradan Fiyat Güncelleme**
- Detay ekranında "Fiyat Güncelle" bölümünden fiyat eklenebilir
- Fiyat eklendikten sonra gain/loss hesaplanır

---

## 💾 Veri Yapısı

### **Database'de Saklama**
- `purchasePrice`: `0.0` (fiyat bilinmiyorsa)
- `currentPrice`: Güncel piyasa fiyatı (varsa)
- `isManualPrice`: `true` (manuel fiyat girişi için)

### **UI Mantığı**
```dart
bool isPriceKnown = asset.purchasePrice > 0;
if (isPriceKnown) {
  // Gain/loss göster
  // Toplam maliyet göster
} else {
  // "Fiyat bilinmiyor" göster
  // Sadece güncel değer göster
}
```

---

## ✅ Test Edilen Senaryolar

- ✅ Fiyatlı varlık ekleme (normal akış)
- ✅ Fiyatsız varlık ekleme (yeni özellik)
- ✅ Ana ekranda gösterim
- ✅ Detay ekranında gösterim
- ✅ Fiyat sonradan güncelleme
- ✅ Gain/loss hesaplaması

---

## 🔄 Gelecek Geliştirmeler

1. **Fiyat Hatırlatma**
   - Fiyatsız varlıklar için bildirim
   - "Fiyatı güncelle" butonu

2. **İstatistiklerde Filtreleme**
   - Fiyatlı/fiyatsız varlıkları ayrı gösterme
   - Portföy değerinde hesaplama seçenekleri

3. **İçe Aktarma/Dışa Aktarma**
   - Fiyatsız varlıkları özel işaretleme

---

## 📱 Kullanıcı Deneyimi

### **Avantajlar**
- **Esnek Giriş**: Kullanıcılar fiyatı bilmeden varlık ekleyebilir
- **Sonradan Güncelleme**: Fiyat öğrenildiğinde eklenebilir
- **Net Gösterim**: Fiyat durumu açıkça belirtilir

### **UI Göstergeleri**
- Ana ekran: "Fiyat bilinmiyor" etiketi
- Detay ekran: "Alış fiyatı bilinmiyor" mesajı
- Güncel değer: Her zaman gösterilir

---

**Güncelleme Tarihi**: 14 Nisan 2026  
**Durum**: ✅ Üretim Hazır  
**Test**: ✅ Emülatörde Doğrulandı
