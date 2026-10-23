import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 try{
  if(req.method!=='POST')throw Error('Method not allowed');
  const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');if(!token)throw Error('Missing authorization');
  const auth=createClient(url,anon);const {data:{user},error}=await auth.auth.getUser(token);if(error||!user)throw Error('Unauthorized');
  const admin=createClient(url,secret);const {data:caller,error:ce}=await admin.from('profiles').select('role,active').eq('id',user.id).single();if(ce||caller?.role!=='admin'||!caller.active)throw Error('Admin only');
  const {email,full_name}=await req.json();if(typeof email!=='string'||typeof full_name!=='string'||!/^\S+@\S+\.\S+$/.test(email)||full_name.trim().length<2||full_name.length>120)throw Error('Invalid input');
  const {data:invite,error:ie}=await admin.auth.admin.inviteUserByEmail(email.trim().toLowerCase(),{data:{full_name:full_name.trim()}});if(ie||!invite.user)throw ie||Error('Invite failed');
  const {error:pe}=await admin.from('profiles').upsert({id:invite.user.id,email:email.trim().toLowerCase(),full_name:full_name.trim(),role:'employee',active:true},{onConflict:'id'});if(pe)throw pe;
  return new Response(JSON.stringify({ok:true}),{headers});
 }catch(e){return new Response(JSON.stringify({error:e instanceof Error?e.message:'Unknown error'}),{status:400,headers})}
});
