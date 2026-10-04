-- v79: fix recursive RLS for private conversation members

-- Security-definer helper avoids a policy querying the same protected table recursively.
create or replace function public.is_conversation_member(p_conversation uuid, p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.chat_conversation_members
    where conversation_id = p_conversation
      and user_id = p_user
  );
$$;

revoke all on function public.is_conversation_member(uuid, uuid) from public;
grant execute on function public.is_conversation_member(uuid, uuid) to authenticated;

drop policy if exists "conversation_member_read" on public.chat_conversations;
create policy "conversation_member_read"
on public.chat_conversations
for select to authenticated
using (public.is_conversation_member(id, auth.uid()));

drop policy if exists "members_member_read" on public.chat_conversation_members;
create policy "members_member_read"
on public.chat_conversation_members
for select to authenticated
using (public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "members_self_update" on public.chat_conversation_members;
create policy "members_self_update"
on public.chat_conversation_members
for update to authenticated
using (user_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()))
with check (user_id = auth.uid());

drop policy if exists "private_member_read" on public.private_messages;
create policy "private_member_read"
on public.private_messages
for select to authenticated
using (public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "private_member_insert" on public.private_messages;
create policy "private_member_insert"
on public.private_messages
for insert to authenticated
with check (
  user_id = auth.uid()
  and public.is_conversation_member(conversation_id, auth.uid())
);

-- start_direct_conversation remains SECURITY DEFINER and creates both members atomically.
