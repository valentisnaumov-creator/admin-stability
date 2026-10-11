#!/usr/bin/env node
/**
 * Private, server-side Supabase PostgreSQL -> Firebase Firestore staging importer.
 * Requires: npm install pg firebase-admin
 * Environment: SOURCE_DATABASE_URL, GOOGLE_APPLICATION_CREDENTIALS,
 *               FIREBASE_PROJECT_ID=admin-stability
 * Dry run by default. To actually write set MIGRATION_WRITE=YES.
 * NEVER run in a browser or GitHub Pages, and NEVER commit credentials/data.
 */
const { Client } = require('pg');
const admin = require('firebase-admin');
const crypto = require('node:crypto');

const tables = [
 'staff','daily_marks','schedule_assignments','schedule_slots','user_roles',
 'account_audit_log','user_profiles','chat_messages','chat_reactions',
 'schedule_replacements','chat_message_views','chat_preferences',
 'chat_conversations','chat_conversation_members','private_messages',
 'chat_presence','chat_attachments','chat_pins','site_notifications',
 'chat_mentions','system_messages','staff_activity_audit'
];
// Exclude registration_invites: old invitation tokens must NOT be reactivated.
const keys = {
 staff:['id'],daily_marks:['id'],schedule_assignments:['id'],
 schedule_slots:['slot_key'],user_roles:['user_id'],account_audit_log:['id'],
 user_profiles:['user_id'],chat_messages:['id'],chat_reactions:['message_id','user_id','emoji'],
 schedule_replacements:['id'],chat_message_views:['message_id','user_id'],
 chat_preferences:['user_id'],chat_conversations:['id'],
 chat_conversation_members:['conversation_id','user_id'],private_messages:['id'],
 chat_presence:['user_id'],chat_attachments:['id'],chat_pins:['id'],
 site_notifications:['id'],chat_mentions:['id'],system_messages:['id'],
 staff_activity_audit:['id']
};
function docId(table,row) {
 const parts=keys[table].map(k=>row[k]);
 if(parts.some(v=>v===null||v===undefined))throw Error('Missing key in '+table);
 if(parts.length===1)return String(parts[0]);
 return crypto.createHash('sha256').update(JSON.stringify(parts.map(String))).digest('hex');
}
function normalize(row) {
 return Object.fromEntries(Object.entries(row).map(([k,v])=>[
  k, v instanceof Date?v.toISOString():v
 ]));
}
async function main(){
 const write=process.env.MIGRATION_WRITE==='YES';
 if(!process.env.SOURCE_DATABASE_URL)throw Error('SOURCE_DATABASE_URL required');
 if(write && (!process.env.GOOGLE_APPLICATION_CREDENTIALS||process.env.FIREBASE_PROJECT_ID!=='admin-stability'))
  throw Error('Set GOOGLE_APPLICATION_CREDENTIALS and FIREBASE_PROJECT_ID=admin-stability');
 const pg=new Client({connectionString:process.env.SOURCE_DATABASE_URL,ssl:{rejectUnauthorized:true}});
 await pg.connect();
 try {
  await pg.query('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
  if(write)admin.initializeApp({credential:admin.credential.applicationDefault(),projectId:'admin-stability'});
  const db=write?admin.firestore():null;
  const manifest={mode:write?'IMPORT':'DRY_RUN',tables:{},excluded:['registration_invites']};
  for(const table of tables){
   const {rows}=await pg.query('SELECT * FROM public."'+table+'"');
   const ids=new Set();
   for(const row of rows){const id=docId(table,row);if(ids.has(id))throw Error('Duplicate key: '+table+'/'+id);ids.add(id);}
   if(write){
    // Writes are idempotent and bounded; the production database is never modified.
    for(let i=0;i<rows.length;i+=400){
     const batch=db.batch();
     for(const row of rows.slice(i,i+400))batch.set(db.collection(table).doc(docId(table,row)),normalize(row));
     await batch.commit();
    }
   }
   manifest.tables[table]={rows:rows.length,uniqueDocumentIds:ids.size};
   console.log(table+': '+rows.length+(write?' imported':' validated'));
  }
  await pg.query('COMMIT');
  console.log(JSON.stringify(manifest,null,2));
  console.log('IMPORTANT: user_roles document IDs still contain Supabase Auth user IDs. Do not enable client access until Firebase UID mapping is complete.');
 }catch(e){await pg.query('ROLLBACK').catch(()=>{});throw e}
 finally{await pg.end()}
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
