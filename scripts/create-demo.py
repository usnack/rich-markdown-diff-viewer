#!/usr/bin/env python3
import pathlib,subprocess,sys,struct,zlib
root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else 'verification/demo').resolve()
root.mkdir(parents=True,exist_ok=True)
def add_tree_fixtures():
 for relative in ['02-단원-기획/src/03-개발환경/01-리눅스.md','02-단원-기획/src/03-개발환경/02-프로그래밍.md','docs/참고 문서.md']:
  p=root/relative;p.parent.mkdir(parents=True,exist_ok=True)
  if not p.exists():p.write_text('# '+p.stem+'\n\n디렉터리 트리에서 문서의 위치를 확인합니다.\n')
if (root/'.git').exists():
 if (root/'.rmd-demo').exists():add_tree_fixtures()
 print(root);sys.exit(0)
def git(*args):subprocess.run(['git','-C',str(root),*args],check=True,stdout=subprocess.DEVNULL)
def png(color):
 def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
 w,h=240,80
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes(color)*w)*h))+chunk(b'IEND',b'')
git('init','-q');git('config','user.email','demo@example.invalid');git('config','user.name','Rich Diff Demo')
before='''# 제품 설계 노트

문서를 읽기 쉽게 만들고, 변경 내용을 정확하게 확인합니다. 👨‍👩‍👧‍👦

## 이번 주 목표

- [x] Git 저장소 열기
- [ ] 렌더링 문서 비교
  - 한글 문장과 **중요한 내용** 표시

| 항목 | 상태 | 담당 |
| --- | --- | --- |
| 문서 비교 | 준비 중 | 기획 |
| 자동 갱신 | 설계 | 개발 |

> 작은 변경도 놓치지 않는 검토 흐름을 만듭니다.

```mermaid
flowchart LR
  A[문서 저장] --> B[변경 조회]
  B --> C[문서 비교]
```

<details><summary>검토 메모 펼치기</summary><div style="color:#38664f;padding:8px">문서 HTML을 안전하게 표시합니다.</div></details>

![시점별 이미지](pixel.png)

[프로젝트 안내][guide]

[guide]: https://example.com/old

```swift
let mode = "unified"
```

'''
long='\n\n'.join(f'### 검토 항목 {i}\n\n{i}번째 확인 문단입니다. 문서 중간에서 저장해도 읽던 위치를 유지합니다.' for i in range(1,31))
(root/'01-제품 설계.md').write_text(before+long)
(root/'pixel.png').write_bytes(png((181,202,231)))
(root/'삭제 문서.md').write_text('이 문서는 삭제됩니다.')
(root/'이전 이름.md').write_text('# 이동한 문서\n\n이름 변경을 확인합니다.')
(root/'.gitignore').write_text('무시.md\n')
git('add','.');git('commit','-qm','Initial document')
staged=before.replace('변경 내용을 정확하게','실제 바뀐 문구를 정확하게').replace('| 준비 중 |','| 검증 중 |').replace('B[변경 조회]','B[Git 비교]').replace('example.com/old','example.com/new').replace('let mode = "unified"','let mode = "split"')
(root/'01-제품 설계.md').write_text(staged+long)
(root/'pixel.png').write_bytes(png((159,210,179)))
git('add','01-제품 설계.md','pixel.png')
current=(staged+long).replace('## 이번 주 목표','### 이번 주 목표').replace('- [ ] 렌더링 문서 비교','- [x] 렌더링 문서 비교').replace('| 설계 | 개발 |','| 구현 완료 | 개발 |')
current+='''

## 오류 격리와 보안 확인

```mermaid
flowchart LR
  A --> [broken
```

<style>header {position:fixed;background:red} h3 {color:#466484}</style>

<div onclick="window.pwned=1">안전한 본문<script>window.pwned=1</script><iframe src="https://example.com"></iframe><a href="javascript:alert(1)">위험 링크 제거</a></div>

![누락](missing.png)

![외부](https://example.invalid/no-image.png)
'''
(root/'01-제품 설계.md').write_text(current)
(root/'pixel.png').write_bytes(png((231,192,137)))
(root/'삭제 문서.md').unlink();git('mv','이전 이름.md','변경 이름.md')
(root/'새 문서.md').write_text('# 새 문서\n\n아직 Git에 추가하지 않은 문서입니다.')
(root/'무시.md').write_text('목록에 나타나면 안 됩니다.')
add_tree_fixtures()
(root/'.rmd-demo').write_text('Rich Markdown Diff verification fixture')
print(root)
