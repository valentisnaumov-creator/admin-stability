#!/usr/bin/env node
// Offline migration preflight. No credentials, network, or writes.
const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');

const tables = [
 'staff','daily_marks','schedule_assignments','schedule_slots','user_roles',
 'account_audit_log','registration_invites','user_profiles','chat_messages',
 'chat_reactions','schedule_replacements','chat_message_views','chat_preferences',
 'chat_conversations','chat_conversation_members','private_messages',
 'chat_presence','chat_attachments','chat_pins','site_notifications',
 'chat_mentions','system_messages','staff_activity_audit'
];
const primary = {
 staff:'id',daily_marks:'id',schedule_assignments:'id',schedule_slots:'slot_key',
 user_roles:'user_id',account_audit_log:'id',registration_invites:'id',
 user_profiles:'user_id',chat_messages:'id',schedule_replacements:'id',
 chat_conversations:'id',private_messages:'id',site_notifications:'id',
 system_messages:'id',staff_activity_audit:'id'
};
function loadRows(dir, name) {
 const filename = path.join(dir, name + '.json');
 if (!fs.existsSync(filename)) return null;
 const rows = JSON.parse(fs.readFileSync(filename,'utf8'));
 if (!Array.isArray(rows)) throw new Error(name + ': expected JSON array');
 return rows;
}
function check(dir) {
 const result = {tables:{},errors:[],warnings:[]};
 const data = {};
 for (const name of tables) {
  const rows = loadRows(dir,name);
  if (!rows) {result.errors.push('Missing table export: '+name);continue;}
  data[name]=rows;
  const digest=crypto.createHash('sha256').update(JSON.stringify(rows)).digest('hex');
  result.tables[name]={count:rows.length,sha256:digest};
  const key=primary[name];
  if(key) {
   const ids=new Set();
   for(const row of rows) {
    const id=row[key];
    if(id===undefined||id===null||String(id)==='')result.errors.push(name+': missing '+key);
    else if(ids.has(String(id)))result.errors.push(name+': duplicate '+key+' '+String(id));
    else ids.add(String(id));
   }
  } else result.warnings.push(name+': composite document ID must be defined before import');
 }
 const staff=new Set((data.staff||[]).map(x=>String(x.id)));
 for(const name of ['daily_marks','schedule_assignments','user_roles']) {
  for(const row of data[name]||[])if(row.staff_id && !staff.has(String(row.staff_id)))
   result.errors.push(name+': missing staff reference '+String(row.staff_id));
 }
 const assignments=new Set((data.schedule_assignments||[]).map(x=>String(x.id)));
 for(const row of data.schedule_replacements||[]) {
  if(row.assignment_id && !assignments.has(String(row.assignment_id)))
   result.errors.push('schedule_replacements: missing assignment '+String(row.assignment_id));
 }
 return result;
}
if(require.main===module){
 const dir=process.argv[2];
 if(!dir){console.error('Usage: node firebase/preflight.cjs /path/to/private/json-export');process.exit(2)}
 try {
  const result=check(dir);
  // Only print counts and diagnostics; never dump exported private data.
  console.log(JSON.stringify(result,null,2));
  process.exitCode=result.errors.length?1:0;
 }catch(e){console.error('Preflight failed:',e.message);process.exitCode=1}
}
module.exports={check,tables};
