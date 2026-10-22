# Rich Markdown Diff

macOS에서 로컬 Git 저장소의 Markdown 변경을 렌더링해 읽는 독립 앱입니다. Swift/AppKit + WKWebView를 사용하며 Node 서버, Python 프로세스, CDN 없이 실행합니다. 이 저장소에 네이티브 앱, 웹 렌더러, 테스트와 실행 안내를 함께 관리합니다. 확정 요구사항은 [구현 계획](docs/implementation-plan.md)을 참고하세요.

## 바로 실행

`dist/Rich Markdown Diff.app`을 Finder에서 열거나 다음 명령을 실행합니다.

```sh
open "dist/Rich Markdown Diff.app"
```

앱의 **저장소 열기…** 또는 **⌘O**로 로컬 Git 저장소를 선택하고, 왼쪽 파일을 선택하세요. 기본 비교는 HEAD와 현재 작업 디렉터리입니다. 인덱스 기준 두 비교도 선택할 수 있습니다. 통합형/좌우형, 변경만 보기, 위·아래 변경 이동, 자동 갱신 일시정지/재개를 제공합니다.

- 실행 환경: Apple Silicon macOS 14 이상, `/usr/bin/git` 사용 가능. 실제 검증 환경은 macOS 26.6.2 arm64입니다. 다른 macOS 버전과 Intel Mac은 실행 검증하지 않았습니다.
- 개인 로컬 실행을 위한 ad-hoc 서명입니다. Apple Developer ID 서명·공증·자동 업데이트는 포함하지 않습니다. 외부로 전달한 다운로드본은 Gatekeeper의 별도 허용이 필요할 수 있습니다.
- 소스는 이 저장소에서 관리하며 앱과 압축본은 빌드 시 `dist/`에 생성됩니다. `dist/`는 Git 추적 대상에서 제외합니다.
- 비교는 읽기 전용입니다. 일반 실행 중 문서·인덱스·커밋을 변경하지 않습니다. 아래 opt-in 검증 모드는 생성된 데모 저장소만 수정하고 복구합니다.

## 코멘트와 파일 트리

왼쪽 변경 파일은 저장소 상대 경로를 따라 폴더 트리로 표시합니다. 폴더를 눌러 접고 펼칠 수 있고, 폴더 옆 숫자는 하위 변경 문서 수입니다. 갱신해도 접힘 상태를 유지하며, 다른 파일을 선택하면 그 파일의 상위 폴더를 펼칩니다. 파일에 마우스를 올리면 전체 상대 경로를 확인할 수 있습니다.

코멘트는 다음과 같이 사용합니다.

1. 본문 블록의 **＋ 코멘트 · L…**를 누릅니다. 렌더링된 텍스트를 선택한 경우에는 선택한 라인 범위가 제안됩니다.
2. 오른쪽에서 변경 전/후 기준과 시작·끝 라인을 확인합니다. **원문 라인 선택**을 펼쳐 라인을 클릭하고, Shift+클릭으로 여러 라인을 선택할 수도 있습니다. HTML·Mermaid 등의 정확한 범위도 원문에서 선택할 수 있습니다.
3. 코멘트를 입력하고 **코멘트 추가** 또는 **⌘Enter**를 누릅니다. 같은 라인 범위에 여러 개를 추가할 수 있습니다. 기존 코멘트의 **같은 범위에 추가**도 사용할 수 있습니다.
4. 각 카드의 **복사** 또는 패널의 **모두 복사**로 macOS 클립보드에 복사합니다. 모두 복사는 현재 문서의 저장된 코멘트를 작성 순서대로 포함합니다. 다른 비교 시점에서 작성한 코멘트도 포함되며 다른 문서의 코멘트는 포함하지 않습니다.

복사 형식은 다음과 같습니다. `Excerpt`는 선택한 Markdown 원문 라인 전체이며, 따옴표와 줄바꿈이 포함된 코멘트는 JSON 문자열 방식으로 이스케이프합니다. 단일 라인은 `Lines 7`로 표시합니다.

```text
File: 02-단원-기획/src/03-개발환경_및_프로그래밍_기초/01-리눅스_및_개발환경.md
Source: markdown

Lines 7-10
Excerpt:
> 터미널에서 파일·경로·패키지·권한을 확인하고 실행 오류의 원인을 구분할 수 있다.
User comment: "asdf"
```

코멘트는 저장소·문서별로 `~/Library/Application Support/Rich Markdown Diff/comments.json`에 저장되어 앱을 다시 열어도 유지됩니다. Markdown 파일과 Git 인덱스는 변경하지 않습니다. 코멘트 내용 수정·삭제도 가능합니다.

작성 당시의 라인·인용문과 비교 시점(HEAD/INDEX/WORK)을 보존합니다. 원문이 변경되어 같은 라인에 다른 내용이 있으면 카드에 표시하고, 복사에는 작성 당시 인용문을 사용합니다. 작성 중 원문이 바뀌면 초안을 유지하고 라인 재선택을 요구합니다. 문서의 변경이 사라져도 현재 문서의 기존 코멘트는 복사할 수 있습니다. 파일이 다른 경로로 이동하면 코멘트를 새 경로로 자동 이관하지 않습니다.

## 터미널에서 열기

이 전달본에는 `rmdiff` 명령을 설치합니다. 저장소와 Markdown 파일 경로를 받을 수 있으며 실행 중인 앱에도 전달됩니다.

```sh
rmdiff .
rmdiff /path/to/repository
rmdiff "/path/to/repository/한글 문서.md"
rmdiff --help
```

경로를 생략하면 현재 디렉터리를 엽니다. 변경 목록에 없는 파일을 지정하면 해당 파일에 변경이 없다는 빈 상태가 표시됩니다. 읽기 전용이며 Git 변경 작업은 하지 않습니다.

다른 컴퓨터나 다른 위치에 소스를 설치했다면 다음 명령으로 런처를 연결하세요. 기존 `rmdiff` 파일은 덮어쓰지 않습니다.

```sh
bash scripts/install-cli.sh                 # /usr/local/bin/rmdiff
bash scripts/install-cli.sh "$HOME/.local/bin"  # 사용자 지정 위치
```

지정한 디렉터리가 PATH에 있어야 합니다. 설치된 명령은 프로젝트 안의 런처를 가리키므로 프로젝트를 이동하면 해당 심볼릭 링크도 새 경로로 다시 연결해야 합니다. 제거할 때는 설치한 `rmdiff` 심볼릭 링크만 삭제하세요. `.app`은 독립적으로도 실행할 수 있습니다.

## 제공 기능

| 영역 | 동작 |
| --- | --- |
| 코멘트 | 원문 라인 범위, 같은 범위의 복수 코멘트, 로컬 저장, 개별·문서 전체 복사, 수정·삭제 |
| 파일 탐색 | 폴더 트리, 접기·펼치기, 하위 변경 수, 전체 경로 툴팁 |
| Git | HEAD→현재, 인덱스→현재, HEAD→인덱스; 초기 저장소; untracked 포함 및 ignore 제외; 추가/삭제/이름 변경; linked worktree |
| Rich diff | Markdown AST 정렬, 한글·이모지 grapheme 단위 강조, 표 셀 강조, 제목/강조/링크/참조 링크 변경, 렌더링이 같은 원문 변경 표시 |
| 보기 | 문서 전체 또는 변경 블록만, 변경 이동, 좌우 대응 행 높이 공유 및 단일 스크롤 |
| 확장 | 번들 Mermaid 전후 렌더링·원문 diff·오류 격리, HTML details/summary/table/div, 제한된 문서 CSS |
| 이미지 | 로컬 PNG/JPEG/GIF/WebP/AVIF/SVG의 HEAD/인덱스/현재 바이트 사용, 과거 누락 명시, 외부 URL 응답 및 실패 표시 |
| 작업 흐름 | 1.2초 보완 조회, 일시정지/재개, 가시 블록과 오프셋 복원, 저장소·선택 파일·비교 기준·보기 기억 |

통합형의 수정 블록은 변경 전과 후를 같은 문서 흐름에 연속해서 표시합니다. 실제 바뀐 문구에 추가 강조가 적용됩니다. 복잡한 HTML과 Mermaid는 전후를 각각 표시하고 원문 변경도 펼쳐 볼 수 있습니다.

## 빌드 및 테스트

개발에 Node.js 22.12 이상, npm, Xcode Command Line Tools의 Swift 컴파일러가 필요합니다. macOS SDK가 설치되어 있어야 합니다.

```sh
npm ci
npm test
npm run build
open "dist/Rich Markdown Diff.app"
```

공유용 앱 ZIP과 커밋된 소스 ZIP은 변경을 커밋한 뒤 `npm run package`로 생성합니다. 출력은 `dist/Rich Markdown Diff.app.zip`, `dist/rich-markdown-diff-source.zip`, `dist/SHA256SUMS`입니다. 소스 압축본은 현재 Git 커밋을 기준으로 만듭니다.

기존 프로젝트의 스킬 연결은 `npm run fetch-project-skills`로 실행합니다.

`package-lock.json`에 의존성을 고정했습니다. 빌드 시 JavaScript를 단일 번들로 묶고, 라이브러리의 라이선스 고지를 앱 리소스에도 포함합니다. Node/npm은 빌드 및 테스트에서만 사용합니다. `npm test`는 AST/보안 테스트와 실제 임시 Git 저장소 통합 테스트를 실행합니다.

실제 macOS 앱 검증은 다른 Rich Markdown Diff 인스턴스를 닫은 뒤 실행합니다. GUI 세션이 필요합니다.

```sh
bash scripts/verify-app.sh
```

최초 실행은 재시작 복원 항목을 제외한 32개 검사이며, 같은 검증을 다시 실행하면 저장된 코멘트 복원을 포함한 33개 검사를 수행합니다.

이 명령은 `verification/demo`에 독립 데모 저장소를 만들고 실제 앱의 WKWebView에서 UI를 조작합니다. 문서를 수정하고 스테이징하는 단계는 `.rmd-demo` 표식과 검증 출력 경로가 일치하는 데모에서만 실행합니다. 사용자 저장소에는 적용하지 않습니다. 데모 내용이 수동 변경되었다면 별도 경로에 새로 생성해 검증하세요. 종료·재실행 복원과 네이티브 폴더 선택은 별도 수동 UI 확인 항목입니다.

결과는 `verification/app-results.json`, `verification/workflow-results.json`, `verification/app-screen.png`에 기록됩니다. `node scripts/check-verification.mjs`는 실패가 있으면 0이 아닌 상태로 종료합니다. 실제 수행 결과와 미검증 범위는 [VERIFICATION.md](VERIFICATION.md)에 있습니다.

## 구성과 설계 선택

- `native/Git.swift`: 셸을 통하지 않는 Git 인자 배열 실행, NUL 파일 목록, 시점별 원문/이미지 조회, 경로 경계, 시간/크기 제한.
- `native/main.swift`: AppKit 창·폴더 선택·설정 저장, 비동기 직렬 Git 큐, 세대 번호로 오래된 응답 제외, WKWebView 브리지.
- `native/Verification.swift`: 명시적으로 켠 데모 전용 실제 앱 검증 하네스.
- `web/src/engine.js`: remark/GFM AST와 원문 위치, 동일 블록 우선 정렬, 순서와 유사도로 수정 블록 대응, grapheme diff.
- `web/src/sanitize.js`: DOMPurify 및 CSS 속성 허용 목록. 각 문서 블록은 Shadow DOM에 격리하고 같은 쪽 문서의 안전한 스타일만 공유.
- `web/src/app.js`: 같은 모델을 사용하는 두 보기, DOM 텍스트 노드 강조, 표 셀 비교, Mermaid, 이미지, 스크롤 위치 복원.

자동 갱신은 제안의 파일 감시+debounce 대신 **1.2초 주기 재조회**로 구현했습니다. 중첩 파일, 인덱스, HEAD, linked worktree의 변경을 한 경로로 감지하기 위한 선택입니다. 보통 다음 조회에 반영되지만 대형 저장소에서는 Git 실행 시간만큼 더 걸립니다. 저장 이벤트 300ms 이내 반영을 보장하지 않습니다. 동일 응답은 다시 렌더링하지 않습니다.

문서 스크립트·이벤트 속성·iframe과 위험 링크를 제거하고 CSP로 스크립트/프레임/임의 연결을 제한합니다. 문서 CSS는 허용 속성만 남기고 Shadow DOM에 적용합니다. 네이티브 메시지 핸들러는 별도 WKContentWorld에 등록해 문서의 JavaScript 세계에서 접근하지 못하게 했습니다. 로컬 파일은 저장소 경계 및 심볼릭 링크를 확인합니다. 외부 http(s) 링크는 사용자 클릭 시 브라우저로 엽니다.

## GitHub Release 자동 배포

`release` 브랜치에 푸시하면 테스트·빌드 후 `YYMMDD-짧은커밋해시` 태그의 GitHub Release를 만들고 앱 ZIP, 소스 ZIP, 체크섬을 첨부합니다. 날짜는 마지막 커밋의 커미터 시각을 한국 시간으로 계산합니다. [배포 안내](docs/release.md)를 참고하세요.

## 알려진 제한

- UTF-8 Markdown만 지원합니다. 문서 4MB, 현재 파일 16MB, 개별 이미지 12MB, Git 응답 64MB, Git 명령 15초 제한이 있습니다. 제한 초과는 오류로 표시합니다.
- 5만 자를 넘는 텍스트 비교나 diff 계산 시간 제한 초과는 문구 강조 대신 블록 전체 강조로 대체합니다. 매우 큰 변경 구간은 추가/삭제 블록으로 표시합니다. 대형 저장소 성능은 벤치마크하지 않았습니다.
- HTML의 모든 CSS/웹 기능을 재현하지 않습니다. `position`, 네트워크 CSS, `@import`, 외부 폰트, iframe, 폼 등은 지원하지 않습니다. 스타일 격리 단위 때문에 블록 경계를 넘는 복잡한 CSS 레이아웃은 원문과 다를 수 있습니다.
- 이미지 참조 수집은 일반 Markdown inline/reference 이미지와 따옴표로 감싼 HTML `src`를 지원합니다. 여러 단계로 중첩한 괄호와 복잡한 이스케이프 이미지 경로 일부, 따옴표 없는 HTML `src`, `<picture>`/`srcset`, 문서에 직접 삽입한 data URL은 제한됩니다. 허용하지 않거나 찾지 못한 로컬 이미지는 누락으로 표시합니다.
- 이미지 바이트 변경은 변경 중인 Markdown의 해당 이미지 블록에 반영합니다. 이미지 파일만 변경하고 Markdown 원문에는 변경이 없으면 사이드바에 문서를 새로 추가하지 않습니다.
- 과거 시점의 심볼릭 링크/서브모듈은 추적해 읽지 않습니다. 저장소 밖 이미지도 차단합니다. 외부 이미지는 현재 응답만 보이며 과거 상태를 복원하지 않습니다.
- 스크롤 복원은 유지된 블록을 우선합니다. 가시 구간 전체가 교체되거나 반복되는 동일 블록의 순서가 크게 바뀌면 정확한 위치를 보장하지 않습니다. HTML details의 열림 상태는 재렌더링 시 초기화될 수 있습니다.
- macOS의 `/usr/bin/git`이 개발 도구 설치를 요구하는 깨끗한 머신, 외부 배포 서명·공증, 접근성 전체 감사, Intel 빌드, Orca 편집기 자체 저장 동작은 별도로 검증해야 합니다. 다른 프로그램의 파일 저장은 앱의 폴링 갱신에 반영됩니다.

의존성 공식 문서: [remark/GFM](https://github.com/remarkjs/remark-gfm), [DOMPurify](https://github.com/cure53/DOMPurify), [Mermaid strict 보안 설정](https://mermaid.js.org/config/schema-docs/config-properties-securitylevel.html). 라이선스는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요.
