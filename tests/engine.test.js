import test from 'node:test';
import assert from 'node:assert/strict';
import {compare,parse,textDiff} from '../web/src/engine.js';
test('Korean and grapheme clusters remain intact',()=>{
 const d=textDiff('안녕 👨‍👩‍👧‍👦 é','안녕 👨‍👩‍👧‍👦 é!');
 assert.ok(d.some(c=>c.added));assert.equal(d.flatMap(c=>c.removed?[]:c.value).join(''),'안녕 👨‍👩‍👧‍👦 é!');assert.ok(d.flatMap(c=>c.value).includes('👨‍👩‍👧‍👦'));
});
test('format-only and reference destination changes stay visible',()=>{
 for(const [a,b]of [['# 제목','## 제목'],['그냥 문장','**그냥** 문장'],['[링크][id]\n\n[id]: https://a.test','[링크][id]\n\n[id]: https://b.test']])assert.ok(compare(a,b).some(r=>r.status==='modify'));
});
test('table AST structure survives cell edit',()=>{
 const rows=compare('| 키 | 값 |\n|---|---|\n| x | 옛값 |','| 키 | 값 |\n|---|---|\n| x | 새값 |');assert.equal(rows[0].a.type,'table');assert.match(rows[0].b.html,/<td>새값<\/td>/);
});
test('lists, tasks, HTML, Mermaid, code retain structures',()=>{
 const text='# 제목\n\n- [x] 하나\n  - 중첩\n\n```mermaid\ngraph TD; A-->B\n```\n\n<details><summary>열기</summary>내용</details>';
 const blocks=parse(text);assert.equal(blocks.length,4);assert.ok(blocks[1].html.includes('checkbox'));assert.ok(blocks[2].mermaid);assert.ok(blocks[3].html.includes('<details>'));
});
test('inserted blocks do not shift identical anchors',()=>{
 const r=compare('# 동일\n\n본문\n\n마지막','# 동일\n\n새 문장\n\n본문\n\n마지막');assert.deepEqual(r.map(x=>x.status),['same','add','same','same']);
});
test('whitespace and unused reference-only changes are explicit',()=>{assert.ok(compare('내용\n','내용\n\n').some(r=>r.status==='source'));assert.ok(compare('문서\n\n[id]: a','문서\n\n[id]: b').some(r=>r.status==='source'));});
test('added/deleted docs and HTML fallback',()=>{assert.equal(compare('','신규')[0].status,'add');assert.equal(compare('삭제','')[0].status,'delete');assert.equal(compare('<div>옛</div>','<div>새</div>')[0].status,'modify');});
