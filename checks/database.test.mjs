import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';

// Isolated PostgreSQL, with a minimal hosted-services fixture, not mocked SQL.
// This validates the new migrations, not the entire historical Supabase stack.
test('migrations, principals, immutable device keys, call transitions and delivery leases',async()=>{
 const db=new PGlite();const sql=s=>db.exec(s);const rows=async s=>(await db.query(s)).rows;
 const a='00000000-0000-4000-8000-000000000001', b=a.replace(/1$/,'2'), stranger=a.replace(/1$/,'3'),c=a.replace(/1$/,'4'),id=a.replace(/1$/,'5');
 await sql(`create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; grant usage on schema auth to authenticated; create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('bro.uid',true),'')::uuid $$;
 create table message_edit_history(message_id uuid,previous_content text,new_content text);create table conversations(id uuid primary key);create table conversation_participants(conversation_id uuid,user_id uuid,draft text);
 create table messages(id uuid primary key, conversation_id uuid,sender_id uuid,content text,reply_to_id uuid);
 create table message_reactions(id uuid,emoji text);create table scheduled_messages(content text,conversation_id uuid,attachment_url text,attachment_mime text);
 create function is_conversation_member(uuid) returns boolean language sql stable security definer as $$select exists(select from public.conversation_participants where user_id=auth.uid() and conversation_id=$1)$$;
 create function shares_conversation(uuid,uuid) returns boolean language sql stable security definer as $$select exists(select from public.conversation_participants a join public.conversation_participants b using(conversation_id) where a.user_id=$1 and b.user_id=$2)$$;
 create schema realtime; create table realtime.messages(id uuid);create policy "Conversation members send call signals" on realtime.messages for insert with check(true);
 create function realtime.send(jsonb,text,text,boolean) returns void language sql as $$select$$;
 create schema vault;create table vault.decrypted_secrets(name text,decrypted_secret text);
 insert into auth.users values('${a}'),('${b}'),('${stranger}');insert into conversations values('${c}');insert into conversation_participants(conversation_id,user_id) values('${c}','${a}'),('${c}','${b}');`);
 for(const migration of ['secure_devices','fcm_delivery','call_relay'].map((n,i)=>`202611200${i}0000_${n}`))await sql(readFileSync(new URL(`../supabase/migrations/${migration}.sql`,import.meta.url),'utf8'));
 const login=async user=>sql(`reset role;set role authenticated; set bro.uid='${user}';`);
 const fp='a'.repeat(64), pub='-----BEGIN PGP PUBLIC KEY BLOCK-----'+'a'.repeat(100);
 await login(a);await sql(`insert into chat_device_keys(user_id,fingerprint,public_key) values('${a}','${fp}','${pub}') on conflict(fingerprint) do nothing`);
 await assert.rejects(sql(`update chat_device_keys set public_key='x'`));
 await assert.rejects(sql(`insert into chat_device_keys(user_id,fingerprint,public_key) values('${b}','${'b'.repeat(64)}','${pub}')`));
 await sql(`insert into fcm_devices(user_id,device_id,token,platform) values('${a}','${id}','${'a'.repeat(40)}','android')`);
 await login(b);assert.equal((await rows('select * from fcm_devices')).length,0); assert.equal((await rows('select * from chat_device_keys')).length,1);
 await sql(`select revoke_chat_key('${fp}')`);assert.equal((await rows('select revoked_at from chat_device_keys'))[0].revoked_at,null);
 await login(stranger);assert.equal((await rows('select * from chat_device_keys')).length,0);assert.equal((await rows(`select claim_call_relay('${c}') ok`))[0].ok,false);
 const signal=(kind,peer)=>sql(`select signal_call('${id}','${c}','${peer}','${kind}','{}')`);
 await assert.rejects(signal('invite',a));await login(a);assert.equal((await rows(`select claim_call_relay('${c}') ok`))[0].ok,true);
 await signal('invite',b);await assert.rejects(signal('invite',b));await assert.rejects(signal('accept',b));await assert.rejects(signal('offer',b));
 await login(stranger);assert.equal((await rows('select * from call_sessions')).length,0);await assert.rejects(signal('ice',a));
 await login(b);await signal('accept',a);await assert.rejects(signal('accept',a));await signal('ice',a);await signal('hangup',a);await assert.rejects(signal('heartbeat',a));
 await assert.rejects(sql(`select claim_push('event','${id}')`));await sql('reset role;set role service_role');const claim="select claim_push('event',(select id from fcm_devices)) ok";
 assert.equal((await rows(claim))[0].ok,true);assert.equal((await rows(claim))[0].ok,false);
 await db.close();
});
