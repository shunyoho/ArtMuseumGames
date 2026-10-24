-- =========================================================
-- 高美館闖關活動：資料表 + RLS + 兌換函式
-- 在 Supabase → SQL Editor 整段貼上執行即可（可重複執行前請先確認沒有舊表）
-- =========================================================

-- 1. 關卡（所有登入者都看得到）
create table public.stages (
  id          smallint primary key,
  name        text not null,
  description text,
  icon        text not null,          -- 前端 icon 代號：palette / sculpture / camera / leaf / frame
  sort        smallint not null
);
alter table public.stages enable row level security;
create policy "stages readable" on public.stages
  for select to authenticated using (true);

-- 2. 關主名單
create table public.staff (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.staff enable row level security;
create policy "staff see self" on public.staff
  for select to authenticated using (user_id = auth.uid());

-- 判斷目前登入者是不是關主（前端用 db.rpc('is_staff') 呼叫）
create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.staff where user_id = auth.uid());
$$;

-- 3. 關卡密碼（QR code 的內容）— 只有關主讀得到，玩家讀了只會拿到 []
create table public.stage_codes (
  stage_id smallint primary key references public.stages(id) on delete cascade,
  code     text not null unique default replace(gen_random_uuid()::text, '-', '')
);
alter table public.stage_codes enable row level security;
create policy "staff read codes" on public.stage_codes
  for select to authenticated using (public.is_staff());

-- 4. 過關紀錄 — 玩家只能讀自己的；沒有 insert policy，只能透過 claim_stage() 寫入
create table public.progress (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  stage_id   smallint not null references public.stages(id) on delete cascade,
  cleared_at timestamptz not null default now(),
  primary key (user_id, stage_id)
);
alter table public.progress enable row level security;
create policy "own progress" on public.progress
  for select to authenticated using (user_id = auth.uid());

-- 5. 掃 QR 兌換過關（前端用 db.rpc('claim_stage', { p_code }) 呼叫）
--    security definer = 以資料表擁有者身分執行，所以能查 stage_codes、寫 progress，
--    但只會寫入「auth.uid() 自己」的那一列。
create or replace function public.claim_stage(p_code text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_stage smallint;
  v_name  text;
  v_rows  int;
begin
  if auth.uid() is null then
    raise exception 'not_logged_in';
  end if;

  select sc.stage_id, s.name into v_stage, v_name
  from public.stage_codes sc
  join public.stages s on s.id = sc.stage_id
  where sc.code = p_code;

  if v_stage is null then
    raise exception 'invalid_code';
  end if;

  insert into public.progress (user_id, stage_id)
  values (auth.uid(), v_stage)
  on conflict do nothing;
  get diagnostics v_rows = row_count;

  return json_build_object('stage_id', v_stage, 'stage_name', v_name, 'already', v_rows = 0);
end;
$$;

revoke execute on function public.claim_stage(text) from public, anon;
grant  execute on function public.claim_stage(text) to authenticated;
revoke execute on function public.is_staff() from public, anon;
grant  execute on function public.is_staff() to authenticated;

-- =========================================================
-- 初始資料：5 個關卡（名稱、說明可以自己改）
-- =========================================================
insert into public.stages (id, name, description, icon, sort) values
  (1, '色彩獵人',   '在展廳中找出指定作品，說出它的三種主色。',       'palette',   1),
  (2, '雕塑公園',   '到戶外雕塑區，模仿一件雕塑的姿勢讓關主拍照。',   'sculpture', 2),
  (3, '光影捕手',   '用手機拍下館內一處最喜歡的光影角落。',           'camera',    3),
  (4, '湖畔生態',   '在內惟埤湖畔找到關主指定的三種植物。',           'leaf',      4),
  (5, '小小策展人', '為一件作品取新名字，並說明你的理由。',           'frame',     5);

-- 每關自動產生一組隨機密碼
insert into public.stage_codes (stage_id) select id from public.stages;

-- =========================================================
-- 設定關主：把下面的 email 換成關主註冊時用的 email 再執行
-- =========================================================
-- insert into public.staff (user_id)
-- select id from auth.users where email = 'staff@example.com';

notify pgrst, 'reload schema';
