-- v59 messenger
alter table public.chat_messages add column if not exists attachment_url text not null default '';
alter table public.chat_messages add column if not exists attachment_name text not null default '';
alter table public.chat_messages add column if not exists attachment_type text not null default '';
alter table public.chat_messages add column if not exists attachment_size bigint not null default 0;

create table if not exists public.chat_message_views (
 message_id bigint not null references public.chat_messages(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 viewed_at timestamptz not null default now(),
 primary key(message_id,user_id)
);
alter table public.chat_message_views enable row level security;
drop policy if exists "chat_views_read" on public.chat_message_views;
create policy "chat_views_read" on public.chat_message_views for select to authenticated using(true);
drop policy if exists "chat_views_add" on public.chat_message_views;
create policy "chat_views_add" on public.chat_message_views for insert to authenticated with check(user_id=auth.uid());

create table if not exists public.chat_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 theme text not null default 'default',
 bubble_style text not null default 'rounded',
 updated_at timestamptz not null default now()
);
alter table public.chat_preferences enable row level security;
drop policy if exists "chat_prefs_read" on public.chat_preferences;
create policy "chat_prefs_read" on public.chat_preferences for select to authenticated using(user_id=auth.uid());
drop policy if exists "chat_prefs_add" on public.chat_preferences;
create policy "chat_prefs_add" on public.chat_preferences for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "chat_prefs_edit" on public.chat_preferences;
create policy "chat_prefs_edit" on public.chat_preferences for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

insert into storage.buckets(id,name,public,file_size_limit)
values('chat-files','chat-files',true,20971520)
on conflict(id) do update set public=true,file_size_limit=20971520;

drop policy if exists "chat_files_read" on storage.objects;
create policy "chat_files_read" on storage.objects for select using(bucket_id='chat-files');
drop policy if exists "chat_files_add" on storage.objects;
create policy "chat_files_add" on storage.objects for insert to authenticated
with check(bucket_id='chat-files' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "chat_files_remove" on storage.objects;
create policy "chat_files_remove" on storage.objects for delete to authenticated
using(bucket_id='chat-files' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.edit_my_chat_message(p_message bigint,p_body text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if char_length(trim(coalesce(p_body,''))) not between 1 and 1500 then raise exception 'Invalid message length'; end if;
 update public.chat_messages set body=trim(p_body),edited_at=now()
 where id=p_message and user_id=auth.uid();
 if not found then raise exception 'Message not found'; end if;
end
$$;
grant execute on function public.edit_my_chat_message(bigint,text) to authenticated;
