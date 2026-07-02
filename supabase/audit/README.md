# DB Security Audit

`db_security_audit.sql` — Supabase'deki tüm tabloları, RLS politikalarını, FK CASCADE kurallarını ve hesap silme akışını doğrulayan **read-only** rapor scripti.

## Çalıştırma

1. Supabase Dashboard → SQL Editor → New query
2. `db_security_audit.sql` dosyasının içeriğini yapıştır
3. Run (Ctrl+Enter)

10 ayrı rapor üretir. Her birinin başında ne kontrol edildiği yazıyor.

## Beklenen Sonuçlar

### ✓ OK ise (her şey doğru):
- **1)** Tüm user_id FK'leri `CASCADE` (db_logs hariç — o `SET NULL`)
- **2)** Tüm tablolarda RLS `açık`
- **3)** Her tabloda en az 1 SELECT/INSERT/UPDATE/DELETE policy
- **4)** Beklenmedik "RLS açık ama policy yok" tablosu yok (account_deletion_log hariç)
- **5)** anon rolü SELECT/INSERT yetkisi yok (sadece authenticated)
- **6)** SECURITY DEFINER fonksiyonların hepsi `search_path` set
- **7)** disclaimer_acceptances için UPDATE/DELETE policy yok ✓
- **8)** account_deletion_log RLS açık, policy yok (yalnızca service-role)
- **10)** Beklenmedik tablo yok

### 🔴 Kırmızı görürsen:
- **RLS KAPALI:** Bir attacker anon key ile tüm veriyi okuyabilir. Hemen `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` çalıştır.
- **DELETE rule CASCADE değil:** Hesap silme akışı bu satırları temizleyemez → KVKK ihlali. ALTER TABLE ile düzelt.
- **SECURITY DEFINER + search_path yok:** Potansiyel privilege escalation (CVE-2007-2138 benzeri).

### ⚠️ Sarı uyarılar:
- Genelde incelemeye değer ama kritik değil. README'deki not'larla karşılaştır.

## Bilinmesi Gereken

- **db_logs** intentionally `ON DELETE SET NULL` (log silmek istemiyoruz, sadece user_id null'a düşsün).
- **disclaimer_acceptances** için UPDATE/DELETE policy YOKLUĞU = doğru tasarım (default deny, immutable).
- **account_deletion_log** için policy YOKLUĞU = doğru tasarım (yalnızca service-role yazabilir/okuyabilir).
- **db_logs_select_own** kullanıcının kendi log'larını okumasına izin veriyor (debugging hakkı).
- **partner_invites_select_partner** policy'si profiles + partnerships birleşimine bağlı — partner görme.

## Ne Sıklıkta?

- Yeni migration ekleyince
- Yeni RLS policy yazınca
- Production öncesi son kontrol
- 3 ayda bir routine audit
