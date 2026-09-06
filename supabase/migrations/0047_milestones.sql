-- 0047_milestones.sql
-- ============================================================
-- Kilometre taşları — birikimin kutlanması.
--
-- ⚠️ KUTLANAN ŞEY BİRİKİMDİR, İŞLEM DEĞİL.
--
-- Robinhood her İŞLEM sonrası konfeti atıyordu; Massachusetts Securities
-- Division bunu "dijital etkileşim pratikleri" başlığı altında menkul
-- kıymet mevzuatı kapsamında ele aldı ve dosya 7,5 milyon dolarlık
-- uzlaşmayla kapandı (Ocak 2024). Ayrım teknik değil ilkesel: işlem
-- ödüllendirildiğinde kullanıcı daha çok işlem yapar ve Barber & Odean
-- verisine göre daha az kazanır. Burada ödüllendirilen şey portföyün
-- BÜYÜMESİ, sabır ve çeşitlenme.
--
-- Bkz. RETENTION_STRATEJISI.md §9.
-- ============================================================

create table if not exists public.milestones (
  user_id    uuid not null references auth.users(id) on delete cascade,
  -- 'portfolio_value' | 'gold_count' | 'portfolio_age' | 'diversification'
  kind       text not null,
  -- Eşiğin kimliği: '100000', 'ALTIN_CEYREK:10', '1y', '5types'.
  -- Metin çünkü eşikler tek tip değil.
  value      text not null,
  reached_at timestamptz not null default now(),
  -- Kullanıcıya GÖSTERİLDİ mi? Eşik geçilir geçilmez yazılır ama kutlama
  -- ayrı bir andır: uygulama kapalıyken geçilen eşik, kullanıcı açtığında
  -- kutlanmalı.
  shown_at   timestamptz,
  primary key (user_id, kind, value)
);

create index if not exists ix_milestones_unshown
  on public.milestones (user_id, reached_at desc)
  where shown_at is null;

alter table public.milestones enable row level security;

drop policy if exists milestones_own_select on public.milestones;
create policy milestones_own_select on public.milestones
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists milestones_own_insert on public.milestones;
create policy milestones_own_insert on public.milestones
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists milestones_own_update on public.milestones;
create policy milestones_own_update on public.milestones
  for update to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke delete on public.milestones from anon, authenticated;
