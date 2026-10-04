-- v72: hard server-side limit of 2 schedule shifts per staff member per date
create or replace function public.enforce_schedule_max_two()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  -- Serialize attempts for the same staff/date so rapid double clicks cannot bypass the limit.
  perform pg_advisory_xact_lock(
    hashtext(new.staff_id::text),
    hashtext(new.work_date::text)
  );

  select count(*)
    into v_count
  from public.schedule_assignments
  where staff_id = new.staff_id
    and work_date = new.work_date
    and (tg_op <> 'UPDATE' or id <> new.id);

  if v_count >= 2 then
    raise exception 'Можно выбрать максимум 2 смены в день'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists schedule_max_two_per_day on public.schedule_assignments;
create trigger schedule_max_two_per_day
before insert or update of staff_id, work_date
on public.schedule_assignments
for each row
execute function public.enforce_schedule_max_two();

-- Report already-invalid rows so they can be cleaned up manually.
select
  work_date,
  staff_id,
  count(*) as shifts
from public.schedule_assignments
group by work_date, staff_id
having count(*) > 2
order by work_date desc, shifts desc;
