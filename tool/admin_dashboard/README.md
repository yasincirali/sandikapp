# sandık · destek paneli

Canlı Supabase'e bakan, **yalnızca yerelde çalışan** yönetici paneli. Amacı tek
bir soruyu hızlı cevaplamak: *"Müşteri X hata alıyor — nerede, ne zaman, neden?"*

Mağazaya, sunucuya veya CI'ya **girmez**. `npm run dev` ile açılır, 127.0.0.1'e
bağlanır, kapatınca biter.

---

## Açmak

**Masaüstündeki `sandık destek paneli` kısayoluna çift tıkla.** Kısayol
`baslat.cmd`'yi çağırır: bağımlılık eksikse kurar, dev sunucusunu kaldırır ve
sunucu hazır olunca tarayıcıyı açar.

Açılan **konsol penceresi sunucunun kendisidir** — görev çubuğunda simge
durumunda durur. Paneli kapatmak için o pencereyi kapat; böylece panel arka
planda unutulmuş halde canlı veriye bağlı kalmaz. Kısayola ikinci kez
basarsan yeni sunucu açılmaz, var olan sekmeye döner.

Kısayolu yeniden oluşturmak (taşındıysa veya silindiyse):

```powershell
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'sandik destek paneli.lnk'))
$s.TargetPath = 'C:\projects\PortfoyTakip\tool\admin_dashboard\baslat.cmd'
$s.WorkingDirectory = 'C:\projects\PortfoyTakip\tool\admin_dashboard'
$s.IconLocation = 'C:\projects\PortfoyTakip\tool\admin_dashboard\panel.ico,0'
$s.WindowStyle = 7
$s.Save()
```

> `baslat.cmd` **CRLF satır sonlarıyla ve saf ASCII** olarak tutulur. LF ile
> kaydedilirse batch yorumlayıcısı `rem` satırlarını bölüp anlamsız hatalar
> verir (`'em' is not recognized...`).

### Elle kurulum

```bash
cd tool/admin_dashboard
npm install
cp .env.example .env.local     # URL ve anon key'i doldur
npm run dev                    # http://127.0.0.1:5273
```

`.env.local` içindeki iki değer **gizli değildir**: anon key zaten mobil
uygulamanın binary'sinde taşınır ve RLS ile korunur. Panelin yetkisi anon
key'den değil, **giriş yaptığın hesabın `push_admins` tablosunda olmasından**
gelir.

> `SUPABASE_SERVICE_ROLE_KEY` buraya **konmaz**. RLS'yi tamamen bypass eder ve
> CLAUDE.md'nin gizli anahtar kuralını ihlal eder. Panel ona ihtiyaç duymayacak
> şekilde tasarlandı.

### Yetki

Panel açılışta `is_push_admin()` çağırır. Hesabın listede değilse ne yapman
gerektiğini ekranda gösterir:

```sql
insert into public.push_admins (user_id)
select id from auth.users where email = 'senin@epostan';
```

---

## Ekranlar

| Ekran | Hangi soruyu cevaplar |
|---|---|
| **Genel durum** | "Şu an bir şey bozuk mu?" Hata/auth/kilit sayaçları, saatlik eğri, en çok tekrarlayan hatalar. 60 sn'de bir yenilenir. |
| **Kullanıcılar** | "Bu müşteriye ne oldu?" E-posta / isim / user_id ile ara → künye (hesap, portföy, ortaklık, **cihazlar**) + **push token'ları** + **seans listesi** + istek günlüğü → satıra tıkla: hata tipi/kodu, **stack trace**, üç zaman damgası, ham request/response JSON. |
| **Seanslar** | "Bu açılışta ne oldu?" Seans listesi (kim, süre, kaç olay, hangi cihaz) → seçince **zaman çizelgesi**: her olay, olaylar arası boşluk, istek→yanıt saatleri. |
| **Cihazlar** | "Hangi sürümde/cihazda kırılıyor?" Sürüm sağlığı (platform × sürüm × hata oranı) + cihaz envanteri. Birden çok hesap gören cihazlar işaretlenir. |
| **Güvenlik** | "Kim zorlanıyor, kim zorluyor?" Ardışık başarısız şifre/OTP denemeleri, rate limit kilitleri, GoTrue + istemci auth olay akışı. |
| **Servisler** | "Hangi endpoint bozuk/yavaş?" Çağrı/hata oranı, p50/p95/maks gecikme, endpoint başına hata kırılımı. |

Tablolardaki e-posta düğmeleri tıklanabilir: her ekrandan doğrudan o
kullanıcının log akışına atlar. Seans kimliğine tıklamak log listesini o
seansa daraltır.

### Hata detayı

Bir hata satırında dört yapılandırılmış alan var (migration 0072):

| Alan | Örnek | Ne işe yarar |
|---|---|---|
| `error_type` | `PostgrestException` | Hata **sınıfı**. Ağ mı, şema mı, auth mı — gruplamanın birincil ekseni |
| `error_code` | `42501`, `PGRST202` | Sağlayıcı kodu. Panel bilinen kodları açıklamasıyla gösterir |
| `error_message` | `new row violates RLS…` | Maskelenmiş mesaj, gruplanabilir |
| `stack_trace` | `#0 SupabaseService…` | **Nerede** kırıldığı |

Hata kümeleri artık `(tip, kod, kaynak, mesaj)` ile gruplanıyor. Önceden
gruplama anahtarı serbest metnin tamamıydı ve en ufak değişken (tablo adı,
id) kümeyi bölüyordu. Küme satırı ayrıca hatanın **hangi sürümlerde**
görüldüğünü ve bir **örnek stack trace** taşır.

### Zaman alanları

Bir log satırında **üç** zaman vardır ve üçü de ayrı şey söyler:

| Alan | Ne | Neden ayrı |
|---|---|---|
| `ts` | Satırın sunucuya yazıldığı an | Tek güvenilir sıralama ekseni |
| `requested_at` | İsteğin atıldığı an (**istemci saati**) | Kullanıcının gördüğü an |
| `responded_at` | Yanıtın döndüğü an (**istemci saati**) | `requested_at` + süre |

Panel ayrıca **saat farkı** (`ts − requested_at`) gösterir. Birkaç saniye
normaldir (ağ + kuyruk); **dakikalar mertebesi cihaz saatinin şaştığını**
söyler ve OTP/token gibi zamana bağlı akışlarda çoğu zaman asıl sebeptir.
2 dakikayı aşan sapma kırmızı ⚠ ile işaretlenir.

---

## Veri kaynakları ve sınırları

Panel **hiçbir veri yazmaz**. Tüm RPC'ler `stable`, salt okuma.

### `db_logs` — istemci istek günlüğü

Her Supabase çağrısı `DbLogger.log()` üzerinden geçer ve buraya düşer.

⚠️ **Üretim yapılarında yalnızca HATALAR yazılır** (`DbLogger._persistAsync`,
KVKK kararı). Yani:

- "İstek" sayısı gerçek trafiği **temsil etmez** — çoğu debug yapılarından gelir.
- **Hata sayısı ve etkilenen kullanıcı gerçek sinyaldir.**
- Hata oranını mutlak doğru kabul etme.

Hassas alanlar istemcide maskelenir (`_maskSensitive`): e-posta, parola, token,
telefon, görünen ad → `***`. Hata metninde e-posta/UUID/JWT/IP ayrıca regex ile
temizlenir. Panel bu maskeyi **açmaz**.

**Saklama: 30 gün** (migration 0056, `cleanup_db_logs` her gün 03:15 UTC).
Daha eski bir olayı araştırıyorsan burada yoktur.

#### Log satırına ne YAZILMAZ

Gizlilik politikası (`legal/tr/PRIVACY_POLICY.md` ve `legal/en/`, iki ayrı
yerde) şunu taahhüt ediyor: *"hassas alanlar (e-posta, şifre, token)
maskelenir"*. Bu metin mağazalara da beyan edildi. Buna uygun olarak:

| Veri | Log satırında | Panelde |
|---|---|---|
| E-posta | ❌ yazılmaz | ✅ `profiles` join'i ile **gösterilir** |
| Oturum JWT'si | ❌ hiçbir yerde | Oturum **durumu** künyede (son giriş, onay) |
| FCM push token | ❌ yazılmaz | ✅ künyede **tam değer** (`user_push_tokens`'tan) |
| Şifre | ❌ hiçbir yerde | — |

Teşhis gücü bundan zarar görmüyor: e-postayı ekranda zaten görüyorsun, fark
sadece verinin nerede durduğu. Push token log satırına yazılsaydı 30 gün
boyunca her istekte çoğalırdı; künyede göstermek aynı bilgiyi tek yerde
verir. Oturum JWT'si loglanırsa panel bir **sır deposuna** dönüşür — satırı
okuyan herkes o oturumu taklit edebilir.

Migration 0072 bu sözleşmeyi bir **doğrulama bloğuyla** korur: `db_logs`'a
`email`, `jwt`, `access_token` gibi bir kolon eklenirse migration patlar.

#### Seans / cihaz alanları henüz BOŞ

Migration 0071 dokuz, 0072 dört kolon ekledi (`session_id`, `device_id`, `platform`,
`os_version`, `app_version`, `device_model`, `requested_at`, `responded_at`,
`event_kind`, `error_type`, `error_code`, `error_message`, `stack_trace`)
ama **uygulama tarafı henüz doldurmuyor** — `DbLogger`
güncellemesi ayrı bir turda yapılacak (kullanıcı kararı 2026-09-22: önce
sunucu + panel).

Bu yüzden Seanslar ve Cihazlar ekranları, o sürüm yayınlanana kadar boş
görünür; Kullanıcılar ekranındaki seans/cihaz sütunları `—` gösterir.
Kolonlar nullable olduğu için mevcut sürüm sorunsuz yazmaya devam eder.

### `auth.audit_log_entries` — GoTrue defteri

Başarılı giriş, çıkış, kurtarma isteği, kullanıcı güncelleme. `ip_address`
ayrı kolondur, `payload` `json` tipindedir (jsonb değil).

⚠️ **Başarısız şifre denemeleri burada güvenilir biçimde yazılmaz.** Bu yüzden
Güvenlik ekranı başarısızlıkları `db_logs`'taki `auth/*` hatalarından üretir —
yani **uygulamadan geçen** denemeler. Doğrudan GoTrue API'sine atılan istekler
panelde görünmez; onlar için Supabase Dashboard → Auth → Logs. Supabase'in kendi
giriş rate limit'i de ayrıca ve bağımsız çalışır.

### `rate_limit_attempts` — sunucu taraflı sayaç

Davet kodu gibi Edge Function akışlarında yazılır (migration 0028/0030).

⚠️ **Panelin "kilitli" göstergesi TAHMİNdir:** 5 deneme / 10 dakika
varsayılanına göre hesaplanır. Çağıran fonksiyon farklı bir limit geçiyorsa
gerçek kilit farklı olur. Kesin cevap `peek_rate_limit`'tedir ve yalnızca
service-role çağırabilir.

---

## Sunucu tarafı

Tüm okuma üç migration'daki **on yedi** RPC üzerinden:
`0070_admin_dashboard_rpc.sql` (teşhis), `0071_db_logs_seans_cihaz.sql`
(seans/cihaz/zaman) ve `0072_db_logs_hata_detayi.sql` (hata detayı,
stack trace, push token). Her biri:

- `security definer` + sabit `search_path`
- gövdenin **ilk satırında** `is_push_admin()` → değilse `raise exception 'Yetkisiz'`
- `anon`'a GRANT **yok**, `authenticated`'a var (GRANT kapı değil; kapı
  `is_push_admin()`)

Her migration sonunda doğrulama blokları var: bir fonksiyonun GRANT'ı,
`security definer`/`search_path` kombinasyonu eksikse ya da `anon`'a
yanlışlıkla açıldıysa **migration patlar**.

`db_logs` üzerindeki `db_logs_select_own` RLS politikası yöneticinin başkasının
logunu görmesini engeller; `admin_user_logs` bunu security definer ile açar.
Panelin var olma sebebi büyük ölçüde budur.

---

## Müdahale neden yok

Panel **yalnızca teşhis eder**. Kullanıcı silme, ban, kilit sıfırlama gibi
yazma işlemleri kasten dışarıda bırakıldı: canlı veriye bakan, yerel, tek
kullanıcılı bir araçta yanlış tıklamanın maliyeti okuma hatasından çok daha
yüksek. Müdahale gerekiyorsa Supabase Dashboard'dan bilinçli olarak yapılır.

---

## Geliştirme

```bash
npx tsc -b        # tip denetimi
npm run build     # üretim derlemesi (dist/, gitignored)
```

`src/types.ts` migration 0070/0071/0072'deki `returns table` imzalarının birebir
karşılığıdır. SQL'de bir sütun adı değişirse burada da değişmeli — tip hatası
derlemede yakalar.
