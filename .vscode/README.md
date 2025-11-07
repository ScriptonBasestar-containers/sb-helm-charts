# VSCode 설정 안내

이 디렉토리에는 Helm 차트 개발을 위한 VSCode 설정이 포함되어 있습니다.

## 권장 확장 프로그램

다음 확장 프로그램 설치를 권장합니다:

1. **YAML** (redhat.vscode-yaml)
   - YAML 문법 하이라이팅
   - 자동 완성

2. **Kubernetes** (ms-kubernetes-tools.vscode-kubernetes-tools)
   - Kubernetes 리소스 지원
   - Helm 차트 미리보기

VSCode에서 자동으로 설치를 권장합니다.

## 설정 설명

### `settings.json`

- **`yaml.validate: false`**: Helm 템플릿 파일의 YAML 검증을 비활성화
  - Helm 템플릿 문법(`{{-`, `}}` 등)이 YAML 파서에서 오류로 표시되는 것을 방지
  - 실제 `helm lint` 검증은 별도로 실행

- **YAML 하이라이팅**: 모든 `.yaml` 파일에서 유지
  - 색상 구문 강조
  - 들여쓰기 가이드

### `.yamllint`

yamllint 도구 사용 시 Helm 템플릿 디렉토리를 자동으로 제외합니다.

## Helm 차트 검증

VSCode의 YAML 검증 대신 다음 명령어를 사용하세요:

```bash
# 전체 차트 검증
make lint

# 특정 차트 검증
make -f Makefile.keycloak.mk lint

# 템플릿 렌더링 확인
make -f Makefile.keycloak.mk template
```

## 문제 해결

### 하이라이팅이 작동하지 않는 경우

1. VSCode 재시작: `Ctrl+Shift+P` → "Reload Window"
2. YAML 확장 프로그램 재설치
3. 파일 언어 모드 확인: 우하단에 "YAML" 표시 확인

### 여전히 빨간 줄이 보이는 경우

- `yaml.validate: false` 설정이 적용되었는지 확인
- VSCode 사용자 설정(User Settings)에서 `yaml.validate`가 `true`로 설정되어 있지 않은지 확인
- 워크스페이스 설정이 사용자 설정보다 우선 적용됩니다
