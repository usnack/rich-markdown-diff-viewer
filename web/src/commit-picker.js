export function createCommitPicker({send}) {
  const $=id=>document.getElementById(id);
  let repo='',base='',signature='',pending=null,counter=0;
  const enabled=()=>{const busy=!!pending||!repo;$('commit-history').disabled=busy||$('commit-history').options.length<2;$('commit-input').disabled=busy;$('commit-apply').disabled=busy||!$('commit-input').value.trim();};
  function submit(revision){if(!repo||pending||!revision.trim())return;pending=String(++counter);$('commit-message').textContent='커밋을 확인하고 있습니다…';$('commit-message').classList.remove('error');send('commit',{revision:revision.trim(),request:pending});enabled();}
  function update(payload){
    const changed=repo!==(payload.repo||'');repo=payload.repo||'';
    if(changed){pending=null;$('commit-input').value='';$('commit-message').textContent='';}
    if(payload.mode!=='commit')pending=null;
    $('commit-picker').hidden=payload.mode!=='commit';
    const commits=payload.commits||[];base=payload.baseCommit||'';
    const next=JSON.stringify([repo,commits,base]);
    if(next!==signature){signature=next;const fragment=document.createDocumentFragment();const option=document.createElement('option');option.value='';option.textContent=commits.length?'최근 커밋에서 선택…':'목록에 표시할 커밋이 없습니다';fragment.append(option);
      for(const commit of commits){const item=document.createElement('option');item.value=commit.id;item.textContent=`${commit.shortID} · ${commit.date} · ${commit.subject}`;item.title=commit.id+'\n'+commit.subject;fragment.append(item);}
      if(base&&!commits.some(c=>c.id===base)){const item=document.createElement('option');item.value=base;item.textContent=base.slice(0,12)+' · 선택한 커밋 (목록 외)';fragment.append(item);}
      $('commit-history').replaceChildren(fragment);$('commit-history').value=base;
    }
    $('commit-base').textContent=base?'기준 '+base.slice(0,12)+' → 현재':'비교할 커밋을 선택하세요';$('commit-base').title=base;
    if(payload.historyError){$('commit-message').textContent=payload.historyError;$('commit-message').classList.add('error');}
    enabled();
  }
  $('commit-history').onchange=e=>submit(e.target.value);
  $('commit-input').oninput=enabled;
  $('commit-input').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();submit(e.target.value);}};
  $('commit-apply').onclick=()=>submit($('commit-input').value);
  window.receiveCommitResult=result=>{
    if(result.request!==pending||result.repo!==repo)return;pending=null;
    if(result.ok){$('commit-input').value='';$('commit-message').textContent='';$('commit-message').classList.remove('error');}
    else{$('commit-history').value=base;$('commit-message').textContent=result.error||'커밋을 읽지 못했습니다.';$('commit-message').classList.add('error');}
    enabled();
  };
  return {update};
}
