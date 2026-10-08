#!/usr/bin/env python3
"""Eurobond kaynaklarının yanıt BİÇİMİNİ döker (2026-10-08).

`kaynak_olcum.py` erişimi ve hızı ölçtü; ayrıştırıcı yazmak için yanıtın
kendisi gerekiyor ve bulut kabı bu hostlara gidemiyor. Yalnızca herkese
açık fiyat sayfaları/uçları; anahtar, çerez, secret yok.
"""
import html
import json
import re
import urllib.error
import urllib.request

UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0 Safari/537.36')


def al(url, extra=None):
    h = {'User-Agent': UA, 'Accept': 'application/json, text/html'}
    h.update(extra or {})
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=20) as r:
            return r.status, r.read().decode('utf-8', 'ignore')
    except urllib.error.HTTPError as e:
        return e.code, (e.read() or b'').decode('utf-8', 'ignore')
    except Exception as e:
        return type(e).__name__, ''


def baslik(t):
    print('\n' + '=' * 8 + ' ' + t + ' ' + '=' * 8, flush=True)


# ── Ziraat: tablo satırları ─────────────────────────────────────────────────
baslik('Ziraat eurobond tablosu')
kod, s = al('https://www.ziraatbank.com.tr/tr/bireysel/yatirim/eurobond')
print('durum', kod, 'uzunluk', len(s))
satirlar = re.findall(r'<tr[^>]*>(.*?)</tr>', s, re.S | re.I)
print('tr sayısı', len(satirlar))
for tr in satirlar[:60]:
    hucreler = [html.unescape(re.sub(r'<[^>]+>', '', c)).strip()
                for c in re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', tr, re.S | re.I)]
    hucreler = [re.sub(r'\s+', ' ', c) for c in hucreler]
    if hucreler:
        print(' | '.join(hucreler))
# Tablo başlığı/tarih ipuçları
for m in re.finditer(r'(\d{2}[./]\d{2}[./]\d{4}[^<]{0,40})', s):
    print('tarih ipucu:', m.group(1)[:60])
    break
# Ayrı JSON/ajax ucu var mı?
for m in set(re.findall(r'["\'](/[^"\']*(?:[Ee]urobond|[Ff]iyat|[Oo]ran)[^"\']*)["\']', s)):
    print('uç adayı:', m[:120])

# ── İş Bankası: tablo dinamik mi? ───────────────────────────────────────────
baslik('İş Bankası eurobond')
kod, s = al('https://www.isbank.com.tr/eurobond')
print('durum', kod, 'uzunluk', len(s))
for m in sorted(set(re.findall(r'["\']([^"\']*(?:api|ajax|json|Eurobond|eurobond)[^"\']*)["\']', s)))[:40]:
    print('uç adayı:', m[:140])

# ── Börse Frankfurt: tek fiyat (tam JSON) ve diğer uçlar ────────────────────
ISINLER = ['US900123DF45', 'US900123DQ00', 'US900123DG28', 'US900123CY43', 'XS1028951264']
for isin in ISINLER:
    baslik(f'BF price_information {isin}')
    for mic in ['XFRA', 'XETR', 'XBER', 'XSTU']:
        kod, s = al(f'https://api.boerse-frankfurt.de/v1/data/price_information/single?isin={isin}&mic={mic}')
        print(mic, kod, s[:700])

baslik('BF ana veri / geçmiş adayları')
adaylar = [
    'https://api.boerse-frankfurt.de/v1/data/bond_master_data?isin=US900123DF45',
    'https://api.boerse-frankfurt.de/v1/data/master_data_bond?isin=US900123DF45',
    'https://api.boerse-frankfurt.de/v1/data/bond_key_data?isin=US900123DF45&mic=XFRA',
    'https://api.boerse-frankfurt.de/v1/data/instrument_information?slug=US900123DF45&instrumentType=BOND',
    'https://api.boerse-frankfurt.de/v1/data/quote_box/single?isin=US900123DF45&mic=XFRA',
    'https://api.boerse-frankfurt.de/v1/data/price_history?isin=US900123DF45&mic=XFRA&minDate=2026-09-01&maxDate=2026-10-07&limit=50&offset=0',
    'https://api.boerse-frankfurt.de/v1/data/price_history?offset=0&limit=50&isin=US900123DF45&mic=XFRA&minDate=2026-09-01&maxDate=2026-10-07&cleanSplit=false&cleanPayout=false&cleanSubscription=false',
    'https://api.boerse-frankfurt.de/v1/tradingview/history?symbol=XFRA:US900123DF45&resolution=1D&from=1756684800&to=1759795200',
    'https://api.boerse-frankfurt.de/v1/data/related_indices?isin=US900123DF45',
    'https://api.boerse-frankfurt.de/v1/search/equity_search',
    'https://api.live.deutsche-boerse.com/v1/data/price_information/single?isin=US900123DF45&mic=XFRA',
]
for u in adaylar:
    kod, s = al(u)
    print('\n', u, '\n  ->', kod, s[:600].replace('\n', ' '))

baslik('Deutsche Börse ürün sayfası JSON ipuçları')
kod, s = al('https://live.deutsche-boerse.com/anleihe/us900123df45-tuerkei-republik-9-875-22-28')
for anahtar in ['coupon', 'Kupon', 'maturity', 'Fälligkeit', 'interestRate', 'accrued',
                'Stückzinsen', 'bid', 'ask', 'yield', 'Rendite']:
    for m in re.finditer(re.escape(anahtar), s):
        print(anahtar, '…', re.sub(r'\s+', ' ', s[m.start():m.start() + 160]))
        break
for m in sorted(set(re.findall(r'https://api[^"\'\s]+', s)))[:20]:
    print('api ipucu:', m[:160])

baslik('Hazine getiri XML örneği')
kod, s = al('https://home.treasury.gov/resource-center/data-chart-center/interest-rates/pages/xml'
            '?data=daily_treasury_yield_curve&field_tdr_date_value_month=202610')
print(kod, s[:1500])
