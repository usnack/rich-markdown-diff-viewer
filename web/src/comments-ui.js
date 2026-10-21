export const sourceLines=source=>source.replace(/\r\n?/g,'\n').split('\n');
export function normalizeRange(start,end,count) {const a=Math.min(count,Math.max(1,Math.trunc(Number(start))||1)),b=Math.min(count,Math.max(1,Math.trunc(Number(end))||a));return {start:Math.min(a,b),end:Math.max(a,b)};}
export function excerptAt(source,start,end){return sourceLines(source).slice(start-1,end).join('\n');}
export function selectedSourceRange(root,selection) {
  if(!selection)return null;
  let start=selection.anchorNode,end=selection.focusNode,collapsed=selection.isCollapsed,endOffset=selection.focusOffset;
  if(selection.getComposedRanges){try{const ranges=selection.getComposedRanges({shadowRoots:[root]});const r=ranges.find(r=>root.contains(r.startContainer)&&root.contains(r.endContainer));if(r){start=r.startContainer;end=r.endContainer;endOffset=r.endOffset;collapsed=start===end&&r.startOffset===r.endOffset;}}catch{}}
  const lineAt=node=>{const parent=node?.nodeType===1?node:node?.parentElement;const marker=parent?.closest?.('[data-rmd-start]');return marker&&root.contains(marker)?{start:Number(marker.dataset.rmdStart),end:Number(marker.dataset.rmdEnd)}:null;};
  const a=lineAt(start),b=lineAt(end);if(collapsed||!a||!b)return null;
  const lo=Math.min(a.start,b.start),hi=Math.max(a.end,b.end);
  return {start:lo,end:endOffset===0&&b.start>a.start?Math.max(lo,b.start-1):hi};
}
export function createComments({getState,send}) {
  const $=id=>document.getElementById(id);
  const el=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e;};
  let payload={},comments=[],scope='',context='',draftContext='',side='after',range={start:1,end:1},pivot=1,editing=null,busy=false,pending=null;
  const drafts=new Map();
  const version=which=>which==='before'?payload.snapshot?.beforeLabel:payload.snapshot?.afterLabel;
  const source=()=>side==='before'?payload.snapshot?.before??'':payload.snapshot?.after??'';
  const notify=(text,error=false)=>{$('comments-message').textContent=text;$('comments-message').classList.toggle('error',error);};
  function show(open=true){$('comment-panel').hidden=!open;$('comments-toggle').setAttribute('aria-expanded',String(open));document.querySelector('.review-layout').classList.toggle('with-comments',open);}
  function enabled(){const valid=!!payload.snapshot&&!payload.commentsError;const editable=!!editing||valid;const nonempty=$('comment-body').value.trim().length>0;const within=new TextEncoder().encode($('comment-body').value).length<=40000;$('comment-submit').disabled=busy||!editable||!nonempty||!within||draftContext!==context;$('comment-side').disabled=!valid||!!editing;for(const id of ['comment-start','comment-end'])$(id).disabled=!valid||!!editing;$('comments-copy-all').disabled=busy||comments.length===0||!context;}
  function updateRange(start,end,confirm=true){range=normalizeRange(start,end,sourceLines(source()).length);$('comment-start').value=range.start;$('comment-end').value=range.end;if(confirm)draftContext=context;
    for(const line of $('comment-source').children){const n=Number(line.dataset.line);line.classList.toggle('selected',n>=range.start&&n<=range.end);line.setAttribute('aria-pressed',String(n>=range.start&&n<=range.end));}
    $('comment-excerpt').textContent=editing?editing.excerpt:excerptAt(source(),range.start,range.end);enabled();
  }
  function renderSource(){const lines=sourceLines(source());const fragment=document.createDocumentFragment();lines.forEach((text,i)=>{const button=el('button','source-line');button.type='button';button.dataset.line=i+1;button.setAttribute('aria-label',`라인 ${i+1}: ${text}`);button.append(el('span','source-line-number',String(i+1)),el('span','source-line-text',text||' '));button.onclick=e=>{if(editing)return;if(!e.shiftKey)pivot=i+1;updateRange(e.shiftKey?pivot:i+1,i+1);notify('');};fragment.append(button);});$('comment-source').replaceChildren(fragment);$('comment-start').max=lines.length;$('comment-end').max=lines.length;
    $('comment-side').options[0].textContent='변경 후 · '+(version('after')||'—');$('comment-side').options[1].textContent='변경 전 · '+(version('before')||'—');$('comment-side').value=side;updateRange(range.start,range.end,false);
  }
  function command(action,extra={}){if(busy)return;busy=true;pending={action,context};send(action,{context,...extra});enabled();}
  function resetEdit(){editing=null;$('comment-cancel-edit').hidden=true;$('comment-submit').textContent='코멘트 추가';draftContext=context;enabled();}
  function renderList(){const fragment=document.createDocumentFragment();
    for(const comment of comments){
      const card=el('article','comment-card');card.dataset.id=comment.id;const lineLabel=`Lines ${comment.startLine===comment.endLine?comment.startLine:comment.startLine+'–'+comment.endLine}`;
      const header=el('div','comment-card-heading');header.append(el('strong','',lineLabel),el('span','comment-version',comment.version+' · '+(comment.side==='before'?'변경 전':'변경 후')));card.append(header);
      let matchingSide=version('after')===comment.version?'after':version('before')===comment.version?'before':null;
      const currentSource=matchingSide==='after'?payload.snapshot?.after:matchingSide==='before'?payload.snapshot?.before:null;
      const stale=currentSource!==null&&currentSource!==undefined&&excerptAt(currentSource,comment.startLine,comment.endLine)!==comment.excerpt;
      if(stale)card.append(el('p','comment-stale','원문 위치가 달라졌습니다 · 작성 당시 인용 유지'));
      else if(!matchingSide)card.append(el('p','comment-stale','이 비교에 없는 시점 · 작성 당시 인용 유지'));
      const quote=el('details','comment-quote');quote.append(el('summary','',comment.file),el('pre','',comment.excerpt));card.append(quote,el('p','comment-text',comment.body));
      const actions=el('div','comment-card-actions');
      const copy=el('button','', '복사');copy.onclick=()=>command('commentCopy',{id:comment.id});
      const edit=el('button','','수정');edit.onclick=()=>{show();$('comment-compose').open=true;editing=comment;side=matchingSide||'after';range={start:comment.startLine,end:comment.endLine};draftContext=context;$('comment-body').value=comment.body;$('comment-cancel-edit').hidden=false;$('comment-submit').textContent='수정 저장';renderSource();$('comment-excerpt').textContent=comment.excerpt;$('comment-body').focus();notify('코멘트 내용만 수정합니다.');};
      const remove=el('button','comment-delete','삭제');remove.onclick=()=>command('commentDelete',{id:comment.id});const another=el('button','','같은 범위에 추가');another.disabled=!matchingSide||stale;another.onclick=()=>open(matchingSide,comment.startLine,comment.endLine);actions.append(another,copy,edit,remove);card.append(actions);fragment.append(card);
    }
    if(!comments.length)fragment.append(el('p','comments-empty','아직 코멘트가 없습니다. 본문의 + 코멘트 버튼이나 원문 라인 선택으로 추가하세요.'));
    $('comment-list').replaceChildren(fragment);$('comment-count').textContent=comments.length;$('panel-comment-count').textContent=comments.length;enabled();
    for(const button of document.querySelectorAll('.block-comment-button')){const v=button.dataset.version;const count=comments.filter(c=>c.version===v&&c.startLine<=Number(button.dataset.end)&&c.endLine>=Number(button.dataset.start)).length;button.dataset.count=String(count);if(!button.dataset.selection)button.textContent=(count?'코멘트 '+count:'＋ 코멘트')+' · L'+button.dataset.start+(button.dataset.end===button.dataset.start?'':'–'+button.dataset.end);}
  }
  function open(which,start,end){show();$('comment-compose').open=true;resetEdit();side=which;range=normalizeRange(start,end,sourceLines(source()).length);pivot=range.start;draftContext=context;renderSource();const target=$('comment-source').querySelector(`[data-line="${range.start}"]`);if(target)$('comment-source').scrollTop=target.offsetTop-$('comment-source').offsetTop-35;$('comment-body').focus();notify('');}
  function update(next){
    const nextScope=(next.repo||'')+'\0'+(next.selected||'');const changed=scope!==nextScope,changedSource=context!==(next.commentContext||'');
    if(changed&&scope)drafts.set(scope,{body:$('comment-body').value,side,range,context:draftContext});
    payload=next;comments=next.comments||[];context=next.commentContext||'';
    if(changed){scope=nextScope;const draft=drafts.get(scope);side=draft?.side||'after';range=draft?.range||{start:1,end:1};$('comment-body').value=draft?.body||'';resetEdit();draftContext=draft?.body?draft.context:context;busy=false;pending=null;renderSource();notify('');$('comment-compose').open=comments.length===0;}
    else if(changedSource){busy=false;pending=null;renderSource();if($('comment-body').value.trim()&&!editing){draftContext='';notify('문서가 바뀌었습니다. 원문 라인을 다시 선택하세요.',true);}else draftContext=context;}
    if(payload.commentsError)notify(payload.commentsError,true);
    else if(!payload.snapshot&&comments.length)notify('문서 변경이 없어도 저장한 코멘트는 복사할 수 있습니다.');
    if(draftContext!==context&&$('comment-body').value.trim()&&!editing)notify('문서가 바뀌었습니다. 원문 라인을 다시 선택하세요.',true);
    renderList();
  }
  function attach(cell,root,block,which){
    const row=el('div','block-comment-actions');const button=el('button','block-comment-button','＋ 코멘트 · L'+block.start+(block.end===block.start?'':'–'+block.end));button.dataset.start=block.start;button.dataset.end=block.end;button.dataset.version=version(which)||'';
    let selectedRange=null;
    root.addEventListener('mouseup',()=>{
      selectedRange=selectedSourceRange(root,root.getSelection?.()||window.getSelection());
      if(selectedRange){button.dataset.selection='true';button.textContent=`선택한 L${selectedRange.start}–${selectedRange.end}에 코멘트`;}
      else{delete button.dataset.selection;renderList();}
    });
    button.onclick=()=>{const r=selectedRange||{start:block.start,end:block.end};open(which,r.start,r.end);};row.append(button);cell.append(row);
  }
  $('comments-toggle').onclick=()=>{show($('comment-panel').hidden);if(!$('comment-panel').hidden){renderSource();renderList();}};$('comments-close').onclick=()=>show(false);
  $('comment-side').onchange=e=>{side=e.target.value;range={start:1,end:1};draftContext=context;renderSource();notify('');};
  for(const id of ['comment-start','comment-end'])$(id).onchange=()=>{updateRange($('comment-start').value,$('comment-end').value);notify('');};
  $('comment-body').oninput=enabled;
  $('comment-body').onkeydown=e=>{if(e.key==='Enter'&&(e.metaKey||e.ctrlKey)){e.preventDefault();$('comment-submit').click();}};
  $('comment-submit').onclick=()=>{if($('comment-submit').disabled)return;command(editing?'commentEdit':'commentAdd',editing?{id:editing.id,body:$('comment-body').value}:{side,startLine:range.start,endLine:range.end,body:$('comment-body').value});};
  $('comment-cancel-edit').onclick=()=>{$('comment-compose').open=false;resetEdit();$('comment-body').value='';renderSource();enabled();notify('');};
  $('comments-copy-all').onclick=()=>command('commentsCopy');
  window.receiveComments=data=>{if(data.context!==context)return;comments=data.comments||[];payload.comments=comments;payload.commentsError=data.commentsError;renderList();};
  window.receiveCommentResult=result=>{if(result.context!==context)return;busy=false;if(!result.ok){notify(result.error||'처리하지 못했습니다.',true);enabled();return;}
    if(result.action==='commentAdd'||result.action==='commentEdit'){$('comment-body').value='';resetEdit();$('comment-compose').open=false;notify(result.action==='commentAdd'?'코멘트를 추가했습니다.':'수정했습니다.');}
    else if(result.action==='commentDelete'){if(editing?.id===result.id){$('comment-body').value='';resetEdit();}notify('코멘트를 삭제했습니다.');}
    else notify(result.action==='commentsCopy'?`${result.count}개 코멘트를 복사했습니다.`:'코멘트를 복사했습니다.');pending=null;enabled();};
  return {update,attach,open,refresh:renderList};
}
