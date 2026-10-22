'use strict';
const $ = id => document.getElementById(id);
const config=window.POKER_CONFIG||{};
const validConfig = /^https:\/\/.+\.supabase\.co\/?$/.test(config.supabaseUrl||'') && !!config.supabaseKey && !config.supabaseKey.includes('PASTE_');
let db, invite='', busy=false, lastSnapshot='', refreshTimer;
const show = id => ['home','room','setup'].forEach(x=>$(x).classList.toggle('hidden',x!==id));
const message = (s='') => $('message').textContent=s;
const esc = v => String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function codeFrom(s){ const t=s.trim(); try{const u=new URL(t);return u.searchParams.get('room')||''}catch{return t} }
function urlFor(code){const u=new URL(location.href);u.search='';u.hash='';u.searchParams.set('room',code);return u.href}
function randomCode(){const bytes=new Uint8Array(12);crypto.getRandomValues(bytes);return [...bytes].map(x=>x.toString(16).padStart(2,'0')).join('')}
async function rpc(fn,args){const {data,error}=await db.rpc(fn,args);if(error)throw Error(error.message);return data}
async function locked(fn){if(busy)return;busy=true;try{message('');await fn()}catch(e){message('操作失敗：'+e.message)}finally{busy=false}}
async function start(){
 if(!validConfig||!window.supabase){show('setup');return}
 db=window.supabase.createClient(config.supabaseUrl,config.supabaseKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
 const {data:{session}}=await db.auth.getSession();if(!session){const {error}=await db.auth.signInAnonymously();if(error)throw Error('匿名登入失敗：'+error.message+'。請在 Supabase 啟用 Anonymous Sign-ins。')}
 const c=new URL(location.href).searchParams.get('room');if(c){invite=c;show('room');await refresh()}else show('home');
}
async function refresh(){if(!invite)return;try{const s=await rpc('get_poker_room',{p_invite:invite});render(s);message('')}catch(e){if(!lastSnapshot){show('home');$('joinCode').value=invite;message('請輸入暱稱並送出加入申請。')}else message('同步暫時失敗：'+e.message)}}
function render(s){lastSnapshot=JSON.stringify(s);show('room');const r=s.room, me=s.me, ms=s.members||[];
 $('roomTitle').textContent=r.name;$('roomDetails').textContent=`盲注 ${r.small_blind} / ${r.big_blind} · 起始籌碼 ${r.starting_stack} · 上限 ${r.max_players} 人`;
 $('myStatus').textContent=me.status==='approved'?(me.is_owner?'房主 · 已入座':me.is_deputy?'代理房主（預先指定） · 已入座':'已入座'):(me.status==='pending'?'等待房主核准':'申請未通過');
 $('shareUrl').value=urlFor(invite);const approved=ms.filter(x=>x.status==='approved').sort((a,b)=>a.seat-b.seat);
 $('seatCount').textContent=`${approved.length} / ${r.max_players}`;
 $('seats').innerHTML=approved.length?approved.map(m=>`<div class="member"><div><strong>${esc(m.seat)} 號｜${esc(m.nickname)}</strong><br><small>${m.is_owner?'房主':m.is_deputy?'代理房主':'玩家'}</small></div></div>`).join(''):'<p>等待玩家加入</p>';
 $('hostPanel').classList.toggle('hidden',!me.is_owner);
 if(me.is_owner){const pending=ms.filter(x=>x.status==='pending');$('pending').innerHTML=pending.length?pending.map(m=>`<div class="member"><strong>${esc(m.nickname)}</strong><div class="actions"><button data-review="${esc(m.id)}" data-approve="true">核准</button><button data-review="${esc(m.id)}" data-approve="false" class="secondary">拒絕</button></div></div>`).join(''):'<p>目前沒有待審核申請</p>';
 const others=approved.filter(x=>!x.is_owner);$('deputy').innerHTML=others.length?others.map(m=>`<div class="member"><span>${esc(m.nickname)} ${m.is_deputy?'✓':''}</span><button style="width:auto" data-deputy="${esc(m.id)}" ${m.is_deputy?'disabled':''}>指定代理</button></div>`).join(''):'<p>其他玩家核准後可指定</p>'}
}
$('create').onclick=()=>locked(async()=>{const p={p_name:$('roomName').value.trim(),p_invite:randomCode(),p_nickname:$('hostName').value.trim(),p_max:Number($('maxPlayers').value),p_sb:Number($('sb').value),p_bb:Number($('bb').value),p_stack:Number($('stack').value)};if(!p.p_nickname)throw Error('請填寫你的暱稱');await rpc('create_poker_room',p);invite=p.p_invite;history.replaceState({},'',urlFor(invite));await refresh()});
$('join').onclick=()=>locked(async()=>{const code=codeFrom($('joinCode').value),nick=$('guestName').value.trim();if(!/^[a-f0-9]{24}$/.test(code))throw Error('請輸入有效房間邀請網址或邀請碼');if(!nick)throw Error('請填寫暱稱');await rpc('request_poker_join',{p_invite:code,p_nickname:nick});invite=code;history.replaceState({},'',urlFor(invite));await refresh()});
$('pending').onclick=e=>{const b=e.target.closest('button[data-review]');if(!b)return;locked(async()=>{await rpc('review_poker_member',{p_invite:invite,p_member_id:b.dataset.review,p_approve:b.dataset.approve==='true'});await refresh()})};
$('deputy').onclick=e=>{const b=e.target.closest('button[data-deputy]');if(!b)return;locked(async()=>{await rpc('set_poker_deputy',{p_invite:invite,p_member_id:b.dataset.deputy});await refresh()})};
$('copyLink').onclick=()=>locked(async()=>{try{await navigator.clipboard.writeText(urlFor(invite));message('已複製邀請網址')}catch{ $('shareUrl').select();message('請長按上方網址選擇複製')}});
$('shareLink').onclick=()=>{if(navigator.share)navigator.share({title:'加入德州撲克房間',url:urlFor(invite)}).catch(()=>{});else $('copyLink').click()};
$('leaveView').onclick=()=>{invite='';lastSnapshot='';history.replaceState({},'',location.pathname);show('home');message('')};
window.addEventListener('focus',()=>{if(invite)refresh()});
refreshTimer=setInterval(()=>{if(invite&&!busy&&document.visibilityState==='visible')refresh()},2500);
start().catch(e=>{show('setup');message(e.message)});
