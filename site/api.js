const config = window.SNAPCIRCLE_CONFIG || {};
const configured = /^https:\/\/[^/]+\.supabase\.co$/.test(config.supabaseUrl || '') && !!config.supabaseAnonKey;
const sessionKey = 'snapcircle:session:v1';
let session = JSON.parse(localStorage.getItem(sessionKey) || 'null');
let mode = sessionStorage.getItem('snapcircle:demo') === 'yes' ? 'demo' : 'live';
let refreshing;
const urls=[];
function saveSession(s){session=s;localStorage.setItem(sessionKey,JSON.stringify(s))}
async function call(path,{method='GET',body,headers={},auth=true}={}){
 if(!configured)throw Error('Connect your Supabase project in config.js to enable real accounts and shared uploads.');
 if(auth && session && session.expires_at*1000<Date.now()+60000)await refresh();
 const r=await fetch(config.supabaseUrl+path,{method,headers:{apikey:config.supabaseAnonKey,...(auth&&session?{Authorization:'Bearer '+session.access_token}:{}),...(body&&!(body instanceof Blob)?{'Content-Type':'application/json'}:{}),...headers},body:body instanceof Blob?body:body?JSON.stringify(body):undefined});
 if(!r.ok){let d;try{d=await r.json()}catch{d={}}throw Error(d.message||d.msg||d.error_description||d.error||'Could not complete this request. Please try again.');}
 return r.status===204?null:r.headers.get('content-type')?.includes('json')?r.json():r.blob();
}
async function refresh(){if(refreshing)return refreshing;refreshing=(async()=>{try{const d=await call('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:session.refresh_token},auth:false});saveSession({...d,expires_at:Math.floor(Date.now()/1000)+d.expires_in});}catch(e){saveSession(null);throw Error('Your session expired. Please sign in again.');}finally{refreshing=null}})();return refreshing;}
function rpc(name,body={}){return call('/rest/v1/rpc/'+name,{method:'POST',body})}
const redirect=()=>location.origin+location.pathname;
const dbPromise=new Promise((resolve,reject)=>{const r=indexedDB.open('snapcircle-preview',1);r.onupgradeneeded=()=>r.result.createObjectStore('state');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
async function localGet(){const db=await dbPromise;return new Promise((resolve,reject)=>{const r=db.transaction('state').objectStore('state').get('data');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)})}
async function localSave(d){const db=await dbPromise;return new Promise((resolve,reject)=>{const tx=db.transaction('state','readwrite');tx.objectStore('state').put(d,'data');tx.oncomplete=resolve;tx.onerror=()=>reject(Error('Device storage is full. Delete a local photo and try again.'));})}
const rewards=[
{id:'sage',label:'Sage studio',cost:40,type:'theme',value:'#7eaa91'},
{id:'sunset',label:'Peach club',cost:60,type:'theme',value:'#ef9775'},
{id:'ocean',label:'Blue hour',cost:80,type:'theme',value:'#69a9d2'},
{id:'rose',label:'Rose garden',cost:100,type:'theme',value:'#d883a1'},
{id:'midnight',label:'After hours',cost:120,type:'theme',value:'#6875af'},
{id:'sticker',label:'Sticker frame',cost:50,type:'frame',value:'sticker'},
{id:'rounded',label:'Soft corners',cost:75,type:'frame',value:'rounded'},
{id:'ink',label:'Ink outline',cost:100,type:'frame',value:'ink'}];
async function demoData(){let d=await localGet();if(d)return d;d={profile:{id:'demo-me',circle_id:'demo',name:'Alex',title:'Our little universe',bio:'Little moments. Big memories.',accent:'#8c7af0',frame:'classic'},circle:{code:'PREVIEW-ONLY'},members:[{id:'demo-me',name:'Alex'},{id:'demo-friend',name:'Jamie'}],albums:[{id:'weekends',name:'Weekend things'},{id:'small-joys',name:'Small joys'}],media:[['coffee','Slow mornings, good company.','small-joys','demo-me'],['sunset','Stay for the sunset.','weekends','demo-friend'],['plant','A little room to grow.','small-joys','demo-me'],['camera','Collecting the good stuff.','weekends','demo-friend']].map(([art,caption,album_id,owner_id],i)=>({id:'sample-'+i,owner_id,caption,album_id,kind:'photo',points:10,path:'./art/'+art+'.svg',created_at:new Date(Date.now()-(i+1)*86400000).toISOString(),sample:true})),favorites:[],inventory:[]};await localSave(d);return d;}
export const api={
 get configured(){return configured},get isDemo(){return mode==='demo'},get signedIn(){return mode==='demo'||!!session},get userId(){return mode==='demo'?'demo-me':session?.user?.id},rewards,
 async init(){const hash=new URLSearchParams(location.hash.slice(1));if(hash.has('access_token')){saveSession({access_token:hash.get('access_token'),refresh_token:hash.get('refresh_token'),expires_at:Math.floor(Date.now()/1000)+Number(hash.get('expires_in')||3600)});history.replaceState(null,'',location.pathname+(hash.get('type')==='recovery'?'#reset':'#home'));session.user=await call('/auth/v1/user');saveSession(session);}if(session&&!session.user){session.user=await call('/auth/v1/user');saveSession(session)}},
 async login(email,password){const d=await call('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password},auth:false});mode='live';sessionStorage.removeItem('snapcircle:demo');saveSession({...d,expires_at:Math.floor(Date.now()/1000)+d.expires_in});},
 async signup(name,email,password){const d=await call('/auth/v1/signup?redirect_to='+encodeURIComponent(redirect()),{method:'POST',body:{email,password,data:{name}},auth:false});if(d.access_token){mode='live';sessionStorage.removeItem('snapcircle:demo');saveSession({...d,expires_at:Math.floor(Date.now()/1000)+d.expires_in});return true;}return false;},
 async recover(email){await call('/auth/v1/recover?redirect_to='+encodeURIComponent(redirect()),{method:'POST',body:{email},auth:false})},
 async reset(password){await call('/auth/v1/user',{method:'PUT',body:{password}})},
 async logout(){if(mode!=='demo'&&session)await call('/auth/v1/logout',{method:'POST'});saveSession(null);mode='live';sessionStorage.removeItem('snapcircle:demo');},
 async demo(){mode='demo';sessionStorage.setItem('snapcircle:demo','yes');await demoData()},
 async load(){
 urls.forEach(URL.revokeObjectURL);urls.length=0;
 if(mode==='demo'){const d=await demoData();return {...d,members:d.members.map(m=>m.id===d.profile.id?{...m,...d.profile}:m),media:d.media.filter(m=>m.kind!=='snap'||new Date(m.expires_at)>new Date()).map(m=>({...m,url:m.blob?(()=>{const url=URL.createObjectURL(m.blob);urls.push(url);return url})():m.path})),scores:d.members.map(p=>({...p,earned:d.media.filter(m=>m.owner_id===p.id).reduce((s,m)=>s+m.points,0),spent:p.id==='demo-me'?d.inventory.reduce((s,i)=>s+i.spent,0):0}))};}
 const profiles=await call('/rest/v1/profiles?select=*'),profile=profiles.find(p=>p.id===session.user.id);if(!profile)throw Error('Account profile missing. Run supabase/setup.sql before creating accounts.');
 const [circles,media,albums,favorites,inventory,scores]=await Promise.all([call('/rest/v1/circles?select=*'),call('/rest/v1/media?select=*&order=created_at.desc'),call('/rest/v1/albums?select=*&order=created_at.desc'),call('/rest/v1/favorites?select=*'),call('/rest/v1/inventory?select=*'),rpc('circle_scores')]);
 const hydrated=await Promise.all(media.map(async m=>{try{const blob=await call('/storage/v1/object/authenticated/moments/'+m.path);const url=URL.createObjectURL(blob);urls.push(url);return {...m,url}}catch{return {...m,url:null}}}));
 return {profile,circle:circles[0],members:profiles,media:hydrated,albums,favorites:favorites.map(f=>f.media_id),inventory,scores};
 },
 async upload(blob,caption,kind,album_id){
 if(mode==='demo'){const d=await demoData();if(d.media.filter(m=>m.owner_id==='demo-me'&&new Date(m.created_at)>new Date(Date.now()-86400000)).length>=20)throw Error('Daily limit reached. Try again tomorrow.');d.media.unshift({id:crypto.randomUUID(),owner_id:'demo-me',caption,kind,album_id,points:kind==='snap'?15:10,created_at:new Date().toISOString(),expires_at:kind==='snap'?new Date(Date.now()+86400000).toISOString():null,blob});return localSave(d)}
 const path=session.user.id+'/'+crypto.randomUUID()+'.jpg';await call('/storage/v1/object/moments/'+path,{method:'POST',body:blob,headers:{'Content-Type':'image/jpeg','x-upsert':'false'}});
 try{await rpc('create_media',{object_path:path,photo_caption:caption,media_kind:kind,target_album:album_id||null});}catch(e){await call('/storage/v1/object/moments',{method:'DELETE',body:{prefixes:[path]}}).catch(()=>{});throw e;}
 },
 async remove(id){if(mode==='demo'){const d=await demoData();d.media=d.media.filter(m=>m.id!==id||m.owner_id!=='demo-me');return localSave(d)}const path=await rpc('delete_media',{media_id:id});try{await call('/storage/v1/object/moments',{method:'DELETE',body:{prefixes:[path]}})}catch{throw Error('Photo removed from the circle. Storage cleanup could not finish.')}} ,
 async favorite(id){if(mode==='demo'){const d=await demoData();d.favorites=d.favorites.includes(id)?d.favorites.filter(x=>x!==id):[...d.favorites,id];return localSave(d)}const existing=await call('/rest/v1/favorites?media_id=eq.'+id);return call('/rest/v1/favorites'+(existing.length?'?media_id=eq.'+id:''),{method:existing.length?'DELETE':'POST',body:existing.length?undefined:{user_id:session.user.id,media_id:id}})},
 async album(name){if(mode==='demo'){const d=await demoData();d.albums.unshift({id:crypto.randomUUID(),name});return localSave(d)}return rpc('create_album',{album_name:name})},
 async join(code){if(mode==='demo')throw Error('Preview mode stays on this device. Connect Supabase and sign in to share a circle.');return rpc('join_circle',{invite:code})},
 async settings(p){if(mode==='demo'){const d=await demoData();d.profile={...d.profile,...p};d.members[0].name=p.name;return localSave(d)}return rpc('save_profile',{display_name:p.name,space_title:p.title,description:p.bio,color:p.accent})},
 async redeem(id){if(mode==='demo'){const d=await demoData(),r=rewards.find(r=>r.id===id),balance=d.media.filter(m=>m.owner_id==='demo-me').reduce((s,m)=>s+m.points,0)-d.inventory.reduce((s,i)=>s+i.spent,0);if(balance<r.cost)throw Error('Collect more points to unlock this.');if(d.inventory.some(i=>i.reward_id===id))throw Error('Already in your inventory.');d.inventory.push({reward_id:id,spent:r.cost});return localSave(d)}return rpc('redeem_reward',{reward:id})},
 async equip(id){if(mode==='demo'){const d=await demoData();if(id==='classic')d.profile.frame='classic';else{const r=rewards.find(r=>r.id===id);if(!d.inventory.some(i=>i.reward_id===id))throw Error('Unlock this first.');d.profile[r.type==='theme'?'accent':'frame']=r.value;}return localSave(d)}return rpc('equip_reward',{reward:id})}
};

