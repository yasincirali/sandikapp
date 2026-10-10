# Videolardaki ses — lisans kaydı (doğrulandı 2026-09-18)

| Kaynak | Kullanıldığı yer | Lisans | Ticari | Atıf | Ücret |
|---|---|---|---|---|---|
| **Müzik** — "Happy Beats / Business Moves" vol-9 ve vol-11, Sascha Ende (ende.app, eski filmmusic.io) | brag-output* videolarının tamamı | **CC BY 4.0** + yazarın "atıf zorunlu değil" muafiyeti (ende.app/en/standard-license) | ✅ "Commercial use is allowed as well" | İsteğe bağlı | Yok, tüm planlar 0 € |
| **SFX** — Kenney.nl (drop, impact, card, switch) | brag-output* videoları | **CC0** (kamu malı) | ✅ | Yok | Yok |
| **Sentetik yatak/whoosh/pop** — `scripts/gen-sfx.mjs` | Remotion kurgusu (`out/sandik_preview_iphone.mp4`) | Kendi üretimimiz | ✅ | — | — |
| **Anlatım** — EMA Lightning 1.0.4 (Canberk Aslan, huggingface.co/canberkkkkkk/ema-lightning), yerelde `scripts/seslendir_ema.py` | anlatımlı videolar (2026-10-10'dan itibaren varsayılan, `vo/m_*.wav`) | **Apache 2.0** — ağırlıklar + kod | ✅ "Commercial use included" | Zorunlu değil (Apache 2.0 yalnız kod/ağırlık dağıtırken NOTICE ister; üretilen ses dağıtım değildir) | Yok |
| **Anlatım** — edge-tts (Microsoft Edge çevrimiçi TTS) | yalnızca `brag-output/` eski anlatımlı sürüm (`a_`/`e_`, YEDEK, teslim değil) | Belirsiz (resmi API değil) | ⚠️ | — | — |

## Müzik için ende.app'in iki yasağı
1. Parçayı **kendi şarkın gibi** Spotify/Apple Music'e yükleme.
2. **YouTube Content ID**'ye veya benzeri sisteme kaydetme.

Mağaza önizlemesi ve sosyal medya tanıtımı "müziğin bir işin parçası olması" şartını
karşılıyor (site: "The music must be part of your work — background, intro, etc.").
Yazar tekil yazılı onay vermiyor; CC BY 4.0 metni onayın kendisidir (FAQ).

## Önerilen (zorunlu değil) atıf
Uygulama içi "Hakkında/Lisanslar" ekranına veya mağaza açıklamasına:
```
Music: "Happy Beats / Business Moves" by Sascha Ende (ende.app), CC BY 4.0
Sound effects: Kenney.nl, CC0
```

## Sorumluluk notu
ende.app: "use is at your own risk"; bazı parçalarda yapay zekâ kullandığını ve
benzer bir melodinin başka yerde bulunmayacağını garanti edemediğini belirtiyor.
Risk düşük ama sıfır değil; sıfır istiyorsan `public/sfx/pad.wav` (kendi sentetik
yatağımız) ile değiştirip yeniden render etmek 1 satırlık iş (`#music` src).

## Yapay zekâ sesi beyanı (EMA Lightning)
Model kartının "Responsible use" bölümü, yayımlanan sesin yapay zekâ ile
üretildiğinin söylenmesini istiyor (AB Yapay Zekâ Yasası'nın şeffaflık
maddesine atıfla). Lisans şartı değil, model sahibinin talebi. Ucuz karşılığı:
mağaza açıklamasına ya da video sonuna küçük bir satır —
`Seslendirme yapay zekâ ile üretilmiştir.` Gerçek bir kişinin sesi gibi
sunulmaz; tek, sentetik bir sestir (ses klonlama yok).
