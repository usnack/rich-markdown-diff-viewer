# GitHub Release 자동 배포

`.github/workflows/release.yml`은 정확히 `release` 브랜치에 푸시할 때 실행합니다. Actions 화면에서 수동 실행할 때도 `release` 브랜치를 선택해야 합니다.

## 배포 순서

1. 워크플로와 배포할 변경을 기본 브랜치인 `main`에 먼저 반영합니다.
2. `release` 브랜치를 해당 커밋으로 갱신해 푸시합니다. `main`이 배포할 커밋이면 `git push origin main:release`로 처음 생성하거나 fast-forward 갱신할 수 있습니다.
3. Actions의 **Release macOS app** 실행 결과를 확인합니다.
4. 성공하면 저장소의 **Releases**에서 앱 ZIP을 다운로드할 수 있습니다. 워크플로 요약에도 릴리스 링크가 표시됩니다.

`GITHUB_TOKEN`에는 워크플로 파일 수정 권한을 부여할 수 없습니다. 릴리스 대상의 `.github/workflows/`가 기본 브랜치와 다르면 GitHub의 릴리스 생성·수정이 거절될 수 있으므로, 이를 빌드 전에 검사합니다. 별도의 PAT나 Apple 인증서 Secret은 요구하지 않습니다. 저장소/조직 정책으로 Actions의 쓰기 권한이 제한돼 있다면 해당 정책의 허용이 필요합니다.

## 태그 규칙

마지막 커밋의 **커미터 시각**을 **Asia/Seoul** 기준으로 계산한 날짜와 짧은 커밋 해시를 조합합니다.

```text
YYMMDD-커밋해시
261021-eb832af
```

해시는 최소 7자리이며, Git이 충돌을 구분해야 하는 경우 더 길어질 수 있습니다. 작성자 시각이나 워크플로 실행 시각은 사용하지 않습니다. `bash scripts/release-tag.sh`로 로컬에서도 같은 태그를 확인할 수 있습니다. 같은 커밋을 재실행하면 같은 태그를 사용합니다.

앱의 내부 버전(`package.json`, `Info.plist`)과 릴리스 태그는 별개입니다. 이 자동화는 커밋을 만들거나 앱 내부 버전을 자동 변경하지 않습니다.

## 빌드와 다운로드 파일

macOS 15의 Apple Silicon 러너에서 Node.js 22와 잠금 파일로 의존성을 설치한 뒤 다음을 실행합니다.

```sh
npm test
npm run package
```

러너가 `arm64`인지 검사합니다. 엔진·Git 통합·코멘트 및 릴리스 스크립트 테스트가 실패하거나, 빌드·서명 확인·ZIP 무결성 검사가 실패하면 공개하지 않습니다. GUI 화면 검증은 호스팅된 러너에서 실행하지 않습니다.

GitHub Release에 다음 세 파일을 첨부합니다.

- `Rich Markdown Diff.app.zip`: Apple Silicon macOS 14 이상용 앱. 압축을 풀고 응용 프로그램 폴더로 옮겨 실행합니다.
- `rich-markdown-diff-source.zip`: 빌드한 커밋의 소스.
- `SHA256SUMS`: 다운로드한 ZIP 파일의 SHA-256 체크섬.

세 파일을 같은 폴더에 내려받고 그 폴더에서 검증합니다.

```sh
shasum -a 256 -c SHA256SUMS
```

같은 파일을 Actions 실행의 **Artifacts**에도 30일간 보관합니다. 일반 사용자에게는 GitHub Release 다운로드 링크를 공유하면 됩니다. 비공개 저장소라면 받는 사람에게도 저장소 접근 권한이 필요합니다.

앱은 현재 방식대로 ad-hoc 서명합니다. Apple Developer ID 서명·공증은 포함하지 않으므로 첫 실행의 macOS 보안 허용이 필요할 수 있습니다. Intel 빌드는 생성하지 않습니다.

## 실패 및 재실행

릴리스를 우선 draft로 만들고 모든 첨부 파일 업로드가 성공한 뒤 공개합니다. 업로드가 실패하면 draft 상태를 유지하며, 같은 커밋으로 재실행하면 draft의 파일을 다시 업로드한 뒤 공개합니다. 이미 공개된 릴리스는 세 첨부 파일과 대상 커밋을 확인하고 그대로 유지합니다. 공개된 릴리스에 파일이 누락됐거나 대상 커밋이 다르면 실패 처리하며 덮어쓰지 않습니다.

같은 브랜치의 배포는 동시에 게시하지 않도록 직렬화합니다. 진행 중인 실행은 새 푸시로 취소하지 않습니다.

## 확인한 범위

로컬에서 워크플로 정적 검사, 태그의 날짜·시간대 계산, 게시 순서·재시도·실패 처리를 모의 GitHub CLI로 검사합니다. 실제 GitHub Actions 러너에서의 실행과 실제 GitHub Release 생성·첨부는 이 문서 작성 작업에서 수행하지 않았습니다.

공식 문서: [러너 사양](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [릴리스 API의 권한 조건](https://docs.github.com/en/rest/releases/releases#create-a-release), [GitHub CLI release](https://cli.github.com/manual/gh_release_create), [Actions artifact](https://github.com/actions/upload-artifact).
