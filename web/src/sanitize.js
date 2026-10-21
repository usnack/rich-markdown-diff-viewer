import DOMPurify from 'dompurify';
const safeProperties = new Set(('color background-color font-size font-weight font-style font-family text-align text-decoration line-height letter-spacing border border-color border-width border-style border-radius padding padding-top padding-bottom padding-left padding-right margin margin-top margin-bottom margin-left margin-right display width max-width min-width height max-height vertical-align white-space list-style-type border-collapse border-spacing').split(' '));
function declaration(style) {
  for (const property of Array.from({length:style.length},(_,i)=>style.item(i))) {
    const value = style.getPropertyValue(property);
    if(!safeProperties.has(property) || /url\s*\(|expression|var\(|image-set|[<>@]/i.test(value) || /-\s*\d/.test(value)) style.removeProperty(property);
  }
  return style.cssText;
}
export function sanitize(html, doc = document) {
  const template=doc.createElement('template');template.innerHTML=html;
  let css='';
  for(const style of template.content.querySelectorAll('style')) {
    const source=style.textContent;
    if(!/@|url\s*\(|:host|::slotted|expression|image-set/i.test(source)) {
      try {const sheet=new CSSStyleSheet();sheet.replaceSync(source);for(const rule of sheet.cssRules) {if(rule.style && rule.selectorText) css+=rule.selectorText+'{'+declaration(rule.style)+'}';}}catch{}
    };style.remove();
  }
  const clean=DOMPurify.sanitize(template.innerHTML,{USE_PROFILES:{html:true},FORBID_TAGS:['script','iframe','object','embed','form','button','textarea','select','video','audio','source','link','meta','base','style'],FORBID_ATTR:['srcset','ping','formaction','autofocus'],ALLOW_DATA_ATTR:false,ADD_ATTR:['data-rmd-start','data-rmd-end']});
  template.innerHTML=clean;
  for(const el of template.content.querySelectorAll('*')) {
    if(el.hasAttribute('style')) {declaration(el.style);if(!el.style.cssText) el.removeAttribute('style');}
    if(el.tagName==='INPUT') {if(el.type!=='checkbox') {el.remove();continue;}el.disabled=true;}
    if(el.tagName==='A') {const href=el.getAttribute('href')||'';if(!/^(https?:\/\/|#)/i.test(href)) el.removeAttribute('href');el.removeAttribute('target');}
    if(el.tagName==='IMG') {el.dataset.originalSrc=el.getAttribute('src')||'';el.removeAttribute('src');el.removeAttribute('loading');}
  }
  return {html:template.innerHTML,css};
}
