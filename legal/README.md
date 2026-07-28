# sandık — Hukuki Doküman Paketi

Bu klasör, **sandık** uygulamasının App Store ve Google Play yayını için gereken tüm hukuki dokümanları içerir.

## 📋 Doküman Listesi

### Türkçe (`tr/`)
| Doküman | Amaç |
|---|---|
| [PRIVACY_POLICY.md](tr/PRIVACY_POLICY.md) | Gizlilik Politikası — KVKK + GDPR uyumlu |
| [TERMS_OF_SERVICE.md](tr/TERMS_OF_SERVICE.md) | Kullanım Koşulları — yatırım disclaimer dahil |
| [KVKK_AYDINLATMA_METNI.md](tr/KVKK_AYDINLATMA_METNI.md) | KVKK Madde 10 aydınlatma yükümlülüğü |
| [ACIK_RIZA_METNI.md](tr/ACIK_RIZA_METNI.md) | KVKK Madde 5(1) ve 9(1) açık rıza (yurt dışı aktarım) |
| [COKEZ_VE_DEPOLAMA.md](tr/COKEZ_VE_DEPOLAMA.md) | Mobil uygulama yerel depolama açıklaması (ePrivacy) |

### English (`en/`)
| Document | Purpose |
|---|---|
| [PRIVACY_POLICY.md](en/PRIVACY_POLICY.md) | Privacy Policy — GDPR + KVKK compliant |
| [TERMS_OF_SERVICE.md](en/TERMS_OF_SERVICE.md) | Terms of Service — investment disclaimer included |
| [GDPR_NOTICE.md](en/GDPR_NOTICE.md) | EU/EEA-specific GDPR Article 13/14 notice |

### Genel (`./`)
| Doküman | Amaç |
|---|---|
| [DATA_DELETION_REQUEST_FORM.md](DATA_DELETION_REQUEST_FORM.md) | Web sayfası şablonu (Google Play zorunluluğu) |
| [ACCOUNT_DELETION_IMPLEMENTATION.md](ACCOUNT_DELETION_IMPLEMENTATION.md) | Hesap silme akışının teknik tasarımı |

---

## ⚠️ Yayın Öncesi YAPILACAKLAR

### 1. TODO Alanlarını Doldurun

Tüm dokümanlarda `Yasin Çıralı`, `İstanbul, Türkiye`, `sandikapp.destek@gmail.com`, `Kayıtlı değil (bireysel geliştirici — VERBIS kaydı ticari faaliyet başlangıcında yapılacaktır)`, `İstanbul Anadolu Mahkemeleri ve İcra Daireleri` vb. placeholder'lar var. Production'a çıkmadan önce **mutlaka** gerçek değerlerle değiştirin.

```bash
# Yardımcı komut — placeholder'ları bul:
grep -rn "\[" legal/ | grep -v "^Binary"
```

### 2. Hukuki İnceleme

Bu şablonlar **kapsamlı bir başlangıç noktasıdır** ancak iki şey için bir **avukatla** çalışın:

- **Veri sorumlusu yapınız:** Bireysel mi (ad-soyad), tescilli şirket mi, limited mi? VERBİS kayıt yükümlülüğünüz var mı? (kvkk.gov.tr/Icerik/2030/Verbis-Hakkinda)
- **Yatırım disclaimer:** SPK ile temas riskine karşı bir SPK avukatına metni inceleten. Çoklu kullanıcı paylaşım özelliğiniz "kollektif yatırım" olarak yorumlanabilir mi?

### 3. Hosting

Hukuki belgeleri **halka açık URL'de** yayınlamak zorunludur:

| URL | İçerik |
|---|---|
| `https://yasincirali.github.io/sandikapp/privacy` | tr/PRIVACY_POLICY.md (HTML render) |
| `https://yasincirali.github.io/sandikapp/privacy-en` | en/PRIVACY_POLICY.md |
| `https://yasincirali.github.io/sandikapp/terms` | tr/TERMS_OF_SERVICE.md |
| `https://yasincirali.github.io/sandikapp/legal/kvkk` | tr/KVKK_AYDINLATMA_METNI.md |
| `https://yasincirali.github.io/sandikapp/legal/gdpr` | en/GDPR_NOTICE.md |
| `https://yasincirali.github.io/sandikapp/data-deletion` | DATA_DELETION_REQUEST_FORM.md HTML |

**Önerilen hosting:** GitHub Pages (ücretsiz), Vercel, Netlify, Cloudflare Pages. Domain için: `sandik.app` veya `sandikapp.com`.

### 4. Uygulama İçi Entegrasyon

| Ekran | Eklenecek |
|---|---|
| Register | KVKK Aydınlatma + Açık Rıza onay kutusu (link ile aç) |
| Profile → Ayarlar | "Gizlilik Politikası", "Kullanım Koşulları", "KVKK", "Hesabımı Sil", "Verilerimi İndir" linkleri |
| Disclaimer akışı | Mevcut (`disclaimer_acceptance_screen.dart`) — devam et |

### 5. Sürüm Yönetimi

Hukuki dokümanların sürümlerini izleyin:

```yaml
# legal/VERSIONS.yaml örneği
privacy_policy: 1.0
terms_of_service: 1.0
kvkk_aydinlatma: 1.0
acik_riza: 1.0
gdpr_notice: 1.0
```

Sürüm değişikliğinde uygulama içi tekrar onay isteyin (mevcut disclaimer flow gibi).

---

## 📊 Karşılanan Yasal Gereklilikler

| Yasa / Kurallar | Karşılayan doküman |
|---|---|
| **KVKK Madde 10** (aydınlatma) | KVKK_AYDINLATMA_METNI.md |
| **KVKK Madde 5(1), 9(1)** (açık rıza) | ACIK_RIZA_METNI.md |
| **KVKK Madde 11** (haklar) | KVKK_AYDINLATMA_METNI.md §7 + PRIVACY_POLICY.md §8 |
| **KVKK Madde 12** (güvenlik + ihlal bildirimi) | KVKK_AYDINLATMA_METNI.md §8-9 |
| **GDPR Madde 13-14** (bilgilendirme) | GDPR_NOTICE.md |
| **GDPR Madde 15-22** (haklar) | GDPR_NOTICE.md §7 |
| **GDPR Madde 33-34** (ihlal bildirimi) | PRIVACY_POLICY.md §10 + GDPR_NOTICE.md §9 |
| **GDPR Madde 44-49** (uluslararası aktarım) | PRIVACY_POLICY.md §6 + GDPR_NOTICE.md §5 |
| **TKHK** (tüketici hakları) | TERMS_OF_SERVICE.md §12 |
| **SPK** (yatırım tavsiyesi reddi) | TERMS_OF_SERVICE.md §3 + disclaimer_service.dart |
| **Apple App Store Privacy** | PRIVACY_POLICY.md (Data Safety form için referans) |
| **Google Play Data Safety** | PRIVACY_POLICY.md + DATA_DELETION_REQUEST_FORM.md |
| **Google Play Account Deletion (2024)** | ACCOUNT_DELETION_IMPLEMENTATION.md + DATA_DELETION_REQUEST_FORM.md |
| **App Store Guideline 5.1.1(v)** | ACCOUNT_DELETION_IMPLEMENTATION.md |
| **ePrivacy Direktifi (2002/58/EC)** | COKEZ_VE_DEPOLAMA.md |

---

## 📞 Sorular

Bu dokümanlarla ilgili teknik sorular için repo issue açın. Hukuki yorum için bir avukatla çalışın.
