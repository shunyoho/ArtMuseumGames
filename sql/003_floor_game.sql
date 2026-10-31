-- =========================================================
-- 《高美館失落的藝術能量》：分組、樓層路線、作答與照片上傳
-- 玩家選組別、填名字 → 依組別路線走完三個樓層 → 每層作答後掃關主 QR code 才能往下一層
-- 在 Supabase → SQL Editor 整段貼上執行（需先執行過 001、002）
-- 注意：會刪掉舊的第 1、5 關；舊玩家沒有組別，手機會被導回首頁重新加入
-- =========================================================

-- 1. 組別：route 是該組走訪樓層的順序（stages.id），要調整路線改這裡就好
create table public.teams (
  id    smallint primary key,
  name  text not null,
  route smallint[] not null
);
alter table public.teams enable row level security;
create policy "teams readable" on public.teams
  for select to anon, authenticated using (true);
grant select on public.teams to anon, authenticated;

insert into public.teams (id, name, route) values
  (1, '第一組', '{2,3,4}'),
  (2, '第二組', '{2,3,4}'),
  (3, '第三組', '{3,4,2}'),
  (4, '第四組', '{3,4,2}'),
  (5, '第五組', '{4,2,3}'),
  (6, '第六組', '{4,2,3}');

-- 2. 玩家加上組別（舊玩家留空，get_player 會當作不存在）
alter table public.players add column team_id smallint references public.teams(id);

-- 3. 關卡改成三個樓層：stages.id 就是樓層數字
alter table public.stages add column title text;

delete from public.stages where id not in (2, 3, 4);

insert into public.stages (id, name, title, description, icon, sort) values
  (2, '二樓', '🔮 你的問題，會得到什麼回應？',
   '在高美館的某個角落，有一個能讓你向傳統智慧提問的神秘裝置。準備好心中的問題，透過藝術家的互動設計，尋找屬於你的籤詩吧！',
   'palette', 2),
  (3, '三樓', '💗 尋找你的心情分身！',
   '展場裡藏著一件與你此刻心情產生共鳴的作品。它可能看起來很快樂，也可能有點孤單、疲憊，甚至讓你覺得說不出來的熟悉。',
   'frame', 3),
  (4, '四樓', '🗿 讓你的身體成為藝術！',
   '畫作裡的人物彷彿被施了魔法，永遠停留在某個動作中。現在，輪到你挑戰了！仔細觀察圖畫的姿勢，看看你能不能成為下一位人體藝術家。',
   'sculpture', 4)
on conflict (id) do update set
  name = excluded.name, title = excluded.title, description = excluded.description,
  icon = excluded.icon, sort = excluded.sort;

insert into public.stage_codes (stage_id) select id from public.stages
on conflict (stage_id) do nothing;

-- 4. 題目：kind 是 text（簡答）或 photo（上傳照片）
create table public.questions (
  id       smallint primary key,
  stage_id smallint not null references public.stages(id) on delete cascade,
  sort     smallint not null,
  kind     text not null check (kind in ('text', 'photo')),
  title    text not null,
  hint     text,
  required boolean not null default true
);
alter table public.questions enable row level security;
create policy "questions readable" on public.questions
  for select to anon, authenticated using (true);
grant select on public.questions to anon, authenticated;

insert into public.questions (id, stage_id, sort, kind, title, hint, required) values
  (21, 2, 1, 'text',  '二樓的毛筆展間共有幾隻毛筆？', '君子六藝：禮樂射御書數。', true),
  (22, 2, 2, 'text',  '藝術求籤：寫下問題', '提示：籤詩是一種文化體驗，你可以自由思考它的意義！', true),
  (23, 2, 3, 'photo', '藝術求籤：上傳抽到的籤詩', null, true),
  (31, 3, 1, 'photo', '像我的照片（一）', E'找一張「最像你現在心情」的展覽品。拍下來上傳\n提示：沒有標準答案，只有屬於你的感受！', true),
  (32, 3, 2, 'text',  '像我的照片（二）', E'找一張「最像你現在心情」的展覽品。\n說出心情和原因。\n如：他在畫星空，像我現在眼睛亮晶晶。', false),
  (41, 4, 1, 'text',  '找出四樓展覽的四個系列名稱', '眾生皆有情，萬物皆有靈性。', true),
  (42, 4, 2, 'photo', '找到一幅畫，模仿畫中人物的姿勢並上傳。', '提示：請注意周遭空間，保持安全，不影響其他觀眾！', true);

-- 5. 玩家答案：不寫 policy，只能透過 save_answer() / get_player()
create table public.player_answers (
  player_id   uuid not null references public.players(id) on delete cascade,
  question_id smallint not null references public.questions(id) on delete cascade,
  text_answer text,
  file_path   text,
  updated_at  timestamptz not null default now(),
  primary key (player_id, question_id)
);
alter table public.player_answers enable row level security;

-- 6. 照片：私有 bucket，玩家只能新增、不能讀取別人的照片
--    檔案放在「玩家編號/」資料夾底下，編號必須存在才能上傳
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('answers', 'answers', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

create or replace function public.player_exists(p_player text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.players where id::text = p_player);
$$;

create policy "players upload answers" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'answers' and public.player_exists((storage.foldername(name))[1]));

-- 7. 加入遊戲：多帶組別
drop function if exists public.join_game(text);

create or replace function public.join_game(p_nickname text, p_team smallint)
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
  if not exists (select 1 from public.teams where id = p_team) then
    raise exception 'invalid_team';
  end if;
  insert into public.players (nickname, team_id) values (v_name, p_team) returning id into v_id;
  return v_id;
end;
$$;

-- 8. 查玩家資料：多回傳組別、路線、答案；編號不存在或沒有組別時回傳 null
create or replace function public.get_player(p_player uuid)
returns json
language sql stable security definer set search_path = public
as $$
  select json_build_object(
    'nickname', p.nickname,
    'team_name', t.name,
    'route', t.route,
    'cleared', coalesce(
      (select json_agg(pp.stage_id order by pp.stage_id)
         from public.player_progress pp where pp.player_id = p.id),
      '[]'::json),
    'answers', coalesce(
      (select json_object_agg(a.question_id, json_build_object('text', a.text_answer, 'file_path', a.file_path))
         from public.player_answers a where a.player_id = p.id),
      '{}'::json)
  )
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.id = p_player;
$$;

-- 9. 存答案：簡答存文字，照片存 Storage 路徑（必須在自己的資料夾底下）
create or replace function public.save_answer(p_player uuid, p_question smallint, p_text text, p_file_path text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_kind text;
  v_text text;
begin
  if not exists (select 1 from public.players where id = p_player and team_id is not null) then
    raise exception 'invalid_player';
  end if;

  select kind into v_kind from public.questions where id = p_question;
  if v_kind is null then
    raise exception 'invalid_question';
  end if;

  if v_kind = 'text' then
    v_text := nullif(btrim(p_text), '');
    if char_length(v_text) > 1000 then
      raise exception 'answer_too_long';
    end if;
    p_file_path := null;
  else
    v_text := null;
    if p_file_path is null or position(p_player::text || '/' in p_file_path) <> 1 then
      raise exception 'invalid_file_path';
    end if;
  end if;

  insert into public.player_answers (player_id, question_id, text_answer, file_path)
  values (p_player, p_question, v_text, p_file_path)
  on conflict (player_id, question_id) do update
    set text_answer = excluded.text_answer, file_path = excluded.file_path, updated_at = now();
end;
$$;

-- 10. 掃 QR 過關：只能掃路線上的下一個樓層，而且必填題都要答完
create or replace function public.claim_stage_as_player(p_player uuid, p_code text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_route smallint[];
  v_stage smallint;
  v_name  text;
  v_next  smallint;
begin
  select t.route into v_route
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.id = p_player;

  if v_route is null then
    raise exception 'invalid_player';
  end if;

  select sc.stage_id, s.name into v_stage, v_name
  from public.stage_codes sc
  join public.stages s on s.id = sc.stage_id
  where sc.code = p_code;

  if v_stage is null then
    raise exception 'invalid_code';
  end if;

  if exists (select 1 from public.player_progress where player_id = p_player and stage_id = v_stage) then
    return json_build_object('stage_id', v_stage, 'stage_name', v_name, 'already', true);
  end if;

  select r.stage_id into v_next
  from unnest(v_route) with ordinality as r(stage_id, ord)
  where not exists (
    select 1 from public.player_progress pp
    where pp.player_id = p_player and pp.stage_id = r.stage_id)
  order by r.ord
  limit 1;

  if v_next is distinct from v_stage then
    raise exception 'wrong_floor';
  end if;

  if exists (
    select 1 from public.questions q
    left join public.player_answers a on a.question_id = q.id and a.player_id = p_player
    where q.stage_id = v_stage and q.required
      and a.text_answer is null and a.file_path is null
  ) then
    raise exception 'incomplete';
  end if;

  insert into public.player_progress (player_id, stage_id)
  values (p_player, v_stage)
  on conflict do nothing;

  return json_build_object('stage_id', v_stage, 'stage_name', v_name, 'already', false);
end;
$$;

revoke execute on function public.join_game(text, smallint) from public;
revoke execute on function public.save_answer(uuid, smallint, text, text) from public;
revoke execute on function public.player_exists(text) from public;
grant  execute on function public.join_game(text, smallint) to anon, authenticated;
grant  execute on function public.save_answer(uuid, smallint, text, text) to anon, authenticated;
grant  execute on function public.player_exists(text) to anon, authenticated;

notify pgrst, 'reload schema';
