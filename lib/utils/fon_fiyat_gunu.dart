/// Fon fiyatının günü — "bugünün fiyatı değil" bilgisinin saf kuralı
/// (müşteri raporu 30 Eki 21:15 #2, yasin "yap").
///
/// TEFAS fonu günde bir fiyat yayımlar; bugünün fiyatı akşam ya da ertesi
/// sabah gelir. Ekran bu yüzden çoğu zaman dünün (hafta başında Cuma'nın)
/// fiyatını gösterir. Kural:
/// - Fiyat BUGÜNÜNse hiçbir şey yazılmaz (gürültü yok).
/// - Gün bilinmiyorsa (eski önbellek, elle fiyat) hiçbir şey yazılmaz:
///   uydurma tarih yok.
/// - Gelecek tarih (saat dilimi kayması) bugün sayılır.
library;

/// [tarih] ile [simdi] arasındaki TAKVİM günü farkı; fark yoksa ya da
/// tarih bilinmiyorsa null. UTC bileşenleriyle hesaplanır ki yaz saati
/// geçişinde 23 saatlik gün "0 gün" çıkmasın.
int? fonFiyatGunFarki(DateTime? tarih, DateTime simdi) {
  if (tarih == null) return null;
  final t = tarih.toLocal();
  final n = simdi.toLocal();
  final fark = DateTime.utc(n.year, n.month, n.day)
      .difference(DateTime.utc(t.year, t.month, t.day))
      .inDays;
  return fark > 0 ? fark : null;
}

/// Pozisyon anahtarından (`fon|TEFAS:AFT`, `fon|AFT`) fon kodu; sembol
/// çekirdeği değilse (`sub:`/`name:`) null.
String? fonKoduAnahtardan(String positionKey) {
  final parts = positionKey.split('|');
  final core = (parts.length > 1 ? parts[1] : positionKey)
      .trim()
      .toUpperCase()
      .replaceFirst('TEFAS:', '');
  if (core.isEmpty || core.contains(':')) return null;
  return core;
}
