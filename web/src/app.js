import {compare,textDiff} from './engine.js';
import {sanitize} from './sanitize.js';
import mermaid from 'mermaid';
import {createFileTree} from './tree.js';
import {createComments} from './comments-ui.js';
const $=id=>document.getElementById(id);
const send=(action,value)=>document.dispatchEvent(new CustomEvent('rmd-command',{detail:JSON.stringify({action,value})}));
let state={},rows=[],layout='unified',only=false,paused=false,active=-1,renderVersion=0,userScroll=0,ready=false,readingAnchor=null,sideStyles={before:'',after:''};
const viewport=$('viewport');
const fileTree=createFileTree($('files'),path=>send('file',path));
const commentUI=createComments({getState:()=>state,send});
viewport.addEventListener('scroll',()=>{readingAnchor=capture();},{passive:true});
viewport.addEventListener('wheel',()=>userScroll++,{passive:true});viewport.addEventListener('pointerdown',()=>userScroll++,{passive:true});viewport.addEventListener('touchstart',()=>userScroll++,{passive:true});viewport.addEventListener('keydown',()=>userScroll++);
mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'neutral',suppressErrorRendering:true,fontFamily:'-apple-system, sans-serif',flowchart:{htmlLabels:false},maxTextSize:50000,maxEdges:500});
const docCSS=`:host{display:block;contain:content;color:#26364a;font:14px/1.85 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif;overflow-wrap:anywhere}*{box-sizing:border-box}h1,h2,h3,h4,h5,h6{line-height:1.4;color:#233a57;margin:8px 0 14px;font-weight:650}h1{font-size:29px;border-bottom:1px solid #dbe2ec;padding-bottom:13px}h2{font-size:23px}h3{font-size:19px}p{margin:5px 0 12px}ul,ol{padding-left:25px;margin:6px 0}li{padding-left:2px}blockquote{border-left:3px solid #94abc4;margin:9px 0;padding:3px 17px;color:#66788d;background:#f5f8fc}a{color:#326caa;text-decoration:underline}table{border-collapse:collapse;display:block;max-width:100%;overflow:auto;margin:10px 0;font-size:13px}th,td{border:1px solid #ccd7e2;padding:8px 13px;min-width:65px}th{background:#edf2f8;text-align:left}pre{background:#edf2f7;padding:14px;border-radius:5px;overflow:auto;line-height:1.6;font-size:12px}code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;background:#e9eef5;border-radius:3px;padding:2px 4px}pre code{padding:0;background:none}img{display:block;max-width:100%;height:auto;margin:8px 0}details{border:1px solid #d5dfeb;border-radius:6px;padding:10px 14px;margin:8px 0}summary{cursor:pointer;font-weight:600}mark{border-radius:2px;padding:1px 0;color:inherit}.diff-del{background:#f9cbc7;text-decoration:line-through;text-decoration-color:#b45151}.diff-add{background:#bce8cc;text-decoration:underline;text-decoration-color:#388659;text-underline-offset:3px}.image-note{display:block;font-size:10px;color:#7c8796;line-height:1.5}.missing-image,.mermaid-error{background:#fff4e3;color:#9b682d;padding:10px;border:1px dashed #d6af75;font-size:12px;border-radius:4px}.diagram svg{max-width:100%;height:auto;display:block;margin:8px auto}.mermaid-error pre{white-space:pre-wrap;color:#7c5b32}input{accent-color:#538e71}`;
const element=(tag,cls,text)=>{const el=document.createElement(tag);if(cls)el.className=cls;if(text!==undefined)el.textContent=text;return el;};
function capture() {
  const top=viewport.getBoundingClientRect().top;
  const els=[...$('rows').children];let i=els.findIndex(el=>el.getBoundingClientRect().bottom>top+2);if(i<0)return null;
  return {candidates:els.slice(Math.max(0,i-2),i+5).map(el=>({id:el.id,offset:el.getBoundingClientRect().top-top})),top:viewport.scrollTop,epoch:userScroll};
}
function restore(anchor) {
  if(!anchor||anchor.epoch!==userScroll)return;
  for(const candidate of anchor.candidates.sort((a,b)=>Math.abs(a.offset)-Math.abs(b.offset))) {
    const el=document.getElementById(candidate.id);if(el){viewport.scrollTop+=el.getBoundingClientRect().top-viewport.getBoundingClientRect().top-candidate.offset;return;}
  };viewport.scrollTop=anchor.top;
}
function texts(root) {
  const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode:n=>n.parentElement?.closest('style,script,.image-note,.missing-image')?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT});let ns=[],n;while(n=walker.nextNode())ns.push(n);return ns;
}
function mark(root,other,side) {
  const ns=texts(root), original=ns.map(n=>n.data).join(''), alternative=texts(other).map(n=>n.data).join('');
  const changes=side==='before'?textDiff(original,alternative):textDiff(alternative,original);
  let offset=0,ranges=[];
  for(const chunk of changes) {
    if((side==='before'&&chunk.added)||(side==='after'&&chunk.removed))continue;
    const length=chunk.value.join('').length;
    if(side==='before'?chunk.removed:chunk.added)ranges.push([offset,offset+length]);offset+=length;
  }
  let start=0;
  for(const node of ns){const end=start+node.length;const parts=ranges.filter(([a,b])=>a<end&&b>start);if(parts.length){const fragment=document.createDocumentFragment();let p=0;for(const [a,b]of parts){const x=Math.max(0,a-start),y=Math.min(node.length,b-start);fragment.append(node.data.slice(p,x));const m=element('mark',side==='before'?'diff-del':'diff-add',node.data.slice(x,y));fragment.append(m);p=y;}fragment.append(node.data.slice(p));node.replaceWith(fragment);}start=end;}
  return original!==alternative;
}
function highlight(a,b) {
  // Stable table structures compare each cell independently.
  const ac=[...a.querySelectorAll('th,td')],bc=[...b.querySelectorAll('th,td')];
  if(ac.length && ac.length===bc.length && a.querySelectorAll('tr').length===b.querySelectorAll('tr').length) {
    const old=ac.map(x=>x.cloneNode(true)),next=bc.map(x=>x.cloneNode(true));ac.forEach((c,i)=>mark(c,next[i],'before'));bc.forEach((c,i)=>mark(c,old[i],'after'));
  } else {const old=a.cloneNode(true),next=b.cloneNode(true);mark(a,next,'before');mark(b,old,'after');}
}
function sourceDetails(row) {
  const detail=element('details','source');detail.append(element('summary','', '원문 변경 보기'));
  const pre=element('pre');for(const chunk of textDiff(row.a?.raw??row.sourceBefore??'',row.b?.raw??row.sourceAfter??'')){const text=chunk.value.join('');pre.append(chunk.added?element('ins','',text):chunk.removed?element('del','',text):document.createTextNode(text));}detail.append(pre);return detail;
}
async function diagram(block,root,version,anchor) {
  const box=element('div','diagram');root.append(box);const stage=element('div','mermaid-stage');document.body.append(stage);
  try {
    const id='diagram-'+version+'-'+Math.random().toString(36).slice(2);
    const {svg}=await mermaid.render(id,block.node.value,stage);
    if(version!==renderVersion)return;
    const current=capture();box.innerHTML=svg;restore(current);readingAnchor=capture();
  }catch(error){if(version!==renderVersion)return;const current=capture();box.className='mermaid-error';box.append(element('strong','', 'Mermaid 문법 오류'),element('p','',String(error.message||error).slice(0,300)),element('pre','',block.node.value));restore(current);readingAnchor=capture();}
  finally{stage.remove();}
}
function makeCell(block,side,status,version,anchor) {
  const safeRestore=()=>{if(version===renderVersion){restore(readingAnchor||anchor);readingAnchor=capture();}};
  const cell=element('div','cell '+(block?(status==='same'?'':side==='before'?'delete':'add'):'blank'));
  if(!block)return {cell};
  if(status!=='same')cell.append(element('div','change-label', (side==='before'?'− 변경 전':'＋ 변경 후')+' · L'+block.start));
  const host=element('div','document');cell.append(host);const root=host.attachShadow({mode:'open'});
  const style=element('style','',docCSS);root.append(style);const body=element('article');root.append(body);
  if(block.mermaid) diagram(block,body,version,anchor);
  else {
    const clean=sanitize(block.annotatedHtml||block.html);body.innerHTML=clean.html;
    if(sideStyles[side])root.append(element('style','',sideStyles[side]));
    for(const img of body.querySelectorAll('img')) {
      const src=img.dataset.originalSrc||'';const external=/^https?:\/\//i.test(src);
      let decoded=src;try{decoded=decodeURI(src);}catch{}
      const resolved=external?src:(state.snapshot?.assets?.[side]?.[src]??state.snapshot?.assets?.[side]?.[decoded]);
      const note=element('span','image-note',external?'외부 이미지 · 현재 URL 응답':(side==='before'?state.snapshot?.beforeLabel:state.snapshot?.afterLabel)+' 이미지');
      img.after(note);
      img.onerror=()=>{const missing=element('div','missing-image','이미지 누락 · '+src+(external?' (외부 응답 실패)':' · 비교 시점에서 찾을 수 없거나 접근이 차단됨'));img.replaceWith(missing);safeRestore();};
      img.onload=safeRestore;
      if(resolved)img.src=resolved;else img.onerror();
    }
  }
  root.addEventListener('click',e=>{const a=e.target.closest?.('a');if(!a)return;e.preventDefault();const href=a.getAttribute('href')||'';if(/^https?:\/\//i.test(href))send('external',href);});
  root.addEventListener('toggle',safeRestore,true);
  commentUI.attach(cell,root,block,side);
  return {cell,body};
}
function draw(preserve=true) {
  const anchor=preserve?capture():null;const version=++renderVersion;const fragment=document.createDocumentFragment();
  for(const r of rows) {
    if(only&&r.status==='same')continue;
    const row=element('section','row '+(layout==='split'?'split ':'')+(r.status!=='same'?'changed':''));row.id='block-'+r.id;row.dataset.status=r.status;
    if(r.status==='source') {row.append(element('div','cell','◇ 원문 변경 · 렌더링 결과는 동일합니다'),sourceDetails(r));fragment.append(row);continue;}
    if(r.status==='same'&&layout==='unified')row.append(makeCell(r.b,'after','same',version,anchor).cell);
    else {
      const a=makeCell(r.a,'before',r.status,version,anchor),b=makeCell(r.b,'after',r.status,version,anchor);
      if(r.status==='modify'&&a.body&&b.body&&!r.a.mermaid&&!r.b.mermaid) {
        const sameText=texts(a.body).map(n=>n.data).join('')===texts(b.body).map(n=>n.data).join('');
        highlight(a.body,b.body);
        if(sameText){a.cell.querySelector('.change-label').append(' · ◇ 서식·원문 변경');b.cell.querySelector('.change-label').append(' · ◇ 서식·원문 변경');}
      }
      if(layout==='split')row.append(a.cell,b.cell);else{if(r.a)row.append(a.cell);if(r.b)row.append(b.cell);}
      if(r.status!=='same') {const source=sourceDetails(r);if(layout==='split')source.style.gridColumn='1 / -1';row.append(source);}
    }
    fragment.append(row);
  }
  $('rows').replaceChildren(fragment);$('rows').style.display=state.snapshot?'block':'none';
  const changes=rows.filter(r=>r.status!=='same');$('status').textContent=state.snapshot?`${rows.length}개 블록 · ${changes.length}개 변경${only?' · 변경만 보기':''}`:'읽기 전용';
  active=-1;$('counter').textContent=`0 / ${changes.length}`;$('unified').classList.toggle('active',layout==='unified');$('split').classList.toggle('active',layout==='split');
  $('only').checked=only;if(anchor)restore(anchor);else viewport.scrollTop=0;readingAnchor=capture();ready=true;commentUI.refresh();
}
window.receive=payload=>{
  try{
    const preserve=state.repo===payload.repo&&state.selected===payload.selected&&state.mode===payload.mode;
    state=payload;layout=payload.layout||layout;only=payload.only??only;
    $('repository').textContent=payload.repo||'로컬 저장소';$('repository').title=payload.repo||'';$('mode').value=payload.mode||'total';$('file-count').textContent=payload.files.length;
    fileTree.render(payload.files,payload.selected,payload.repo);$('filename').textContent=payload.selected||'문서를 선택하세요';$('versions').textContent=payload.snapshot?payload.snapshot.beforeLabel+' → '+payload.snapshot.afterLabel:'';
    $('empty').style.display=payload.snapshot?'none':'block';$('empty-open').style.display=payload.repo?'none':'inline-block';
    if(!payload.snapshot){$('empty').querySelector('h1').textContent=payload.error?'문서를 읽을 수 없습니다':payload.missing?'선택한 파일의 변경이 없습니다':payload.repo?'변경된 마크다운이 없습니다':'문서의 변화를 한눈에';$('empty').querySelector('p').textContent=payload.error|| (payload.missing?'파일이 삭제·이동되었거나 이 비교 기준에 변경이 없습니다. 왼쪽에서 다른 문서를 선택하세요.':payload.repo?'문서를 저장하면 변경 내용이 자동으로 나타납니다.':'로컬 Git 저장소를 열어 마크다운 변경을 살펴보세요.');}
    rows=payload.snapshot?compare(payload.snapshot.before,payload.snapshot.after):[];
    sideStyles={before:'',after:''};
    for(const side of ['before','after']) {
      for(const r of rows) {const block=side==='before'?r.a:r.b;if(block?.html.includes('<style'))sideStyles[side]+=sanitize(block.html).css;}
    }
    for(const row of rows)if(row.status==='same' && row.b.html.includes('<img')) {
      const clean=sanitize(row.b.html);const t=document.createElement('template');t.innerHTML=clean.html;
      if([...t.content.querySelectorAll('img')].some(img=>{const src=img.dataset.originalSrc;return payload.snapshot.assets.before[src]!==payload.snapshot.assets.after[src];})) row.status='modify';
    }
    commentUI.update(payload);
    draw(preserve);$('updated').textContent='갱신 '+new Date().toLocaleTimeString('ko-KR');
  }catch(error){$('empty').style.display='block';$('empty').querySelector('h1').textContent='렌더링 오류';$('empty').querySelector('p').textContent=String(error);$('rows').replaceChildren();}
};
$('open').onclick=$('empty-open').onclick=()=>send('open');
$('mode').onchange=e=>send('mode',e.target.value);
for(const value of ['unified','split'])$(value).onclick=()=>{layout=value;send('layout',value);draw();};
$('only').onchange=e=>{only=e.target.checked;send('only',only);draw();};
$('pause').onclick=()=>{paused=!paused;$('pause').classList.toggle('paused',paused);$('pause').textContent=paused?'▶ 자동 갱신 재개':'Ⅱ 자동 갱신 중';send('pause',paused);};
function navigate(delta){userScroll++;const changed=[...document.querySelectorAll('.row.changed')];if(!changed.length)return;active=active<0?(delta>0?0:changed.length-1):(active+delta+changed.length)%changed.length;for(const el of changed)el.classList.remove('current');changed[active].classList.add('current');changed[active].scrollIntoView({block:'start'});$('counter').textContent=`${active+1} / ${changed.length}`;}
$('prev').onclick=()=>navigate(-1);$('next').onclick=()=>navigate(1);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
window.verifyApp=async()=>{
 const checks=[];const check=(name,pass,detail)=>checks.push({name,pass:!!pass,detail:detail??''});
 check('native snapshot loaded',!!state.snapshot,{repo:state.repo,selected:state.selected,files:state.files?.length});
 check('rich Markdown rendered',!!document.querySelector('.document')?.shadowRoot?.querySelector('h1'));
 const roots=()=>[...document.querySelectorAll('.document')].map(x=>x.shadowRoot);
 check('phrase highlights',roots().some(r=>r.querySelector('mark')));
 check('Mermaid rendered',roots().some(r=>r.querySelector('.diagram svg')));
 check('Mermaid error isolated',roots().some(r=>r.querySelector('.mermaid-error')));
 check('HTML details rendered',roots().some(r=>r.querySelector('details')));
 check('unsafe script removed',roots().every(r=>!r.querySelector('script,iframe,[onclick],[onerror]'))&&!window.pwned);
 check('document CSS isolated',getComputedStyle(document.querySelector('header')).position!=='fixed');
 check('historical images distinct',state.snapshot&&state.snapshot.assets.before['pixel.png']!==state.snapshot.assets.after['pixel.png']);
 check('historical images both displayed',roots().flatMap(r=>[...r.querySelectorAll('img')]).filter(img=>img.dataset.originalSrc==='pixel.png').length===2);
 check('document stylesheet reaches another block',roots().some(r=>[...r.querySelectorAll('h3')].some(h=>getComputedStyle(h).color==='rgb(70, 100, 132)')));
 check('native bridge isolated',!window.webkit?.messageHandlers?.native);
 $('split').click();await sleep(2000);
 const pairs=[...document.querySelectorAll('.row.split')].filter(r=>r.querySelectorAll(':scope > .cell').length===2);
 check('split grid equal row heights',pairs.length>0&&pairs.every(r=>{const c=r.querySelectorAll(':scope > .cell');return Math.abs(c[0].getBoundingClientRect().height-c[1].getBoundingClientRect().height)<1}));
 $('only').click();check('changes only',![...document.querySelectorAll('.row')].some(r=>r.dataset.status==='same'));$('only').click();
 $('next').click();check('change navigation',$('counter').textContent.startsWith('1 /'));
 const details=roots().flatMap(r=>[...r.querySelectorAll('details')])[0];if(details){details.open=true;check('HTML disclosure toggles',details.open);}
 const original=state.selected;
 for(const value of ['unstaged','staged','total']){ $('mode').value=value;$('mode').dispatchEvent(new Event('change'));await sleep(2500);check('comparison '+value,state.mode===value,{files:state.files.map(x=>x.path),selected:state.selected}); }
 if(state.selected!==original){send('file',original);await sleep(2000);}
 $('pause').click();check('pause button',paused);$('pause').click();await sleep(1500);check('resume button',!paused);
 $('split').click();await sleep(2500);
 await verifyReviewFeatures(check);
 return {checks,failures:checks.filter(c=>!c.pass),state:{repo:state.repo,selected:state.selected,mode:state.mode,layout},timestamp:new Date().toISOString()};
};
send('ready');

window.workflowStart=async()=>{
 $('unified').click();if(only)$('only').click();await sleep(2000);
 const target=[...document.querySelectorAll('.row')].find(r=>[...r.querySelectorAll('.document')].some(d=>d.shadowRoot.textContent.includes('검토 항목 15')));
 userScroll++;target?.scrollIntoView({block:'start'});window.workflowAnchor=capture();window.workflowBefore=state.snapshot?.after;$('pause').click();
 return {targetFound:!!target,scrollTop:viewport.scrollTop,selected:state.selected};
};
window.workflowPaused=()=>({paused,unchanged:state.snapshot?.after===window.workflowBefore});
window.workflowResume=()=>{$('pause').click();return true;};
window.workflowAfter=()=>{
 const anchor=window.workflowAnchor;const candidate=anchor?.candidates.find(c=>document.getElementById(c.id));
 const offset=candidate?document.getElementById(candidate.id).getBoundingClientRect().top-viewport.getBoundingClientRect().top:null;
 return {updated:state.snapshot?.after?.includes('자동 갱신 검증용 추가 문단'),scrollTop:viewport.scrollTop,offsetError:candidate?Math.abs(offset-candidate.offset):null,pass:!!candidate&&Math.abs(offset-candidate.offset)<3&&state.snapshot?.after?.includes('자동 갱신 검증용 추가 문단'),anchorRetained:!!candidate};
};
window.workflowRapid=async()=>{
 const files=state.files;for(const f of files)send('file',f.path);await sleep(2500);
 const expected=files.at(-1)?.path;const result={expected,selected:state.selected,pass:state.selected===expected};
 send('file','01-제품 설계.md');await sleep(1800);return result;
};
window.workflowIndexStart=()=>{$('mode').value='staged';$('mode').dispatchEvent(new Event('change'));return true;};
window.workflowIndexCheck=()=>({mode:state.mode,stagedUpdated:state.snapshot?.after?.includes('자동 갱신 검증용 추가 문단')});
window.workflowEnd=()=>{$('mode').value='total';$('mode').dispatchEvent(new Event('change'));$('split').click();if($('comment-panel').hidden)$('comments-toggle').click();$('comment-compose').open=false;viewport.scrollTop=0;return {selected:state.selected,layout};};

async function verifyReviewFeatures(check) {
 const waitFor=async(predicate)=>{for(let i=0;i<60;i++){if(predicate())return true;await sleep(100);}return false;};
 const folder=document.querySelector('.tree-folder');
 check('nested repository tree rendered',!!folder&&!!document.querySelector('.tree-group .tree-folder'));
 if(folder){const path=folder.dataset.path;folder.open=false;folder.dispatchEvent(new Event('toggle'));fileTree.render(state.files,state.selected,state.repo);check('tree collapse retained after refresh',!document.querySelector(`.tree-folder[data-path="${path}"]`).open);const next=document.querySelector(`.tree-folder[data-path="${path}"]`);next.open=true;next.dispatchEvent(new Event('toggle'));}
 const inherited=state.comments||[];
 if(inherited.length)check('comments restored from previous app launch',inherited.filter(c=>['asdf','second comment'].includes(c.body)).length===2);
 for(const comment of [...inherited]){send('commentDelete',{context:state.commentContext,id:comment.id});await waitFor(()=>!state.comments.some(c=>c.id===comment.id));}
 const sourceHost=[...document.querySelectorAll('.document')].find(h=>h.shadowRoot.querySelector('span[data-rmd-start="7"]')&&h.parentElement.querySelector('.block-comment-button')?.dataset.version==='WORK');
 let selectedRangeWorks=false,selectionDetail={host:!!sourceHost};
 if(sourceHost){const root=sourceHost.shadowRoot,a=root.querySelector('span[data-rmd-start="7"]'),b=root.querySelector('span[data-rmd-start="8"]');if(a?.firstChild&&b?.firstChild){const selected=document.createRange();selected.setStart(a.firstChild,0);selected.setEnd(b.firstChild,b.firstChild.textContent.length);const s=window.getSelection();s.removeAllRanges();s.setBaseAndExtent(a.firstChild,0,b.firstChild,b.firstChild.textContent.length);selectionDetail={host:true,rootGetSelection:!!root.getSelection,composed:!!s.getComposedRanges,anchor:s.anchorNode?.parentElement?.outerHTML?.slice(0,350),focus:s.focusNode?.parentElement?.outerHTML?.slice(0,350),collapsed:s.isCollapsed,text:s.toString()};try{selectionDetail.ranges=s.getComposedRanges?.({shadowRoots:[root]}).map(r=>({start:r.startContainer?.parentElement?.outerHTML?.slice(0,350),end:r.endContainer?.parentElement?.outerHTML?.slice(0,350)}));}catch(e){selectionDetail.rangeError=String(e)}root.dispatchEvent(new MouseEvent('mouseup'));const button=sourceHost.parentElement.querySelector('.block-comment-button');selectionDetail.buttonLabel=button.textContent;button.click();selectionDetail.start=$('comment-start').value;selectionDetail.end=$('comment-end').value;selectedRangeWorks=$('comment-start').value==='7'&&$('comment-end').value==='8';s.removeAllRanges();}}
 check('rendered text selection maps to Markdown lines',selectedRangeWorks,selectionDetail);
 const anchorButton=[...document.querySelectorAll('.block-comment-button')].find(b=>b.dataset.start==='7'&&b.dataset.version==='WORK');anchorButton?.click();$('comment-start').value=7;$('comment-end').value=10;$('comment-end').dispatchEvent(new Event('change'));$('comment-body').value='asdf';$('comment-body').dispatchEvent(new Event('input'));$('comment-submit').click();
 check('comment persisted through native bridge',await waitFor(()=>state.comments?.some(c=>c.body==='asdf')));
 const first=state.comments?.find(c=>c.body==='asdf');
 check('exact source line range and excerpt',first?.startLine===7&&first?.endLine===10&&first?.excerpt===state.snapshot.after.split('\n').slice(6,10).join('\n'));
 const another=[...document.querySelectorAll('.comment-card button')].find(b=>b.textContent==='같은 범위에 추가');another?.click();$('comment-body').value='second comment';$('comment-body').dispatchEvent(new Event('input'));$('comment-submit').click();
 check('multiple comments on identical lines',await waitFor(()=>state.comments?.length===2)&&state.comments.every(c=>c.startLine===7&&c.endLine===10));
 const copy=[...document.querySelectorAll('.comment-card button')].find(b=>b.textContent==='복사');copy?.click();
 check('individual copy acknowledged',await waitFor(()=>$('comments-message').textContent==='코멘트를 복사했습니다.'));
 $('comments-copy-all').click();check('copy all acknowledged',await waitFor(()=>$('comments-message').textContent==='2개 코멘트를 복사했습니다.'));
 const original=state.selected;const other=state.files.find(f=>f.path!==original);if(other){send('file',other.path);await waitFor(()=>state.selected===other.path);check('comments scoped to current document',state.comments.length===0);send('file',original);await waitFor(()=>state.selected===original);check('comments restored on file return',state.comments.length===2);}
 check('comment cards use raw text',document.querySelectorAll('.comment-card .comment-text').length===2);
 $('comments-close').click();
}

window.inspectReviewSelection=async()=>{const checks=[];await verifyReviewFeatures((name,pass,detail)=>checks.push({name,pass:!!pass,detail:detail??''}));return {checks,failures:checks.filter(c=>!c.pass)};};
