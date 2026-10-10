#!/usr/bin/env python3
"""BIST hisse evrenini canlı kaynaklardan çıkarır (2026-10-10, salt okunur).

Neden: `bist100StocksMap` elle yazılmış bir listeydi; borsada işlem gören
hisselerin bir kısmı (ve BIST 100'ün bir kısmı) eksikti. Bulut kabı finans
hostlarına çıkamıyor; liste GitHub Actions runner'ında ölçülür.
Kaynaklar: TradingView tarayıcısı (evren + BIST 100 üyeliği), KAP (Türkçe
unvan), Yahoo (uygulamanın fiyatı gerçekten okuyabildiği mi). Anahtarsız.
Çıktı: bist_evren.json (iş eseri) + log özeti.
"""
import json, sys, urllib.request, concurrent.futures as cf

UA = {'User-Agent': 'Mozilla/5.0', 'Content-Type': 'application/json'}

def post(url, body):
    r = urllib.request.Request(url, data=json.dumps(body).encode(), headers=UA)
    return json.load(urllib.request.urlopen(r, timeout=30))

def get(url):
    r = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    return urllib.request.urlopen(r, timeout=20).read()

def tv(extra):
    body = {
        'filter': [{'left': 'exchange', 'operation': 'equal', 'right': 'BIST'}],
        'columns': ['name', 'description', 'type', 'subtype', 'close', 'volume'],
        'range': [0, 2000],
        **extra,
    }
    d = post('https://scanner.tradingview.com/turkey/scan', body)
    return [x['d'] for x in d.get('data', [])]

out = {}
try:
    hepsi = tv({})
    out['tv_hepsi'] = hepsi
    print('TV satır:', len(hepsi))
    from collections import Counter
    print('TV tür/alt tür:', Counter((r[2], r[3]) for r in hepsi).most_common(20))
except Exception as e:
    print('TV hata', e)
try:
    x100 = tv({'symbols': {'symbolset': ['SYML:BIST;XU100']}})
    out['xu100'] = [r[0] for r in x100]
    print('XU100:', len(x100), ' '.join(sorted(out['xu100'])))
except Exception as e:
    print('XU100 hata', e)
try:
    xt = tv({'symbols': {'symbolset': ['SYML:BIST;XUTUM']}})
    out['xutum'] = [r[0] for r in xt]
    print('XUTUM:', len(xt))
except Exception as e:
    print('XUTUM hata', e)

# KAP: Türkçe unvanlar.
for url in ['https://www.kap.org.tr/tr/api/company/generic/BIST/A',
            'https://www.kap.org.tr/tr/bist-sirketler']:
    try:
        b = get(url)
        out.setdefault('kap', {})[url] = b.decode('utf-8', 'replace')[:3_000_000]
        print('KAP', url, len(b))
    except Exception as e:
        print('KAP hata', url, e)

# Yahoo: uygulama .IS fiyatını Yahoo'dan okur — her sembol okunabiliyor mu?
semboller = sorted({r[0] for r in out.get('tv_hepsi', []) if r[2] in ('stock', 'fund', 'dr')})
def yahoo(s):
    try:
        d = json.loads(get(f'https://query1.finance.yahoo.com/v8/finance/chart/{s}.IS?range=5d&interval=1d'))
        m = d['chart']['result'][0]['meta']
        return s, m.get('regularMarketPrice'), m.get('longName') or m.get('shortName')
    except Exception:
        return s, None, None
with cf.ThreadPoolExecutor(12) as ex:
    out['yahoo'] = {s: [p, n] for s, p, n in ex.map(yahoo, semboller)}
print('Yahoo fiyatlı:', sum(1 for v in out['yahoo'].values() if v[0]), '/', len(semboller))
json.dump(out, open('bist_evren.json', 'w'), ensure_ascii=False)

# Log dökümü (eser indirilemeyen ortamlar için): sembol|tür|alt tür|XU100|yahoo fiyat|TV adı|Yahoo adı
x100 = set(out.get('xu100', []))
print('KAP durumları:', {k: len(v) for k, v in out.get('kap', {}).items()})
print('=== DÖKÜM BAŞI ===')
for r in sorted(out.get('tv_hepsi', []), key=lambda r: r[0]):
    y = out['yahoo'].get(r[0], [None, None])
    print('|'.join(str(v) for v in [r[0], r[2], r[3], int(r[0] in x100), int(bool(y[0])), r[1], y[1]]))
print('=== DÖKÜM SONU ===')
