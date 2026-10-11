# Firebase migration plan

Current production: Supabase. Firebase is a separate staging environment.

## Source collections
staff, daily_marks, schedule_assignments, schedule_slots, user_roles, account_audit_log, registration_invites, user_profiles, chat_messages, chat_reactions, schedule_replacements, chat_message_views, chat_preferences, chat_conversations, chat_conversation_members, private_messages, chat_presence, chat_attachments, chat_pins, site_notifications, chat_mentions, system_messages, staff_activity_audit.

Also migrate Supabase authentication accounts and any application storage files separately.

## Steps
1. Keep Firestore rules closed until role-based access is implemented.
2. Verify real Firebase Authentication and Firestore requests on the affected mobile device.
3. Create a private server-side export of every source table and associated files. Check row counts.
4. Map source IDs to Firestore document IDs. Preserve relationships and timestamps.
5. Migrate user accounts with a planned password reset and map original user IDs to new Firebase Auth IDs.
6. Implement and test role-based permissions, including blocked accounts and creator-only operations.
7. Replace Supabase-specific database calls, RPCs, Realtime, and file storage in a separate test site.
8. Validate records and workflows, perform a final sync, then switch the production site.

Do not publish user data or privileged credentials in the repository. Keep Supabase available for rollback.
