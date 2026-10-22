-- Poker Room Phase 1 / Supabase SQL Editor / run once on a new project.
create extension if not exists pgcrypto;
create table public.rooms (
 id uuid primary key default gen_random_uuid(),
 name text not null check (char_length(name) between 1 and 60),
 invite_code text not null unique check (invite_code ~ '^[a-f0-9]{24}$'),
 owner_id uuid not null references auth.users(id),
 deputy_id uuid references auth.users(id),
 max_players int not null check(max_players between 2 and 12),
 small_blind bigint not null check(small_blind > 0),
 big_blind bigint not null check(big_blind > small_blind),
 starting_stack bigint not null check(starting_stack >= big_blind),
 created_at timestamptz not null default now()
);
create table public.room_members (
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms(id) on delete cascade,
 user_id uuid not null references auth.users(id),
 nickname text not null check(char_length(nickname) between 1 and 24),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 seat_number int check(seat_number between 1 and 12),
 created_at timestamptz not null default now(),
 unique(room_id,user_id),
 unique(room_id,seat_number)
);
create index on public.room_members(room_id,status);
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
-- RPC-only reads/writes: no table grants for anon/authenticated. Snapshot polling ensures sync.
revoke all on public.rooms, public.room_members from anon, authenticated;

create or replace function public.create_poker_room(p_name text,p_invite text,p_nickname text,p_max int,p_sb bigint,p_bb bigint,p_stack bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room uuid; v_user uuid := auth.uid();
begin
 if v_user is null then raise exception '請先建立匿名登入身分'; end if;
 if length(trim(coalesce(p_name,''))) not between 1 and 60 or length(trim(coalesce(p_nickname,''))) not between 1 and 24 then raise exception '房間名稱或暱稱不正確'; end if;
 if p_invite !~ '^[a-f0-9]{24}$' then raise exception '邀請碼格式錯誤'; end if;
 if p_max not between 2 and 12 or p_sb <= 0 or p_bb <= p_sb or p_stack < p_bb or p_stack > 1000000000 then raise exception '盲注或籌碼設定不正確'; end if;
 insert into public.rooms(name,invite_code,owner_id,max_players,small_blind,big_blind,starting_stack)
 values(trim(p_name),p_invite,v_user,p_max,p_sb,p_bb,p_stack) returning id into v_room;
 insert into public.room_members(room_id,user_id,nickname,status,seat_number) values(v_room,v_user,trim(p_nickname),'approved',1);
 return jsonb_build_object('room_id',v_room,'invite_code',p_invite);
end $$;

create or replace function public.request_poker_join(p_invite text,p_nickname text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_member public.room_members%rowtype; v_user uuid := auth.uid();
begin
 if v_user is null then raise exception '尚未登入'; end if;
 if length(trim(coalesce(p_nickname,''))) not between 1 and 24 then raise exception '暱稱需為 1–24 字'; end if;
 select * into v_room from public.rooms where invite_code=p_invite;
 if not found then raise exception '找不到房間，請確認邀請網址'; end if;
 insert into public.room_members(room_id,user_id,nickname,status)
 values(v_room.id,v_user,trim(p_nickname),'pending')
 on conflict(room_id,user_id) do update set nickname=case when room_members.status='approved' then room_members.nickname else excluded.nickname end,
 status=case when room_members.status='approved' then 'approved' else 'pending' end
 returning * into v_member;
 return jsonb_build_object('room_id',v_room.id,'status',v_member.status);
end $$;

create or replace function public.get_poker_room(p_invite text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_user uuid:=auth.uid(); v_m public.room_members%rowtype; v_members jsonb;
begin
 select * into v_room from public.rooms where invite_code=p_invite;
 if not found then raise exception '找不到房間'; end if;
 select * into v_m from public.room_members where room_id=v_room.id and user_id=v_user;
 if not found then raise exception '尚未申請加入房間'; end if;
 if v_m.status='approved' or v_room.owner_id=v_user then
   select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'nickname',m.nickname,'status',m.status,'seat',m.seat_number,'is_owner',m.user_id=v_room.owner_id,'is_deputy',m.user_id=v_room.deputy_id) order by m.created_at), '[]'::jsonb) into v_members
   from public.room_members m where m.room_id=v_room.id and m.status in ('approved','pending');
 else
   v_members:='[]'::jsonb;
 end if;
 return jsonb_build_object('room',jsonb_build_object('name',v_room.name,'max_players',v_room.max_players,'small_blind',v_room.small_blind,'big_blind',v_room.big_blind,'starting_stack',v_room.starting_stack),
 'me',jsonb_build_object('status',v_m.status,'is_owner',v_room.owner_id=v_user,'is_deputy',v_room.deputy_id=v_user), 'members',v_members);
end $$;

create or replace function public.review_poker_member(p_invite text,p_member_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_seat int;
begin
 select * into v_room from public.rooms where invite_code=p_invite for update;
 if not found or v_room.owner_id is distinct from auth.uid() then raise exception '只有房主可以審核'; end if;
 if not exists(select 1 from public.room_members where id=p_member_id and room_id=v_room.id and status='pending') then raise exception '申請不存在或已處理'; end if;
 if p_approve then
  select s into v_seat from generate_series(1,v_room.max_players) s
  where not exists(select 1 from public.room_members m where m.room_id=v_room.id and m.seat_number=s and m.status='approved') order by s limit 1;
  if v_seat is null then raise exception '座位已滿'; end if;
  update public.room_members set status='approved',seat_number=v_seat where id=p_member_id and room_id=v_room.id;
 else
  update public.room_members set status='rejected',seat_number=null where id=p_member_id and room_id=v_room.id;
 end if;
end $$;

create or replace function public.set_poker_deputy(p_invite text,p_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_user uuid;
begin
 select * into v_room from public.rooms where invite_code=p_invite for update;
 if not found or v_room.owner_id is distinct from auth.uid() then raise exception '只有房主可以指定代理'; end if;
 select user_id into v_user from public.room_members where id=p_member_id and room_id=v_room.id and status='approved';
 if v_user is null or v_user=v_room.owner_id then raise exception '請選擇已核准的其他玩家'; end if;
 update public.rooms set deputy_id=v_user where id=v_room.id;
end $$;

revoke all on function public.create_poker_room(text,text,text,int,bigint,bigint,bigint),public.request_poker_join(text,text),public.get_poker_room(text),public.review_poker_member(text,uuid,boolean),public.set_poker_deputy(text,uuid) from public,anon;
grant execute on function public.create_poker_room(text,text,text,int,bigint,bigint,bigint),public.request_poker_join(text,text),public.get_poker_room(text),public.review_poker_member(text,uuid,boolean),public.set_poker_deputy(text,uuid) to authenticated;
