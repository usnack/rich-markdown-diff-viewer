import { unified } from 'unified';
import remarkParse from 'remark-parse';
import remarkGfm from 'remark-gfm';
import { toHast } from 'mdast-util-to-hast';
import { toHtml } from 'hast-util-to-html';
import { diffArrays } from 'diff';
const parser = unified().use(remarkParse).use(remarkGfm);
export function parse(source) {
  const tree = parser.parse(source);
  return tree.children.filter(n => n.type !== 'definition').map(node => {
    const raw = source.slice(node.position.start.offset, node.position.end.offset);
    const hast = toHast({type:'root', children:[node, ...tree.children.filter(n => n.type === 'definition')]}, {allowDangerousHtml:true});
    const html = toHtml(hast, {allowDangerousHtml:true});
    function annotate(parent) {
      if(!parent.children)return;
      parent.children=parent.children.flatMap(child=>{
        if(child.type==='text'&&child.position){
          const values=child.value.split('\n');
          return values.flatMap((value,i)=>[...(i?[{type:'text',value:'\n'}]:[]),{type:'element',tagName:'span',properties:{'data-rmd-start':child.position.start.line+i,'data-rmd-end':child.position.start.line+i},children:[{type:'text',value}]}]);
        }
        if(child.type==='element'&&child.position){child.properties=child.properties||{};child.properties['data-rmd-start']=child.position.start.line;child.properties['data-rmd-end']=child.position.end.line;}
        annotate(child);return [child];
      });
    }
    annotate(hast);
    const annotatedHtml=toHtml(hast,{allowDangerousHtml:true});
    return { node, raw, html, annotatedHtml, end:node.position.end.line, type: node.type, start:node.position.start.line, key:raw+'\0'+html, mermaid:node.type==='code' && node.lang==='mermaid' };
  });
}
const graphemes = text => Array.from(new Intl.Segmenter('ko', {granularity:'grapheme'}).segment(text), x => x.segment);
export function textDiff(a,b) {
  if(a===b)return [{value:[a]}];
  if(a.length+b.length>50000)return [{removed:true,value:[a]},{added:true,value:[b]}];
  return diffArrays(graphemes(a),graphemes(b),{timeout:200}) || [{removed:true,value:[a]},{added:true,value:[b]}];
}
function plain(n) { return n.value ?? n.alt ?? (n.children || []).map(plain).join(' '); }
function score(a,b) {
  if(a.type!==b.type && !(['heading','paragraph'].includes(a.type)&&['heading','paragraph'].includes(b.type))) return 0;
  const x = new Set(graphemes(plain(a.node))), y = new Set(graphemes(plain(b.node)));
  const intersection = [...x].filter(v=>y.has(v)).length;
  return .25 + .75 * (intersection / Math.max(1, new Set([...x,...y]).size));
}
function pair(aa,bb) {
  // Bounded dynamic alignment between exact anchors; preserve order and avoid quadratic work on huge edits.
  if(aa.length*bb.length>90000) return [...aa.map(a=>({a,status:'delete'})),...bb.map(b=>({b,status:'add'}))];
  const dp = Array.from({length:aa.length+1},()=>new Float64Array(bb.length+1));
  for(let i=aa.length-1;i>=0;i--) for(let j=bb.length-1;j>=0;j--) dp[i][j]=Math.max(dp[i+1][j],dp[i][j+1], score(aa[i],bb[j])+dp[i+1][j+1]);
  let i=0,j=0,rows=[];
  while(i<aa.length||j<bb.length) {
    const s=i<aa.length&&j<bb.length?score(aa[i],bb[j]):0;
    if(s>.24 && Math.abs(dp[i][j]-(s+dp[i+1][j+1]))<.0001) rows.push({a:aa[i++],b:bb[j++],status:'modify'});
    else if(i<aa.length&&(j===bb.length||dp[i+1][j]>=dp[i][j+1])) rows.push({a:aa[i++],status:'delete'});
    else rows.push({b:bb[j++],status:'add'});
  }
  return rows;
}
export function compare(before,after) {
  const aa=parse(before),bb=parse(after); const parts=diffArrays(aa,bb,{comparator:(a,b)=>a.key===b.key});
  let rows=[],removed=[],added=[],ai=0,bi=0;
  const flush=()=> {rows.push(...pair(removed,added));removed=[];added=[];};
  for(const p of parts) {
    if(p.removed) {removed.push(...p.value);ai+=p.value.length;}
    else if(p.added) {added.push(...p.value);bi+=p.value.length;}
    else {flush();for(let k=0;k<p.value.length;k++)rows.push({a:aa[ai+k],b:bb[bi+k],status:'same'});ai+=p.value.length;bi+=p.value.length;}
  }; flush();
  if(before!==after && rows.every(r=>r.status==='same')) rows.push({status:'source',sourceBefore:before,sourceAfter:after});
  const ids=new Map();
  return rows.map(r=>{const base=(r.b||r.a)?.html || 'source';let h=2166136261;for(const c of base) h=Math.imul(h^c.charCodeAt(0),16777619);const key=(h>>>0).toString(36);const count=ids.get(key)||0;ids.set(key,count+1);return {...r,id:key+'-'+count};});
}
