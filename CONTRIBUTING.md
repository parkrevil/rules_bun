# 기여 안내

## 개발 환경

Bazelisk와 prek 0.5.3 이상을 설치한 뒤 저장소 루트에서 실행합니다.
Bazel 버전은 `.bazelversion`을 따릅니다.

```sh
prek install
prek run --all-files
bazel test //...
```

`prek install`은 `.pre-commit-config.yaml`에 지정된 `pre-commit`과
`commit-msg` 훅을 설치합니다. 새로 복제한 저장소마다 실행해야 합니다.

외부 모듈에서의 사용은 별도로 검증합니다.

```sh
cd e2e/smoke
bazel build //:verify
```

## 생성 파일

Starlark 소스의 의존성을 바꾸면 BUILD 파일을 갱신합니다.

```sh
bazel run //:gazelle
```

Bazel 버전이나 bazelrc-preset.bzl을 변경하면 기본 플래그를 갱신합니다.

```sh
bazel run //tools:preset.update
```

## 커밋 메시지

이 프로젝트는 `.pre-commit-config.yaml`에 고정된 Commitizen의
`cz_conventional_commits` 기본 규칙을 사용합니다.

```text
type(scope)!: 설명

본문

푸터
```

- 허용 type: `build`, `bump`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`,
  `refactor`, `revert`, `style`, `test`.
- scope는 선택이며 공백 없이 작성합니다. 별도의 허용 목록은 없습니다.
- 호환성을 깨는 변경은 `!` 또는 `BREAKING CHANGE:` 푸터로 표시합니다.
- 콜론 뒤에는 공백을 둡니다. 설명은 한국어로 작성할 수 있습니다.
- 본문을 작성하면 제목 뒤에 빈 줄을 둡니다. 제목 길이 제한은 없습니다.
- `Merge`, `Revert`, `Pull request`, `fixup!`, `squash!`, `amend!`로 시작하는
  메시지는 Commitizen 기본 동작에 따라 검사를 생략합니다.
- 빈 메시지는 커밋 취소를 위해 훅 검사를 통과합니다.

```text
fix(toolchain): 실행 파일 경로 수정
```

규칙 근거는 [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)와
[Commitizen 검사 문서](https://commitizen-tools.github.io/commitizen/commands/check/)입니다.
