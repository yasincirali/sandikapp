"""Mum (OHLC) kaynaklarının canlı ölçümü (2026-10-10).

Soru: hangi varlık türü hangi mum aralığını (1 dk, 1 sa, 4 sa, gün, hafta,
ay) GERÇEK açılış/en yüksek/en düşük/kapanış ile verebiliyor? Bulut kabı
finans hostlarını reddettiği için GitHub Actions'tan koşar
(`kaynak-olcum.yml`). Salt okunur, anahtarsız; log herkese açık.

Ölçüt: bar sayısı, ilk/son damga, "gerçek OHLC" oranı (en yüksek > en
düşük olan bar yüzdesi — kapanıştan türetilmiş seride bu %0'dır).
"""
import json
import time
import urllib.request
from datetime import datetime, timezone

UA = 'Mozilla/5.0 (compatible; sandik-olcum/1.0)'


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': 'application/json'})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=20) as r:
        body = r.read()
    return json.loads(body), time.time() - t0


def ts(s):
    return datetime.fromtimestamp(s, tz=timezone.utc).strftime('%Y-%m-%d %H:%M')


def yahoo(sym, interval, gun):
    son = int(time.time())
    bas = son - int(gun * 86400)
    url = (f'https://query1.finance.yahoo.com/v8/finance/chart/{sym}'
           f'?interval={interval}&period1={bas}&period2={son}&includePrePost=false')
    try:
        body, sure = get(url)
    except Exception as e:  # noqa: BLE001
        return f'{sym:10} {interval:4} HATA {type(e).__name__} {getattr(e, "code", "")}'
    res = (body.get('chart') or {}).get('result') or []
    if not res:
        return f'{sym:10} {interval:4} boş ({(body.get("chart") or {}).get("error")})'
    r = res[0]
    t = r.get('timestamp') or []
    q = ((r.get('indicators') or {}).get('quote') or [{}])[0]
    o, h, l, c = (q.get(k) or [] for k in ('open', 'high', 'low', 'close'))
    v = q.get('volume') or []
    tam = [i for i in range(len(t)) if None not in (o[i], h[i], l[i], c[i])]
    gercek = sum(1 for i in tam if h[i] > l[i])
    hacim = sum(1 for i in tam if i < len(v) and v[i])
    son_bar = (f'o={o[tam[-1]]:.4f} h={h[tam[-1]]:.4f} l={l[tam[-1]]:.4f} '
               f'c={c[tam[-1]]:.4f}') if tam else ''
    gmt = r.get('meta', {}).get('gmtoffset')
    return (f'{sym:10} {interval:4} {len(tam):5} bar  '
            f'{ts(t[tam[0]]) if tam else "-"} → {ts(t[tam[-1]]) if tam else "-"}  '
            f'gerçek OHLC %{(100 * gercek / len(tam)) if tam else 0:5.1f}  '
            f'hacim %{(100 * hacim / len(tam)) if tam else 0:5.1f}  gmtoff={gmt}  '
            f'{sure:.2f}s  {son_bar}')


def binance(sym, interval, limit=1000):
    for taban in ('https://data-api.binance.vision', 'https://api.binance.com'):
        url = f'{taban}/api/v3/klines?symbol={sym}&interval={interval}&limit={limit}&timeZone=3'
        try:
            rows, sure = get(url)
        except Exception as e:  # noqa: BLE001
            last = f'{sym:10} {interval:4} HATA {type(e).__name__} {getattr(e, "code", "")} ({taban})'
            continue
        gercek = sum(1 for r in rows if float(r[2]) > float(r[3]))
        r = rows[-1]
        return (f'{sym:10} {interval:4} {len(rows):5} bar  {ts(rows[0][0] / 1000)} → '
                f'{ts(r[0] / 1000)}  gerçek OHLC %{100 * gercek / len(rows):5.1f}  {sure:.2f}s  '
                f'o={r[1]} h={r[2]} l={r[3]} c={r[4]}  ({taban.split("//")[1]})')
    return last


def main():
    print('## Yahoo (BIST hisse, ABD hisse, döviz, altın, emtia, endeks)')
    semboller = ['THYAO.IS', 'ASELS.IS', 'XU100.IS', 'AAPL', 'USDTRY=X', 'EURTRY=X',
                 'XAUTRY=X', 'GC=F', 'SI=F', 'BZ=F']
    araliklar = [('1m', 1.5), ('1m', 7), ('60m', 30), ('60m', 365), ('60m', 729),
                 ('1d', 365), ('1wk', 5 * 365), ('1mo', 10 * 365)]
    for s in semboller:
        for (i, g) in araliklar:
            print(yahoo(s, i, g), f' pencere={g}g')
        print()
    print('## Yahoo 4h (desteklenmiyorsa 60m birleştirilmeli)')
    print(yahoo('THYAO.IS', '4h', 30))
    print(yahoo('USDTRY=X', '4h', 30))
    print()
    print('## Binance (kripto)')
    for s in ['BTCTRY', 'ETHUSDT', 'USDTTRY', 'SHIBTRY']:
        for i in ['1m', '1h', '4h', '1d', '1w', '1M']:
            print(binance(s, i))
        print()


if __name__ == '__main__':
    main()
