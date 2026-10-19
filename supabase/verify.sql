begin;
select set_config('snap.qa1',gen_random_uuid()::text,true),set_config('snap.qa2',gen_random_uuid()::text,true),set_config('snap.qa3',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
(current_setting('snap.qa1')::uuid,'qa1@sample.invalid','{"name":"QA One"}'),
(current_setting('snap.qa2')::uuid,'qa2@sample.invalid','{"name":"QA Two"}'),
(current_setting('snap.qa3')::uuid,'qa3@sample.invalid','{"name":"QA Three"}');
select set_config('snap.code',(select c.code from public.circles c join public.profiles p on p.circle_id=c.id where p.id=current_setting('snap.qa1')::uuid),true);
insert into storage.objects(bucket_id,name) select 'moments',current_setting('snap.qa1')||'/test-'||n||'.jpg' from generate_series(1,6) n;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('snap.qa1'),true);
do $$
declare mid uuid;a uuid;
begin
if (select count(*) from public.profiles)<>1 then raise exception 'RLS profile isolation failed';end if;
a:=public.create_album('QA album');
for i in 1..5 loop
mid:=public.create_media(current_setting('snap.qa1')||'/test-'||i||'.jpg','QA photo','photo',a);
end loop;
if (select earned from public.circle_scores() where id=auth.uid())<>50 then raise exception 'Score calculation failed';end if;
perform public.redeem_reward('sage');
perform public.equip_reward('sage');
if (select accent from public.profiles where id=auth.uid())<>'#7eaa91' then raise exception 'Equipping reward failed';end if;
if (select count(*) from public.inventory)<>1 then raise exception 'Redemption failed';end if;
begin perform public.redeem_reward('sticker');raise exception 'Balance bypass allowed';exception when raise_exception then if sqlerrm<>'Collect more points to unlock this' then raise;end if;end;
begin insert into public.inventory(user_id,reward_id,spent) values(auth.uid(),'ink',0);raise exception 'Direct inventory manipulation allowed';exception when insufficient_privilege then null;end;
update public.profiles set name='Unauthorized mutation' where id=auth.uid();
if (select name from public.profiles where id=auth.uid())<>'QA One' then raise exception 'Direct profile mutation allowed';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('snap.qa2'),true);
do $$ begin
if (select count(*) from public.media)<>0 then raise exception 'Circle isolation failed';end if;
perform public.join_circle(current_setting('snap.code'));
if (select count(*) from public.media)<>5 then raise exception 'Circle join failed';end if;
if (select count(*) from public.profiles)<>2 then raise exception 'Circle member visibility failed';end if;
begin perform public.delete_media((select id from public.media limit 1));raise exception 'Friend deletion allowed';exception when raise_exception then if sqlerrm<>'Photo not found' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('snap.qa3'),true);
do $$ begin if (select count(*) from public.media)<>0 then raise exception 'Outside circle access allowed';end if;end $$;
reset role;
rollback;
select 'PASS: circle isolation, joining, points, album, redemption, equip and mutation protection' as result;

