# Videolardaki ses — lisans kaydı (doğrulandı 2026-09-18)

| Kaynak | Kullanıldığı yer | Lisans | Ticari | Atıf | Ücret |
|---|---|---|---|---|---|
| **Müzik** — "Happy Beats / Business Moves" vol-9 ve vol-11, Sascha Ende (ende.app, eski filmmusic.io) | brag-output* videolarının tamamı | **CC BY 4.0** + yazarın "atıf zorunlu değil" muafiyeti (ende.app/en/standard-license) | ✅ "Commercial use is allowed as well" | İsteğe bağlı | Yok, tüm planlar 0 € |
| **SFX** — Kenney.nl (drop, impact, card, switch) | brag-output* videoları | **CC0** (kamu malı) | ✅ | Yok | Yok |
| **Sentetik yatak/whoosh/pop** — `scripts/gen-sfx.mjs` | Remotion kurgusu (`out/sandik_preview_iphone.mp4`) | Kendi üretimimiz | ✅ | — | — |
| **Anlatım** — edge-tts (Microsoft Edge çevrimiçi TTS) | yalnızca `brag-output/` anlatımlı sürüm (YEDEK, teslim değil) | Belirsiz (resmi API değil) | ⚠️ | — | — |

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
