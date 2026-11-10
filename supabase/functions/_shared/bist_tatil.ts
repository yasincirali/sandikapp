/// Borsa İstanbul'un kapalı olduğu günler: sunucunun kopyası.
///
/// İstemcideki `lib/services/bist_calendar.dart` (`BistTakvimi`) ile AYNI
/// liste ve aynı kalmalı (Ar-Ge 29 Eki #1; yasin "yap"). Ayrışınca kilit
/// ekranı uygulama kapalıyken "Canlı", açılınca "Piyasa kapalı" diyordu
/// (29 Ekim 2026 bütün gün). `test/bist_tatil_parite_test.dart` aşağıdaki
/// nesneyi JSON olarak okuyup Dart takvimiyle gün gün karşılaştırır; bu
/// yüzden nesne katı JSON kalır (tırnaklı anahtar, sondaki virgül yok).
///
/// Neden JSON dosyası değil: Edge Function paketine JSON modülü sokmak
/// dağıtım aracında doğrulanmadı; düz TS nesnesi her yerde çalışır.
///
/// Kurallar istemciyle aynı: yalnız ilan edilmiş günler; kapsanmayan yılda
/// dinî bayram bilinmez ve o gün açık sayılır (uydurma tatil yok). Aralık'ta
/// sonraki yılın ilanı gelince iki dosya birlikte güncellenir.
/// 2027 bayramları: yasin 10 Kas 2026'da iletilen resmî tatil listesi.
export const BIST_TATIL = {
  "sonKapsananYil": 2027,
  "sabitTamGun": ["01-01", "04-23", "05-01", "05-19", "07-15", "08-30", "10-29"],
  "sabitYarimGun": ["10-28"],
  "diniTamGun": {
    "2026": ["03-20", "03-21", "03-22", "05-27", "05-28", "05-29", "05-30"],
    "2027": ["03-09", "03-10", "03-11", "05-16", "05-17", "05-18", "05-19"]
  },
  "diniYarimGun": {
    "2026": ["03-19", "05-26"],
    "2027": ["03-08", "05-15"]
  }
} as const;
