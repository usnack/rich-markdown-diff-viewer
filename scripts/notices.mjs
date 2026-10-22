import fs from 'node:fs';import path from 'node:path';
const lock=JSON.parse(fs.readFileSync('package-lock.json','utf8'));
let text='# Third-party notices\n\nRuntime and build dependencies are pinned in package-lock.json. This file includes installed license notices.\n';
for(const [dir,pkg]of Object.entries(lock.packages)){
 if(!dir||!fs.existsSync(dir))continue;
 const names=fs.readdirSync(dir).filter(n=>/^(licen[cs]e|copying|notice)(\.|$)/i.test(n)).sort();
 text+=`\n## ${dir} (${pkg.version})\n\nLicense: ${pkg.license||'See package notice'}\n`;
 for(const name of names){const p=path.join(dir,name);if(fs.statSync(p).isFile())text+='\n```text\n'+fs.readFileSync(p,'utf8').replace(/\r\n?/g,'\n')+'\n```\n';}
}
fs.writeFileSync('THIRD_PARTY_NOTICES.md',text);
