-- v112: customizable profile appearance
alter table public.user_profiles
  add column if not exists accent_color text not null default '#8b5cf6',
  add column if not exists accent_color_2 text not null default '#2563eb',
  add column if not exists profile_effect text not null default 'gradient';

alter table public.user_profiles
  drop constraint if exists user_profiles_accent_color_check,
  add constraint user_profiles_accent_color_check check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  drop constraint if exists user_profiles_accent_color_2_check,
  add constraint user_profiles_accent_color_2_check check (accent_color_2 ~ '^#[0-9A-Fa-f]{6}$'),
  drop constraint if exists user_profiles_profile_effect_check,
  add constraint user_profiles_profile_effect_check check (profile_effect in ('solid','gradient','animated','aurora','none'));

create or replace function public.get_staff_profile(p_user uuid)
returns table(
  user_id uuid, nickname text, account_role text, staff_id uuid, staff_role text,
  appointed_at date, yellow_cards integer, red_cards integer, avatar_url text,
  bio text, display_status text, profile_banner text, accent_color text,
  accent_color_2 text, profile_effect text, last_seen_at timestamptz,
  month_hours bigint, norm_days bigint, inactive_days bigint
)
language sql stable security definer set search_path = public
as $$
  select ur.user_id,ur.nickname,ur.role,ur.staff_id,s.role,s.appointed_at,
    coalesce(s.yellow_cards,0),coalesce(s.red_cards,0),up.avatar_url,up.bio,
    up.display_status,up.profile_banner,coalesce(up.accent_color,'#8b5cf6'),
    coalesce(up.accent_color_2,'#2563eb'),coalesce(up.profile_effect,'gradient'),
    cp.last_seen_at,
    coalesce(sum(dm.norm_value) filter(where dm.status='norm' and dm.mark_date>=date_trunc('month',current_date)::date and dm.mark_date<(date_trunc('month',current_date)+interval '1 month')::date),0)::bigint,
    count(*) filter(where dm.status='norm' and dm.mark_date>=date_trunc('month',current_date)::date and dm.mark_date<(date_trunc('month',current_date)+interval '1 month')::date)::bigint,
    count(*) filter(where dm.status='inactive' and dm.mark_date>=date_trunc('month',current_date)::date and dm.mark_date<(date_trunc('month',current_date)+interval '1 month')::date)::bigint
  from public.user_roles ur
  left join public.staff s on s.id=ur.staff_id
  left join public.user_profiles up on up.user_id=ur.user_id
  left join public.chat_presence cp on cp.user_id=ur.user_id
  left join public.daily_marks dm on dm.staff_id=ur.staff_id
  where ur.user_id=p_user and ur.is_blocked=false and auth.uid() is not null
  group by ur.user_id,ur.nickname,ur.role,ur.staff_id,s.role,s.appointed_at,s.yellow_cards,s.red_cards,
    up.avatar_url,up.bio,up.display_status,up.profile_banner,up.accent_color,up.accent_color_2,up.profile_effect,cp.last_seen_at;
$$;
revoke all on function public.get_staff_profile(uuid) from public;
grant execute on function public.get_staff_profile(uuid) to authenticated;
