-- Snapcircle: run once in a new Supabase project's SQL editor.
create extension if not exists pgcrypto with schema extensions;
create table public.circles (id uuid primary key default gen_random_uuid(), code text not null unique default upper(encode(extensions.gen_random_bytes(8),'hex')), created_at timestamptz not null default now());
create table public.profiles (id uuid primary key references auth.users on delete cascade, circle_id uuid not null references public.circles, name text not null default 'New friend' check(length(name) between 1 and 40), title text not null default 'Our little universe' check(length(title)<=70), bio text not null default 'Little moments. Big memories.' check(length(bio)<=160), accent text not null default '#8c7af0' check(accent ~ '^#[0-9a-fA-F]{6}$'), frame text not null default 'classic');
create table public.albums (id uuid primary key default gen_random_uuid(), circle_id uuid not null references public.circles, owner_id uuid not null references public.profiles, name text not null check(length(name) between 1 and 60), created_at timestamptz not null default now());
create table public.media (id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles on delete cascade, circle_id uuid not null references public.circles, album_id uuid references public.albums on delete set null, path text not null unique, caption text not null default '' check(length(caption)<=160), kind text not null check(kind in ('photo','snap')), points integer generated always as (case when kind='snap' then 15 else 10 end) stored, created_at timestamptz not null default now(), expires_at timestamptz);
create index on public.media(circle_id,created_at desc);
create table public.favorites (user_id uuid references public.profiles on delete cascade, media_id uuid references public.media on delete cascade, primary key(user_id,media_id));
create table public.rewards (id text primary key, label text not null, cost integer not null check(cost>=0), type text not null, value text not null);
insert into public.rewards values ('sage','Sage studio',40,'theme','#7eaa91'),('sunset','Peach club',60,'theme','#ef9775'),('ocean','Blue hour',80,'theme','#69a9d2'),('rose','Rose garden',100,'theme','#d883a1'),('midnight','After hours',120,'theme','#6875af'),('sticker','Sticker frame',50,'frame','sticker'),('rounded','Soft corners',75,'frame','rounded'),('ink','Ink outline',100,'frame','ink');
create table public.inventory (user_id uuid references public.profiles on delete cascade, reward_id text references public.rewards, spent integer not null, created_at timestamptz not null default now(), primary key(user_id,reward_id));
create schema if not exists private;
create function private.my_circle() returns uuid language sql stable security definer set search_path='' as $$ select circle_id from public.profiles where id=auth.uid() $$;
create function private.has_circle(c uuid) returns boolean language sql stable security definer set search_path='' as $$ select c=private.my_circle() $$;
create function private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
declare c uuid;
begin insert into public.circles default values returning id into c; insert into public.profiles(id,circle_id,name) values(new.id,c,left(coalesce(nullif(new.raw_user_meta_data->>'name',''),'New friend'),40));return new;end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.new_user();
alter table public.circles enable row level security;
alter table public.profiles enable row level security;
alter table public.albums enable row level security;
alter table public.media enable row level security;
alter table public.favorites enable row level security;
alter table public.rewards enable row level security;
alter table public.inventory enable row level security;
create policy "my circle" on public.circles for select to authenticated using(private.has_circle(id));
create policy "circle profiles" on public.profiles for select to authenticated using(private.has_circle(circle_id));
create policy "circle albums" on public.albums for select to authenticated using(private.has_circle(circle_id));
create policy "live circle media" on public.media for select to authenticated using(private.has_circle(circle_id) and (expires_at is null or expires_at>now()));
create policy "my favorites" on public.favorites for select to authenticated using(user_id=auth.uid());
create policy "favorite live media" on public.favorites for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.media where id=media_id));
create policy "unfavorite" on public.favorites for delete to authenticated using(user_id=auth.uid());
create policy "reward catalog" on public.rewards for select to authenticated using(true);
create policy "my inventory" on public.inventory for select to authenticated using(user_id=auth.uid());
create function public.join_circle(invite text) returns void language plpgsql security definer set search_path='' as $$
declare c uuid;
begin if auth.uid() is null then raise exception 'Sign in first';end if;
select id into c from public.circles where code=upper(trim(invite));if c is null then raise exception 'Circle code not found';end if;
update public.profiles set circle_id=c where id=auth.uid();end $$;
create function public.save_profile(display_name text, space_title text, description text, color text) returns void language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Sign in first';end if;update public.profiles set name=display_name,title=space_title,bio=description,accent=color where id=auth.uid();end $$;
create function public.create_album(album_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid;
begin if auth.uid() is null then raise exception 'Sign in first';end if;insert into public.albums(circle_id,owner_id,name) values(private.my_circle(),auth.uid(),album_name) returning id into a;return a;end $$;
create function public.create_media(object_path text, photo_caption text, media_kind text, target_album uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare m uuid;
begin
if auth.uid() is null then raise exception 'Sign in first';end if;
perform 1 from public.profiles where id=auth.uid() for update;
if (select count(*) from public.media where owner_id=auth.uid() and created_at>now()-interval '24 hours')>=20 then raise exception 'Daily limit reached: 20 uploads per day';end if;
if split_part(object_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='moments' and name=object_path) then raise exception 'Upload your image first';end if;
if target_album is not null and not exists(select 1 from public.albums where id=target_album and private.has_circle(circle_id)) then raise exception 'Album not found';end if;
insert into public.media(owner_id,circle_id,path,caption,kind,expires_at,album_id) values(auth.uid(),private.my_circle(),object_path,photo_caption,media_kind,case when media_kind='snap' then now()+interval '24 hours' else null end,target_album) returning id into m;return m;end $$;
create function public.delete_media(media_id uuid) returns text language plpgsql security definer set search_path='' as $$
declare p text;begin delete from public.media where id=media_id and owner_id=auth.uid() returning path into p;if p is null then raise exception 'Photo not found';end if;return p;end $$;
-- A separate score function includes expired snaps for lifetime earned points.
create function public.circle_scores() returns table(id uuid,name text,earned bigint,spent bigint) language sql stable security definer set search_path='' as $$
select p.id,p.name,coalesce((select sum(m.points) from public.media m where m.owner_id=p.id),0),coalesce((select sum(i.spent) from public.inventory i where i.user_id=p.id),0) from public.profiles p where private.has_circle(p.circle_id) $$;
create function public.redeem_reward(reward text) returns void language plpgsql security definer set search_path='' as $$
declare price integer; balance bigint;
begin if auth.uid() is null then raise exception 'Sign in first';end if;perform 1 from public.profiles where id=auth.uid() for update;
select cost into price from public.rewards where id=reward;if price is null then raise exception 'Reward not found';end if;
select coalesce((select sum(points) from public.media where owner_id=auth.uid()),0)-coalesce((select sum(spent) from public.inventory where user_id=auth.uid()),0) into balance;
if balance<price then raise exception 'Collect more points to unlock this';end if;insert into public.inventory(user_id,reward_id,spent) values(auth.uid(),reward,price);end $$;
create function public.equip_reward(reward text) returns void language plpgsql security definer set search_path='' as $$
declare r public.rewards;
begin if reward='classic' then update public.profiles set frame='classic' where id=auth.uid();return;end if;
if not exists(select 1 from public.inventory where user_id=auth.uid() and reward_id=reward) then raise exception 'Unlock this first';end if;select * into r from public.rewards where id=reward;
if r.type='theme' then update public.profiles set accent=r.value where id=auth.uid();else update public.profiles set frame=r.value where id=auth.uid();end if;end $$;
-- Expose only authenticated application operations.
revoke execute on function public.join_circle(text),public.save_profile(text,text,text,text),public.create_album(text),public.create_media(text,text,text,uuid),public.delete_media(uuid),public.circle_scores(),public.redeem_reward(text),public.equip_reward(text) from public, anon;
grant execute on function public.join_circle(text),public.save_profile(text,text,text,text),public.create_album(text),public.create_media(text,text,text,uuid),public.delete_media(uuid),public.circle_scores(),public.redeem_reward(text),public.equip_reward(text) to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.my_circle(),private.has_circle(uuid) to authenticated;
grant select on public.circles,public.profiles,public.albums,public.media,public.rewards,public.inventory to authenticated;
grant select,insert,delete on public.favorites to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('moments','moments',false,5242880,array['image/jpeg']);
create policy "upload own JPEG" on storage.objects for insert to authenticated with check(bucket_id='moments' and (storage.foldername(name))[1]=auth.uid()::text and lower(storage.extension(name))='jpg');
create policy "read circle live images" on storage.objects for select to authenticated using(bucket_id='moments' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.media m where m.path=name and private.has_circle(m.circle_id) and (m.expires_at is null or m.expires_at>now()))));
create policy "delete own uploads" on storage.objects for delete to authenticated using(bucket_id='moments' and (storage.foldername(name))[1]=auth.uid()::text);

