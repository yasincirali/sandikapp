// Widget Fiyat Edge Function — tek varlık widget'ının arka plan tazelemesi
//
// yasin onayı 2026-10-26: "Tek varlık widget'ı uygulama açılmadan da
// tazelensin". iOS WidgetKit zaman çizelgesi ve Android widget alarmı yarım
// saatte bir, YALNIZ seçili varlık sunucu kapsamındaysa (altın, TL döviz,
// kripto) çağırır. Gerekçe ve kapsam: `_shared/widget_fiyat.ts`.
//
// ── Güvenlik (karar: oturum jetonu widget'a taşınmaz) ───────────────────────
// · Çağıran anon anahtarıyla gelir; gateway JWT doğrulaması Supabase
//   varsayılanı (`verify_jwt = true`, config.toml'da blok yok — anon
//   anahtarı geçerli JWT'dir). Kullanıcı kimliği SORULMAZ, kişisel veri
//   okunmaz/dönmez: yanıt herkes için aynı kamu piyasa fiyatıdır.
// · Okuma service role ile yalnız iki piyasa tablosundan; tabloların
//   anon/authenticated GRANT ve RLS'ine DOKUNULMAZ (0101/0074 anon'a kapalı
//   kalır). Yazma yok, SQL yok (PostgREST sorgu kurucusu, sabit tablo/sütun).
// · Sembol beyaz listesi; en çok 5 sembol; gövde ≤ 1 KB. Başka sağlayıcıya
//   istek atılmaz — fonksiyon açık proxy değildir, en kötü kötüye kullanım
//   iki küçük tablodan zaten kamuya açık fiyat okumaktır.
// · Yanıtta hata ayrıntısı, ham metin, anahtar DÖNMEZ; ayrıntı yalnız
//   sunucu günlüğünde (`console.error`, kod/ad düzeyinde).
//
// Yanıt: `{ "<SEMBOL>": { fiyat, zaman, degisim? }, … }` — bilinmeyen ya da
// bayat sembol yanıtta yoktur. `Cache-Control: public, max-age=60`.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { kriptoKodu } from '../_shared/kripto.ts';
import {
  kriptoWidgetFiyati,
  WIDGET_AZAMI_GOVDE,
  WIDGET_ONBELLEK_SN,
  type WidgetFiyat,
  widgetIstegiCoz,
  widgetSembolTuru,
  yurtIciWidgetFiyati,
} from '../_shared/widget_fiyat.ts';

const baslik = {
  'Content-Type': 'application/json',
  'Cache-Control': `public, max-age=${WIDGET_ONBELLEK_SN}`,
};

function json(body: unknown, status = 200, onbellege = status === 200) {
  return new Response(JSON.stringify(body), {
    status,
    // Hata ya da eksik yanıt önbelleğe alınmaz: sonraki deneme sunucuya ulaşsın.
    headers: onbellege ? baslik : { 'Content-Type': 'application/json' },
  });
}

/// Isolate içi kısa önbellek: aynı sembol kümesi 60 sn içinde yeniden
/// sorulursa tabloya gidilmez. Boyut sınırlı (beyaz liste küçük ama kripto
/// kodları çok); taşarsa en eskisi düşer.
const onbellek = new Map<string, { at: number; yanit: Record<string, WidgetFiyat> }>();
const ONBELLEK_AZAMI = 200;

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'method' }, 405);

  try {
    // Gövde sınırı: önce başlık, sonra gerçek uzunluk (başlık yalan olabilir).
    const uzunluk = Number(request.headers.get('content-length') ?? '0');
    if (Number.isFinite(uzunluk) && uzunluk > WIDGET_AZAMI_GOVDE) {
      return json({ error: 'istek' }, 413);
    }
    const metin = await request.text();
    if (metin.length > WIDGET_AZAMI_GOVDE) return json({ error: 'istek' }, 413);
    let govde: unknown = null;
    try {
      govde = JSON.parse(metin);
    } catch (_) { /* aşağıda reddedilir */ }
    const semboller = widgetIstegiCoz(govde);
    if (semboller === null) return json({ error: 'istek' }, 400);
    if (semboller.length === 0) return json({});

    const simdi = Date.now();
    const anahtar = [...semboller].sort().join(',');
    const onceki = onbellek.get(anahtar);
    if (onceki && simdi - onceki.at < WIDGET_ONBELLEK_SN * 1000) {
      return json(onceki.yanit);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Supabase ortam değişkenleri runtime tarafından sağlanmadı.');
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const yurtIci = semboller.filter((s) => widgetSembolTuru(s) === 'yurt_ici');
    const kripto = semboller.filter((s) => widgetSembolTuru(s) === 'kripto');
    const yanit: Record<string, WidgetFiyat> = {};
    // Okuma hatası olan tur önbelleğe girmez: eksik yanıt 60 sn dağıtılmasın.
    let eksik = false;

    await Promise.all([
      // Sembol başına son kova: PK (sembol, ts) üzerinde tek satır.
      ...yurtIci.map(async (s) => {
        const { data, error } = await admin
          .from('yurt_ici_kotasyon')
          .select('ts, fiyat, degisim_pct')
          .eq('sembol', s)
          .order('ts', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (error) {
          console.error('widget-fiyat yurt_ici okunamadi', error.code);
          eksik = true;
          return;
        }
        const f = data ? yurtIciWidgetFiyati(data, simdi) : null;
        if (f) yanit[s] = f;
      }),
      (async () => {
        if (kripto.length === 0) return;
        const kodlar = new Map<string, string>();
        for (const s of kripto) {
          const kod = kriptoKodu(s);
          if (kod) kodlar.set(kod, s);
        }
        const { data, error } = await admin
          .from('kripto_fiyat')
          .select('kod, fiyat_try, gun_acilis_try, guncellendi')
          .in('kod', [...kodlar.keys()]);
        if (error) {
          console.error('widget-fiyat kripto okunamadi', error.code);
          eksik = true;
          return;
        }
        for (const satir of data ?? []) {
          const s = kodlar.get(String(satir.kod));
          const f = s ? kriptoWidgetFiyati(satir, simdi) : null;
          if (s && f) yanit[s] = f;
        }
      })(),
    ]);

    if (eksik) return json(yanit, 200, false);
    if (onbellek.size >= ONBELLEK_AZAMI) {
      const ilk = onbellek.keys().next().value;
      if (ilk !== undefined) onbellek.delete(ilk);
    }
    onbellek.set(anahtar, { at: simdi, yanit });
    return json(yanit);
  } catch (e) {
    console.error('widget-fiyat hatasi', e instanceof Error ? e.name : '');
    return json({ error: 'sunucu' }, 500);
  }
});
