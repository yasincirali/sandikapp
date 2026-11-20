-- 0187 — Fon dağılımı var mı (yalnız evet/hayır), kilit kartı için (2026-11-20)
--
-- ## Neden
-- Ar-Ge 20 Kas UI/UX turu 2, madde 2: fon dağılımı kilit kartı (Fon X-Ray)
-- dağılımı OLMAYAN fonda da Premium satıyordu. Ödeyen kullanıcı o fonda
-- hiçbir şey görmüyordu (kart `dag == null` → çizilmez): ödedikten sonra
-- boş çıkan vaat. `fon_dagilimlari` (0131) RLS'i ücretsize satır vermez,
-- istemci "bu fonun verisi var mı"yı bilemiyordu.
--
-- ## Ne verir, ne vermez
-- Yalnız bir boolean: o fon kodunun satırı var mı. Yüzde, tarih, fon tipi
-- DÖNMEZ; Premium içerik (dağılımın kendisi) yine RLS arkasında. Varlık
-- bilgisi kamuya açık TEFAS verisinin "yayımlanıyor mu" kısmıdır, kişisel
-- veri değildir (yasal metne dokunmaz, CLAUDE.md 2026-10-08).
--
-- ## Eski istemciler
-- Yalnız EKLER: yeni bir fonksiyon. Eski build çağırmaz. Yeni build bu
-- migration canlıya gitmeden çıkarsa RPC hatası → istemci eski davranışa
-- (kartı göster) düşer (`fonDagilimiVarMiProvider`).

create or replace function public.fon_dagilimi_var_mi(p_fon_kodu text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.fon_dagilimlari where fon_kodu = upper(p_fon_kodu)
  );
$$;

comment on function public.fon_dagilimi_var_mi(text) is
  '0187: fon_dagilimlari satiri var mi (yalniz boolean). Kilit kartini '
  'verisi olmayan fonda gostermemek icin; icerik RLS arkasinda kalir.';

revoke all on function public.fon_dagilimi_var_mi(text) from public, anon;
grant execute on function public.fon_dagilimi_var_mi(text) to authenticated;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'public.fon_dagilimi_var_mi(text)'::regprocedure
       and p.prosecdef
       and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) then
    raise exception '0187: fon_dagilimi_var_mi SECURITY DEFINER + search_path olmali';
  end if;
  if not has_function_privilege('authenticated', 'public.fon_dagilimi_var_mi(text)', 'EXECUTE') then
    raise exception '0187: fon_dagilimi_var_mi authenticated icin EXECUTE eksik';
  end if;
  if has_function_privilege('anon', 'public.fon_dagilimi_var_mi(text)', 'EXECUTE') then
    raise exception '0187: fon_dagilimi_var_mi anon icin acik olmamali';
  end if;
  raise notice '0187 tamam: fon_dagilimi_var_mi (authenticated, boolean).';
end $$;
