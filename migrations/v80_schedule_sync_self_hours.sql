-- v80: reliable schedule sync + self hours entry

create or replace function public.get_schedule_assignments()
returns setof public.schedule_assignments
language sql
stable
security definer
set search_path = public
as $$
  select sa.*
  from public.schedule_assignments sa
  where auth.uid() is not null
    and public.current_app_role() <> 'blocked'
  order by sa.work_date, sa.slot_key, sa.created_at;
$$;

grant execute on function public.get_schedule_assignments() to authenticated;

create or replace function public.save_my_daily_hours(
  p_date date,
  p_hours integer,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff uuid;
begin
  if auth.uid() is null then
    raise exception 'Необходимо войти в аккаунт';
  end if;

  if public.current_app_role() not in ('admin','trainee') then
    raise exception 'Эта функция доступна администратору или стажёру';
  end if;

  select staff_id into v_staff
  from public.user_roles
  where user_id = auth.uid();

  if v_staff is null then
    raise exception 'Аккаунт не привязан к сотруднику в составе';
  end if;

  if p_date > current_date then
    raise exception 'Нельзя указывать часы за будущую дату';
  end if;

  if p_hours < 0 or p_hours > 24 then
    raise exception 'Количество часов должно быть от 0 до 24';
  end if;

  insert into public.daily_marks(staff_id, mark_date, status, norm_value, note, updated_at)
  values(v_staff, p_date, 'norm', p_hours, left(trim(coalesce(p_note,'')),500), now())
  on conflict(staff_id, mark_date) do update set
    status = 'norm',
    norm_value = excluded.norm_value,
    note = excluded.note,
    updated_at = now();
end;
$$;

grant execute on function public.save_my_daily_hours(date, integer, text) to authenticated;

-- Ensure authenticated users can see the shared schedule even if an older migration
-- replaced the original public read policy.
drop policy if exists "schedule_authenticated_read" on public.schedule_assignments;
create policy "schedule_authenticated_read"
on public.schedule_assignments
for select to authenticated
using (public.current_app_role() <> 'blocked');
