"""
Legal + landing HTML builder for GitHub Pages (docs/).

Reads Markdown files from legal/ and store_listing/, wraps them in the shared
Sandık-branded HTML layout, and writes them into docs/ at the URL paths
referenced by app/legal docs.

Run from repo root:
    python docs/_build_legal.py
"""
from pathlib import Path
import markdown

ROOT = Path(__file__).parent.parent
DOCS = ROOT / "docs"
LEGAL = ROOT / "legal"

# Layout ─ tek CSS, marka renkleri (Sandık amber/gold/dark), mobile-first.
LAYOUT = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} — sandık</title>
<meta name="description" content="{desc}">
<link rel="icon" href="/sandikapp/favicon.svg" type="image/svg+xml">
<style>
:root {{
  --bg: #0A1E15;
  --surface: #10281E;
  --surface-2: #1A3D2E;
  --border: rgba(255,255,255,0.06);
  --text: rgba(255,255,255,0.90);
  --text-58: rgba(255,255,255,0.58);
  --text-36: rgba(255,255,255,0.36);
  --amber: #F5A623;
  --gold: #F5C842;
  --gain: #6BB77B;
  --loss: #E86A5E;
}}
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; padding: 0; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'DM Sans', sans-serif; line-height: 1.6; }}
.container {{ max-width: 720px; margin: 0 auto; padding: 24px 20px 64px; }}
header {{ display: flex; align-items: center; gap: 12px; padding: 20px 0 32px; border-bottom: 1px solid var(--border); margin-bottom: 32px; }}
header .logo {{ width: 40px; height: 40px; background: linear-gradient(135deg, var(--gold), var(--amber)); border-radius: 10px; display: flex; align-items: center; justify-content: center; font-weight: 900; color: #0A1E15; font-size: 20px; }}
header .brand {{ font-size: 22px; font-weight: 800; letter-spacing: -0.5px; }}
header .brand small {{ font-size: 12px; color: var(--text-58); font-weight: 500; display: block; letter-spacing: 0; }}
h1 {{ font-size: 28px; font-weight: 800; letter-spacing: -0.5px; margin: 0 0 8px; }}
h2 {{ font-size: 20px; font-weight: 700; margin: 32px 0 12px; color: var(--gold); }}
h3 {{ font-size: 16px; font-weight: 700; margin: 20px 0 8px; color: var(--text); }}
p, li {{ font-size: 15px; }}
a {{ color: var(--amber); text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
code {{ background: var(--surface); padding: 2px 6px; border-radius: 4px; font-size: 13px; font-family: 'Fira Code', 'Consolas', monospace; }}
pre {{ background: var(--surface); padding: 16px; border-radius: 8px; overflow-x: auto; border: 1px solid var(--border); }}
pre code {{ background: transparent; padding: 0; }}
blockquote {{ border-left: 3px solid var(--amber); padding: 8px 14px; margin: 16px 0; background: rgba(245,166,35,0.06); border-radius: 0 6px 6px 0; color: var(--text); }}
hr {{ border: 0; height: 1px; background: var(--border); margin: 32px 0; }}
table {{ width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px; }}
th, td {{ padding: 10px 12px; text-align: left; border-bottom: 1px solid var(--border); }}
th {{ background: var(--surface); font-weight: 700; color: var(--gold); }}
tr:hover td {{ background: rgba(255,255,255,0.02); }}
ul, ol {{ padding-left: 20px; }}
li {{ margin: 6px 0; }}
footer {{ margin-top: 48px; padding-top: 24px; border-top: 1px solid var(--border); text-align: center; font-size: 12px; color: var(--text-36); }}
footer a {{ color: var(--text-58); margin: 0 8px; }}
input[type="text"], input[type="email"], textarea {{ width: 100%; padding: 10px 12px; background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); font-family: inherit; font-size: 14px; }}
input:focus, textarea:focus {{ outline: none; border-color: var(--amber); }}
button {{ background: var(--amber); color: #0A1E15; border: 0; padding: 12px 24px; border-radius: 8px; font-size: 15px; font-weight: 700; cursor: pointer; }}
button:hover {{ opacity: 0.9; }}
.checkbox-row {{ display: flex; align-items: flex-start; gap: 10px; margin: 12px 0; font-size: 14px; color: var(--text-58); }}
.checkbox-row input {{ width: auto; margin-top: 3px; }}
</style>
</head>
<body>
<div class="container">
<header>
  <div class="logo">S</div>
  <div class="brand">sandık<small>{subtitle}</small></div>
</header>
{body}
<footer>
  sandık — <a href="/sandikapp/">Ana Sayfa</a> · <a href="/sandikapp/privacy">Gizlilik</a> · <a href="/sandikapp/terms">Kullanım</a> · <a href="/sandikapp/data-deletion">Hesap Silme</a>
</footer>
</div>
</body>
</html>
"""

def build(md_path: Path, out_path: Path, title: str, subtitle: str, desc: str, lang: str = "tr"):
    src = md_path.read_text(encoding="utf-8")
    html_body = markdown.markdown(src, extensions=["tables", "fenced_code"])
    html = LAYOUT.format(
        title=title, subtitle=subtitle, desc=desc, body=html_body, lang=lang,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    print(f"  -> {out_path.relative_to(ROOT)}")

# ── Legal HTML pages ────────────────────────────────────────────────────────
pages = [
    # (source, output, title, subtitle, description, lang)
    (LEGAL / "tr/PRIVACY_POLICY.md",       DOCS / "privacy/index.html",      "Gizlilik Politikası",       "Gizlilik Politikası",      "Sandık uygulamasının gizlilik politikası — KVKK ve GDPR uyumlu.", "tr"),
    (LEGAL / "en/PRIVACY_POLICY.md",       DOCS / "privacy-en/index.html",   "Privacy Policy",            "Privacy Policy",           "Sandık app privacy policy — GDPR compliant.", "en"),
    (LEGAL / "tr/TERMS_OF_SERVICE.md",     DOCS / "terms/index.html",        "Kullanım Koşulları",        "Kullanım Koşulları",       "Sandık uygulamasının kullanım koşulları.", "tr"),
    (LEGAL / "en/TERMS_OF_SERVICE.md",     DOCS / "terms-en/index.html",     "Terms of Service",          "Terms of Service",         "Sandık app terms of service.", "en"),
    (LEGAL / "tr/KVKK_AYDINLATMA_METNI.md",DOCS / "legal/kvkk/index.html",   "KVKK Aydınlatma Metni",    "KVKK",                     "KVKK Madde 10 aydınlatma yükümlülüğü.", "tr"),
    (LEGAL / "en/GDPR_NOTICE.md",          DOCS / "legal/gdpr/index.html",   "GDPR Notice",               "GDPR",                     "GDPR notice for EU/EEA users of Sandık.", "en"),
    (LEGAL / "tr/ACIK_RIZA_METNI.md",      DOCS / "legal/acik-riza/index.html","Açık Rıza Metni",         "Açık Rıza",                "KVKK Madde 5(1) ve 9(1) yurt dışı aktarım açık rıza metni.", "tr"),
    (LEGAL / "tr/COKEZ_VE_DEPOLAMA.md",    DOCS / "legal/depolama/index.html","Çerezler ve Yerel Depolama","Depolama",               "Yerel depolama ve çerez kullanımı bilgilendirmesi.", "tr"),
    (LEGAL / "DATA_DELETION_REQUEST_FORM.md", DOCS / "data-deletion/index.html","Hesap Silme Talebi",    "Hesap Silme",              "Hesap silme talep formu — 30 gün içinde işleme alınır.", "tr"),
    (LEGAL / "DATA_DELETION_REQUEST_FORM.md", DOCS / "data-request/index.html","Data Access Request",   "Data Request",             "Data access/deletion request under GDPR / KVKK.", "en"),
]

print("Building legal pages...")
for src, out, title, subtitle, desc, lang in pages:
    build(src, out, title, subtitle, desc, lang)

# ── Landing page ────────────────────────────────────────────────────────────
LANDING = """<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>sandık — Portföy Takibi</title>
<meta name="description" content="sandık, tüm yatırımlarını tek ekranda takip et. Hisse, fon, döviz, altın, emtia.">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<style>
:root {
  --bg: #0A1E15;
  --surface: #10281E;
  --surface-2: #1A3D2E;
  --border: rgba(255,255,255,0.06);
  --text: rgba(255,255,255,0.90);
  --text-58: rgba(255,255,255,0.58);
  --amber: #F5A623;
  --gold: #F5C842;
  --gain: #6BB77B;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'DM Sans', sans-serif; line-height: 1.6; min-height: 100vh; }
.hero { max-width: 960px; margin: 0 auto; padding: 80px 24px 60px; text-align: center; }
.logo-hero { width: 96px; height: 96px; background: linear-gradient(135deg, var(--gold), var(--amber)); border-radius: 24px; display: inline-flex; align-items: center; justify-content: center; font-weight: 900; color: #0A1E15; font-size: 52px; margin-bottom: 24px; box-shadow: 0 12px 40px rgba(245,166,35,0.25); }
h1 { font-size: 48px; font-weight: 800; letter-spacing: -1.5px; margin: 0 0 12px; }
.tagline { font-size: 20px; color: var(--text-58); margin-bottom: 40px; max-width: 560px; margin-left: auto; margin-right: auto; }
.features { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin: 40px 0; }
.feature { background: var(--surface); padding: 24px 20px; border-radius: 16px; border: 1px solid var(--border); text-align: left; }
.feature h3 { color: var(--gold); font-size: 16px; margin-bottom: 8px; }
.feature p { font-size: 14px; color: var(--text-58); }
.legal-nav { margin-top: 60px; padding: 32px; background: var(--surface); border-radius: 16px; border: 1px solid var(--border); text-align: left; max-width: 640px; margin-left: auto; margin-right: auto; }
.legal-nav h2 { color: var(--gold); font-size: 16px; margin-bottom: 16px; font-weight: 700; }
.legal-nav ul { list-style: none; padding: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 8px 24px; }
.legal-nav a { color: var(--text); text-decoration: none; font-size: 14px; padding: 6px 0; display: block; border-bottom: 1px solid var(--border); }
.legal-nav a:hover { color: var(--amber); }
footer { text-align: center; padding: 40px 20px; font-size: 12px; color: rgba(255,255,255,0.36); }
@media (max-width: 600px) {
  h1 { font-size: 32px; }
  .tagline { font-size: 16px; }
  .legal-nav ul { grid-template-columns: 1fr; }
}
</style>
</head>
<body>
<div class="hero">
  <div class="logo-hero">S</div>
  <h1>sandık</h1>
  <p class="tagline">Hisse, fon, döviz, altın ve emtia varlıklarını tek ekranda takip et. TradingView tarzı profesyonel grafik. KVKK ve GDPR uyumlu.</p>

  <div class="features">
    <div class="feature">
      <h3>📊 Profesyonel Grafik</h3>
      <p>Pinch zoom, crosshair, dinamik zaman aralıkları. Portföy performansın anlık ve tarihsel.</p>
    </div>
    <div class="feature">
      <h3>👥 Ortak Paylaşımı</h3>
      <p>Aile veya iş ortaklarınla portföyünü güvenli paylaş. İstediğin zaman sonlandır.</p>
    </div>
    <div class="feature">
      <h3>🏆 Yarış (Opsiyonel)</h3>
      <p>Ortaklarınla getiri sıralaması + anonim genel percentile. Sadece opt-in ile aktif.</p>
    </div>
    <div class="feature">
      <h3>🔒 Gizlilik</h3>
      <p>KVKK + GDPR uyumlu. Uçtan uca şifreli. Hesabını istediğin zaman sil.</p>
    </div>
  </div>

  <div class="legal-nav">
    <h2>Hukuki & Destek</h2>
    <ul>
      <li><a href="privacy/">Gizlilik Politikası (TR)</a></li>
      <li><a href="privacy-en/">Privacy Policy (EN)</a></li>
      <li><a href="terms/">Kullanım Koşulları</a></li>
      <li><a href="terms-en/">Terms of Service</a></li>
      <li><a href="legal/kvkk/">KVKK Aydınlatma</a></li>
      <li><a href="legal/gdpr/">GDPR Notice</a></li>
      <li><a href="legal/acik-riza/">Açık Rıza Metni</a></li>
      <li><a href="legal/depolama/">Depolama Bilgisi</a></li>
      <li><a href="data-deletion/">Hesap Silme (TR)</a></li>
      <li><a href="data-request/">Data Request (EN)</a></li>
    </ul>
  </div>
</div>

<footer>
  © sandık · <a href="mailto:sandikapp.destek@gmail.com" style="color:inherit">sandikapp.destek@gmail.com</a>
</footer>
</body>
</html>
"""

(DOCS / "index.html").write_text(LANDING, encoding="utf-8")
print(f"  -> docs/index.html")

# ── Favicon (basic S with amber bg) ────────────────────────────────────────
FAVICON = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<rect width="64" height="64" rx="12" fill="#F5A623"/>
<text x="50%" y="50%" dominant-baseline="central" text-anchor="middle" font-family="-apple-system,sans-serif" font-size="40" font-weight="900" fill="#0A1E15">S</text>
</svg>"""
(DOCS / "favicon.svg").write_text(FAVICON, encoding="utf-8")
print(f"  -> docs/favicon.svg")

print("\nDone. To serve locally: python -m http.server 8000 --directory docs")
print("GitHub Pages settings: Source = main branch / docs folder")
