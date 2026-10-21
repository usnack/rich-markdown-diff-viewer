export function buildFileTree(files) {
  const root={name:'',path:'',directories:new Map(),files:[]};
  for(const file of files){const parts=file.path.split('/');let node=root;for(const name of parts.slice(0,-1)){const path=node.path?node.path+'/'+name:name;if(!node.directories.has(name))node.directories.set(name,{name,path,directories:new Map(),files:[]});node=node.directories.get(name);}node.files.push(file);}
  return root;
}
const sorted=entries=>[...entries].sort((a,b)=>a[0].localeCompare(b[0],'ko',{numeric:true}));
export function createFileTree(container,onSelect) {
  let repo='',selected='',closed=new Set();
  const make=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e;};
  const count=node=>node.files.length+[...node.directories.values()].reduce((n,d)=>n+count(d),0);
  function render(files,current,repository) {
    const changed=repo!==repository||selected!==current;
    if(repo!==repository){repo=repository;try{closed=new Set(JSON.parse(localStorage.getItem('rmd-tree:'+repo)||'[]'));}catch{closed=new Set();}}
    selected=current;const tree=buildFileTree(files);const fragment=document.createDocumentFragment();container.setAttribute('role','tree');
    function fill(node,parent,depth){
      for(const [,dir]of sorted(node.directories)){
        const details=make('details','tree-folder');details.dataset.path=dir.path;details.open=changed&&current.startsWith(dir.path+'/')?true:!closed.has(dir.path);
        const summary=make('summary','folder-row');summary.title=dir.path;summary.style.setProperty('--depth',depth);summary.setAttribute('role','treeitem');summary.setAttribute('aria-expanded',String(details.open));
        summary.append(make('span','folder-chevron','›'),make('span','folder-icon','▱'),make('span','folder-name',dir.name),make('span','folder-count',String(count(dir))));
        const group=make('div','tree-group');group.setAttribute('role','group');fill(dir,group,depth+1);details.append(summary,group);
        details.addEventListener('toggle',()=>{summary.setAttribute('aria-expanded',String(details.open));if(details.open)closed.delete(dir.path);else closed.add(dir.path);try{localStorage.setItem('rmd-tree:'+repo,JSON.stringify([...closed]));}catch{}});parent.append(details);
      }
      for(const file of [...node.files].sort((a,b)=>a.path.localeCompare(b.path,'ko',{numeric:true}))){
        const button=make('button','file tree-file'+(file.path===current?' active':''));button.style.setProperty('--depth',depth);button.dataset.path=file.path;button.setAttribute('role','treeitem');button.setAttribute('aria-selected',String(file.path===current));
        const code=file.status==='?'?'N':file.status[0];const badge=make('span','badge '+(file.status==='?'?'unknown':code),code);
        const name=make('span','path',file.path.split('/').pop());if(file.staged&&file.unstaged)name.append(make('small','partial-stage','부분 스테이징'));
        if(file.status.startsWith('R'))name.append(make('small','rename-from','← '+file.oldPath));
        button.title=(file.status.startsWith('R')?file.oldPath+' → ':'')+file.path;button.append(badge,name);button.onclick=()=>onSelect(file.path);parent.append(button);
      }
    }
    fill(tree,fragment,0);container.replaceChildren(fragment);
    if(!files.length)container.append(make('p','tree-empty','변경된 Markdown 파일이 없습니다.'));
  }
  return {render};
}
