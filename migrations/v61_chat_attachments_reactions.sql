-- v61: allow attachment-only messages and expand reactions
alter table public.chat_messages drop constraint if exists chat_messages_body_check;
alter table public.chat_messages add constraint chat_messages_body_check
check (
  (char_length(trim(body)) between 1 and 1500)
  or
  (char_length(trim(body)) = 0 and char_length(trim(attachment_url)) > 0)
);

alter table public.chat_reactions drop constraint if exists chat_reactions_emoji_check;
