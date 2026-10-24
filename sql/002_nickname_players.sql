-- =========================================================
-- 暱稱玩家（不用登入）
-- 玩家輸入暱稱 → join_game() 發一組隨機玩家編號，存在手機裡
-- 之後蓋章、查進度都帶這組編號呼叫函式；玩家不能直接讀寫資料表
-- 在 Supabase → SQL Editor 整段貼上執行（需先執行過 001_stage_game.sql）
-- =========================================================

-- 1. 玩家
create table public.players (
  id         uuid primary key default gen_random_uuid(),
  nickname   text not null check (char_length(nickname) between 1 and 20),
  created_at timestamptz not null default now()
);
alter table public.players enable row level security;
-- 不寫任何 policy：前端讀寫一律被擋，只能透過下面的函式

-- 2. 玩家過關紀錄
create table public.player_progress (
  player_id  uuid not null references public.players(id) on delete cascade,
  stage_id   smallint not null references public.stages(id) on delete cascade,
  cleared_at timestamptz not null default now(),
  primary key (player_id, stage_id)
);
alter table public.player_progress enable row level security;
-- 同樣不寫 policy

-- 3. 沒登入的玩家（anon）也要能讀關卡列表
create policy "stages readable by anon" on public.stages
  for select to anon using (true);

-- 4. 加入遊戲：建立玩家，回傳玩家編號
create or replace function public.join_game(p_nickname text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_name text := btrim(p_nickname);
  v_id   uuid;
begin
  if v_name is null or char_length(v_name) = 0 or char_length(v_name) > 20 then
    raise exception 'invalid_nickname';
  end if;
  insert into public.players (nickname) values (v_name) returning id into v_id;
  return v_id;
end;
$$;

-- 5. 查玩家資料：{ nickname, cleared: [關卡 id...] }；編號不存在時回傳 null
create or replace function public.get_player(p_player uuid)
returns json
language sql stable security definer set search_path = public
as $$
  select json_build_object(
    'nickname', p.nickname,
    'cleared', coalesce(
      (select json_agg(pp.stage_id order by pp.stage_id)
         from public.player_progress pp where pp.player_id = p.id),
      '[]'::json)
  )
  from public.players p
  where p.id = p_player;
$$;

-- 6. 掃 QR 蓋章
create or replace function public.claim_stage_as_player(p_player uuid, p_code text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_stage smallint;
  v_name  text;
  v_rows  int;
begin
  if not exists (select 1 from public.players where id = p_player) then
    raise exception 'invalid_player';
  end if;

  select sc.stage_id, s.name into v_stage, v_name
  from public.stage_codes sc
  join public.stages s on s.id = sc.stage_id
  where sc.code = p_code;

  if v_stage is null then
    raise exception 'invalid_code';
  end if;

  insert into public.player_progress (player_id, stage_id)
  values (p_player, v_stage)
  on conflict do nothing;
  get diagnostics v_rows = row_count;

  return json_build_object('stage_id', v_stage, 'stage_name', v_name, 'already', v_rows = 0);
end;
$$;

revoke execute on function public.join_game(text) from public;
revoke execute on function public.get_player(uuid) from public;
revoke execute on function public.claim_stage_as_player(uuid, text) from public;
grant  execute on function public.join_game(text) to anon, authenticated;
grant  execute on function public.get_player(uuid) to anon, authenticated;
grant  execute on function public.claim_stage_as_player(uuid, text) to anon, authenticated;

notify pgrst, 'reload schema';
