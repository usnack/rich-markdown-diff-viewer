import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
const dom=new JSDOM('');global.window=dom.window;global.document=dom.window.document;global.CSSStyleSheet=dom.window.CSSStyleSheet;
const {sanitize}=await import('../web/src/sanitize.js');
test('script, iframe, event, dangerous URLs, form attacks stripped',()=>{
 const {html}=sanitize('<script>window.pwned=1</script><iframe src="https://evil.test"></iframe><img src="../../secret.png" onerror="alert(1)"><a href="javascript:alert(1)">bad</a><form><input type="text"><button>run</button></form>');
 assert.ok(!/<script|<iframe|onerror|javascript:|<form|<button|type="text"/.test(html));assert.ok(!/src="/.test(html.replace('data-original-src="../../secret.png"','')));
});
test('safe disclosure, table, style and checkbox retained, network CSS stripped',()=>{
 const {html}=sanitize('<details open><summary>열기</summary><table><tr><td style="color:red;position:fixed;background-image:url(https://evil.test/x)">표</td></tr></table><input type="checkbox" checked></details>');
 assert.match(html,/<details open/);assert.match(html,/color: red/);assert.ok(!/fixed|url\(/.test(html));assert.match(html,/disabled/);
});
