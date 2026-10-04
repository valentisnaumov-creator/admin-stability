-- v102: automatic system inbox events for staff metrics and schedule replacements
create or replace function public.user_for_staff(p_staff uuid)
returns uuid language sql security definer set search_path=public stable as $$
 select user_id from public.user_roles where staff_id=p_staff and coalesce(is_blocked,false)=false order by created_at limit 1
$$;
revoke all on function public.user_for_staff(uuid) from public,anon,authenticated;

create or replace function public.notify_staff_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_uid uuid; v_body text;
begin
 v_uid:=public.user_for_staff(coalesce(new.id,old.id));
 if v_uid is null then return coalesce(new,old); end if;
 if tg_op='UPDATE' then
   if new.yellow_cards is distinct from old.yellow_cards or new.red_cards is distinct from old.red_cards then
     v_body:='Карточки изменены. Жёлтые: '||coalesce(new.yellow_cards,0)||', красные: '||coalesce(new.red_cards,0)||'.';
     perform public.push_system_message(v_uid,'cards','Изменение карточек',v_body,'mystats');
   end if;
   if new.dismissed_at is distinct from old.dismissed_at then
     perform public.push_system_message(v_uid,'staff',
       case when new.dismissed_at is null then 'Возвращение в состав' else 'Изменение состава' end,
       case when new.dismissed_at is null then 'Вы возвращены в действующий состав.' else 'Вы переведены в архив состава.' end,'mystats');
   end if;
 end if;
 return coalesce(new,old);
end $$;
drop trigger if exists staff_system_notify on public.staff;
create trigger staff_system_notify after update on public.staff for each row execute function public.notify_staff_change();

create or replace function public.notify_daily_mark_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_uid uuid; v_date date; v_body text; v_staff uuid;
begin
 v_staff:=coalesce(new.staff_id,old.staff_id); v_uid:=public.user_for_staff(v_staff);
 if v_uid is null or auth.uid()=v_uid then return coalesce(new,old); end if;
 v_date:=coalesce(new.mark_date,old.mark_date);
 if tg_op='DELETE' then
   v_body:='Отметка за '||to_char(v_date,'DD.MM.YYYY')||' удалена.';
 else
   v_body:=case when new.status='inactive'
     then 'На '||to_char(v_date,'DD.MM.YYYY')||' установлен неактив.'||
          case when nullif(trim(coalesce(new.note,'')),'') is not null then ' Причина: '||left(new.note,180) else '' end
     else 'Данные за '||to_char(v_date,'DD.MM.YYYY')||' изменены. Онлайн: '||coalesce(new.norm_value,0)||' ч.' end;
 end if;
 perform public.push_system_message(v_uid,case when tg_op<>'DELETE' and new.status='inactive' then 'inactive' else 'hours' end,
   case when tg_op<>'DELETE' and new.status='inactive' then 'Неактив' else 'Изменение показателей' end,v_body,'mystats');
 return coalesce(new,old);
end $$;
drop trigger if exists daily_marks_system_notify on public.daily_marks;
create trigger daily_marks_system_notify after insert or update or delete on public.daily_marks for each row execute function public.notify_daily_mark_change();

create or replace function public.notify_replacement_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_target uuid; v_requester uuid; v_a public.schedule_assignments%rowtype; v_name text;
begin
 select * into v_a from public.schedule_assignments where id=coalesce(new.assignment_id,old.assignment_id);
 if tg_op='INSERT' then
   v_target:=public.user_for_staff(new.replacement_staff_id);
   select nickname into v_name from public.user_roles where user_id=new.requester_user_id;
   if v_target is not null then
     perform public.push_system_message(v_target,'replacement','Запрос на замену',
       coalesce(v_name,'Сотрудник')||' просит заменить его в смене '||coalesce(v_a.slot_key,'')||' на '||to_char(v_a.work_date,'DD.MM.YYYY')||
       case when nullif(trim(new.reason),'') is not null then '. Причина: '||left(new.reason,180) else '' end,'schedule');
   end if;
 elsif tg_op='UPDATE' and new.status is distinct from old.status then
   v_requester:=new.requester_user_id;
   perform public.push_system_message(v_requester,'replacement',
     case new.status when 'accepted' then 'Замена подтверждена' when 'rejected' then 'Замена отклонена' when 'cancelled' then 'Замена отменена' else 'Статус замены изменён' end,
     case new.status when 'accepted' then 'Ваш запрос на замену подтверждён.' when 'rejected' then 'Ваш запрос на замену отклонён.' when 'cancelled' then 'Ваш запрос на замену отменён.' else 'Статус запроса на замену изменён.' end,'schedule');
   if new.status='accepted' then
     v_target:=public.user_for_staff(new.replacement_staff_id);
     if v_target is not null then perform public.push_system_message(v_target,'replacement','Замена принята','Вы приняли смену '||coalesce(v_a.slot_key,'')||' на '||to_char(v_a.work_date,'DD.MM.YYYY')||'.','schedule'); end if;
   end if;
 end if;
 return coalesce(new,old);
end $$;
drop trigger if exists schedule_replacements_system_notify on public.schedule_replacements;
create trigger schedule_replacements_system_notify after insert or update on public.schedule_replacements for each row execute function public.notify_replacement_change();
