-- v62: fix invite token generation on Supabase
create extension if not exists pgcrypto with schema extensions;

create or replace function public.create_registration_invite(
    p_role text default 'trainee',
    p_hours integer default 24
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_token text;
begin
    if auth.uid() is null then
        raise exception 'Необходимо войти в аккаунт';
    end if;

    if public.current_app_role() <> 'creator' then
        raise exception 'Создавать приглашения может только Создатель';
    end if;

    if p_role not in ('creator','chief_admin','admin','trainee') then
        raise exception 'Неизвестная роль';
    end if;

    if p_hours not in (24,72,168) then
        raise exception 'Недопустимый срок действия приглашения';
    end if;

    v_token := encode(extensions.gen_random_bytes(32), 'hex');

    insert into public.registration_invites(
        token, role, created_by, expires_at
    )
    values(
        v_token,
        p_role,
        auth.uid(),
        now() + make_interval(hours => p_hours)
    );

    return v_token;
end;
$$;

grant execute on function public.create_registration_invite(text, integer) to authenticated;
