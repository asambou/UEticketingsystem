// Privileged mail delivery stays on the server. Every request is authenticated
// against Supabase Auth and requires current, active Energy admin membership.
const origin='https://asambou.github.io';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Vary':'Origin'};
Deno.serve(async(req:Request)=>{
 const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{message:'POST required'});
 const authorization=req.headers.get('authorization');
 if(!authorization?.startsWith('Bearer '))return reply(401,{message:'Staff sign-in required'});
 const url=Deno.env.get('SUPABASE_URL')!;
 const serviceKey=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 const pubKey=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default||Deno.env.get('SUPABASE_ANON_KEY');
 if(!serviceKey||!pubKey)return reply(503,{message:'Membership service is not configured'});
 try{
  const userResponse=await fetch(url+'/auth/v1/user',{headers:{apikey:pubKey,Authorization:authorization}});
  if(!userResponse.ok)return reply(401,{message:'Your session is invalid or expired'});
  const user=await userResponse.json();
  const check=await fetch(url+'/rest/v1/profiles?select=role,active&id=eq.'+encodeURIComponent(user.id),{headers:{apikey:pubKey,Authorization:authorization}});
  const members=check.ok?await check.json():[];
  if(!members.some((m:{role:string,active:boolean})=>m.active&&m.role==='admin'))return reply(403,{message:'Only approved Energy administrators can invite members'});
  const body=await req.json();
  const {email,name,role}=body;
  if(typeof email!=='string'||email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||typeof name!=='string'||!name.trim()||name.length>120||!['admin','manager','dispatcher','technician'].includes(role))return reply(400,{message:'A valid staff email, name and role are required'});
  const cleanEmail=email.trim().toLowerCase();
  const callerHeaders={apikey:pubKey,Authorization:authorization};
  const releaseResponse=await fetch(url+'/rest/v1/energy_invitation_release?select=approved&id=eq.true',{headers:callerHeaders});
  const release=releaseResponse.ok?await releaseResponse.json():[];
  if(!release[0]?.approved)return reply(403,{message:'Invitations are on hold pending Operations approval.'});
  const queueResponse=await fetch(url+'/rest/v1/energy_invitation_queue?select=*&email=eq.'+encodeURIComponent(cleanEmail),{headers:callerHeaders});
  const queue=queueResponse.ok?await queueResponse.json():[];
  if(!queue[0]?.included||queue[0].status!=='pending'||queue[0].name!==name.trim()||queue[0].role!==role)return reply(403,{message:'Review and include this exact staff entry in the pending invitation list first.'});

  const invite=await fetch(url+'/auth/v1/invite?redirect_to='+encodeURIComponent(origin+'/UEticketingsystem/'),{method:'POST',headers:{apikey:serviceKey,...(serviceKey.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+serviceKey}),'Content-Type':'application/json'},body:JSON.stringify({email:cleanEmail,data:{name:name.trim()}})});
  const sent=await invite.json().catch(()=>({}));
  const exists=['email_exists','user_already_exists'].includes(sent.error_code)||/already (been registered|registered|exists)/i.test(sent.msg||sent.message||'');
  if(!invite.ok&&!exists)return reply(400,{message:sent.msg||sent.message||'Invitation could not be sent. Check project email delivery settings.'});
  // Uses the caller's JWT, so an admin revoked during mail delivery cannot
  // approve membership. An unapproved Auth account has no ticket access.
  const approval=await fetch(url+'/rest/v1/rpc/admin_approve_member',{method:'POST',headers:{apikey:pubKey,Authorization:authorization,'Content-Type':'application/json'},body:JSON.stringify({p_email:cleanEmail,p_name:name.trim(),p_role:role})});
  const approved=await approval.json();
  if(!approval.ok)return reply(400,{message:approved.message||'Account was invited but membership was not approved; ask an active administrator to review it.'});
  await fetch(url+'/rest/v1/rpc/energy_mark_invitation_sent',{method:'POST',headers:{...callerHeaders,'Content-Type':'application/json'},body:JSON.stringify({p_email:cleanEmail})});
  return reply(200,{id:approved,invitation:invite.ok?'sent':'existing_account',message:invite.ok?'Invitation sent and Energy access approved.':'Existing account approved for Energy access.'});
 }catch{return reply(500,{message:'Membership request failed. No access is granted without administrator approval.'})}
});
