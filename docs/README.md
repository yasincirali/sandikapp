# sandık — GitHub Pages Site

Bu klasör https://yasincirali.github.io/sandikapp/ adresinde yayınlanan sandık landing + legal sayfalarını içerir.

## Yayınlama (bir kere)

1. GitHub repo: `sandikapp` (yoksa oluştur ve bu repo'yu push et — ya da mevcut `PortfoyTakip` repo'yu `sandikapp` olarak rename et; ancak URL'ler `/sandikapp/` prefix ile yazıldığı için repo adı **`sandikapp`** olmalı)
2. Repo Settings → Pages
3. Source: **Deploy from a branch**
4. Branch: `main` / `/docs` folder → Save
5. 1-2 dakika içinde https://yasincirali.github.io/sandikapp/ yayınlanır

## HTML'leri yeniden üret

Legal Markdown dosyalarını değiştirdiysen (`legal/tr/*.md`, `legal/en/*.md`), HTML'leri yeniden derle:

```bash
python docs/_build_legal.py
```

Bu komut `_build_legal.py` içindeki sayfa listesindeki her Markdown'ı okur, ortak layout'a sarar, `docs/` altına ilgili URL path'ine yazar.

## Yapı

```
docs/
├── index.html               → https://yasincirali.github.io/sandikapp/
├── favicon.svg
├── privacy/index.html       → /privacy
├── privacy-en/index.html    → /privacy-en
├── terms/index.html         → /terms
├── terms-en/index.html      → /terms-en
├── legal/kvkk/index.html    → /legal/kvkk
├── legal/gdpr/index.html    → /legal/gdpr
├── legal/acik-riza/index.html → /legal/acik-riza
├── legal/depolama/index.html  → /legal/depolama
├── data-deletion/index.html → /data-deletion   (Play Console zorunlu)
├── data-request/index.html  → /data-request    (GDPR)
├── _build_legal.py          → build script
├── faz10-draw-tools-plan.md → dev notu, Pages'te de render edilir ama önemsiz
└── README.md                → bu dosya
```

## Play Console form değerleri

Yayın sonrası Play Console → App content → Data Safety'e giren URL'ler:
- **Privacy policy URL:** https://yasincirali.github.io/sandikapp/privacy
- **Data deletion URL:** https://yasincirali.github.io/sandikapp/data-deletion

Form referansı: [store_listing/DATA_SAFETY_FORM.md](../store_listing/DATA_SAFETY_FORM.md)
