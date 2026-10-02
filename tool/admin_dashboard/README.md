# sandık · kontrol paneli

Canlı Supabase'e bakan, **yalnızca yerelde çalışan** yönetici paneli. İki soruyu
hızlı cevaplar:

- **Büyüme** — *"İndirenlerin kaçı kayıt ekranına geliyor, kaçı kayıt oluyor, ilk
  girişini yapıyor, ilk varlığını ekliyor; kaybettiklerimiz nerede ve neden?"*
  (Kayıt hunisi, açılış ekranı — 2026-10-02.)
- **Destek** — *"Müşteri X hata alıyor — nerede, ne zaman, neden?"*

Mağazaya, sunucuya veya CI'ya **girmez**. `npm run dev` ile açılır, 127.0.0.1'e
bağlanır, kapatınca biter.

---

## Açmak

**Masaüstündeki `sandık kontrol paneli` kısayoluna çift tıkla.** Panel her
açılışta **`main`'in son hâliyle** gelir:

1. Kısayol `%LOCALAPPDATA%\sandik-panel\guncel_baslat.ps1`'i çalıştırır.
2. Betik, yalnızca panele ayrılmış `C:\projects\PortfoyTakip-panel`
   klasörünü (ayrık HEAD) `origin/main`'e çeker. Klasör yoksa kendisi kurar
   ve `.env.local`'ı ana klasörden kopyalar. `package-lock.json` değiştiyse
   bağımlılıkları yeniden kurar. Ağ yoksa mevcut sürümle açılır.
3. Sonra `baslat.cmd` dev sunucusunu kaldırır ve hazır olunca tarayıcıyı açar.

Neden ayrı klasör: geliştirme klasörü çoğu zaman bir dalda ve işlenmemiş
değişikliklerle durur; kısayol oradan açsaydı paneli o dalın hâliyle
görürdün, sıfırlasaydı işini silerdi. Betik bu yüzden **dalda duran ya da
değişiklik taşıyan klasöre dokunmaz**, yalnızca uyarır.

Neden betik depo dışında: panel klasörünü güncelleyen betik o klasörün
içinde dursaydı kendi dosyasını değiştirirdi. Depodaki
`tool/admin_dashboard/guncel_baslat.ps1` asıl kaynaktır; dışarıdaki kopya her
açılışta ondan tazelenir.

Açılan **konsol penceresi sunucunun kendisidir** — görev çubuğunda simge
durumunda durur. Paneli kapatmak için o pencereyi kapat; böylece panel arka
planda unutulmuş halde canlı veriye bağlı kalmaz. Kısayola ikinci kez
basarsan yeni sunucu açılmaz, var olan sekmeye döner.

Kısayolu yeniden oluşturmak (taşındıysa veya silindiyse):

```powershell
$dir = Join-Path $env:LOCALAPPDATA 'sandik-panel'
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item 'C:\projects\PortfoyTakip	ooldmin_dashboard\guncel_baslat.ps1' $dir
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'sandik kontrol paneli.lnk'))
$s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell1.0\powershell.exe"
$s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$dir\guncel_baslat.ps1`""
$s.WorkingDirectory = $dir
$s.IconLocation = 'C:\projects\PortfoyTakip-panel	ooldmin_dashboard\panel.ico,0'
$s.WindowStyle = 7
$s.Save()
```

Yalnızca güncellemek (paneli açmadan):
`powershell -File "$env:LOCALAPPDATA\sandik-panel\guncel_baslat.ps1" -YalnizGuncelle`

> `baslat.cmd` **CRLF satır sonlarıyla ve saf ASCII** olarak tutulur. LF ile
> kaydedilirse batch yorumlayıcısı `rem` satırlarını bölüp anlamsız hatalar
> verir (`'em' is not recognized...`). `guncel_baslat.ps1` de saf ASCII:
> Windows PowerShell 5.1 BOM'suz dosyayı ANSI okur.

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
| **Kayıt hunisi** | "Kaç kişi indirdi → kayıt ekranına geldi → kayıt oldu → ilk girişini yaptı → ilk varlığını ekledi?" Adım başına sayı, bir önceki adımdan geçiş oranı ve süresi (medyan/p90), ara adımlar (form, kod, yasal onay, ad, tur, ana ekran), gün gün eğri, platform/sürüm/giriş yolu kırılımı, **neden düştüğü** (kayıt sırasındaki hata kodları + ilk 48 saatteki hatalar) ve kişi kişi yolculuklar → satıra tıkla: adım adım zaman çizelgesi → künyeye geç. |
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

### Kayıt hunisi (migration 0097)

İki görünüm, iki farklı soru:

| Görünüm | Kimler | Ne zaman dolu |
|---|---|---|
| **Kurulumdan** | Bu dönemde **başlayan** kurulumlar | Yalnızca huni kaydı olan sürümden (0097 istemcisi) itibaren — beş adımın hepsi |
| **Hesaptan** | Bu dönemde **açılan** hesaplar | Tüm sürümler; kayıt öncesi adımlar yalnızca yeni sürümle gelenlerde |

- **"İndirdi" mağaza sayısı değildir.** Mağaza indirmeleri App Store Connect /
  Play Console'dadır. Buradaki ilk adım, uygulamayı **en az bir kez açan** yeni
  kurulumdur. Bu sürüme *güncelleme* ile gelen cihaz huniye girmez.
- Kayıt (`auth.users`: e-posta onayı ya da Apple/Google), ilk giriş
  (`auth.audit_log_entries`) ve ilk varlık (`assets.created_at`) **sunucu
  kayıtlarından** okunur; istemci olayı kaybolsa da sayı düşmez.
- **İlk varlık "tahmini"** işaretliyse: satır 0095 öncesinden (damga alış
  tarihi) ya da hesaptan önceki bir tarihten geliyor; hesap açılışına
  kıstırılır, süre ortalamalarına girmez.
- **Mevcut hesabıyla dönen** (yeniden yükleme / yeni telefon) kurulumlar yeni
  kullanıcı sayılmaz; huninin altında ayrı gösterilir.
- Kayıt öncesi kimlik cihazda üretilen **rastgele kurulum kimliğidir** (cihaz/
  reklam kimliği yok). Kayıt hatalarında yalnızca *aşama:kod* tutulur
  (`kayit:auth_weak_password`), mesaj asla. Saklama 400 gün
  (`cleanup_db_logs`).
- Yazma ucu `huni_kaydet` oturumsuz çağrılabilir (huninin üst yarısı tanımı
  gereği giriş öncesi); sınırları migration başlığında: kurulum başına 40,
  sunucu geneli dakikada 300 satır.

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

Tüm okuma dört migration'daki RPC'ler üzerinden:
`0070_admin_dashboard_rpc.sql` (teşhis), `0071_db_logs_seans_cihaz.sql`
(seans/cihaz/zaman), `0072_db_logs_hata_detayi.sql` (hata detayı,
stack trace, push token) ve `0097_kayit_hunisi.sql` (`admin_huni_*`: özet,
günlük, kırılım, yolculuklar, hatalar). Her biri:

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

`src/types.ts` migration 0070/0071/0072/0097'deki `returns table` imzalarının birebir
karşılığıdır. SQL'de bir sütun adı değişirse burada da değişmeli — tip hatası
derlemede yakalar.
