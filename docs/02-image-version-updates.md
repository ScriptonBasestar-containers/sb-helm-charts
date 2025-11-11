# Image Version Updates - 2025-11-11

## Overview

이 문서는 2025-11-11에 수행된 전체 차트의 Docker 이미지 버전 업데이트 내역을 기록합니다.

## 업데이트 원칙

1. **Alpine 우선**: 가능한 경우 Alpine 변형 사용 (경량화, 보안)
2. **메이저 버전 명시**: 재현 가능성을 위한 구체적 버전 태그
3. **OS 버전 명시**: Alpine 버전까지 명시 (예: `alpine3.22`)
4. **최신 안정 버전**: 프로덕션 환경에서 검증된 stable 버전

## 업데이트 결과

### 1. Memcached

**변경사항:**
- `appVersion`: `1.6.32` → `1.6.39`
- `image.tag`: `""` (empty) → `1.6.39-alpine3.22`

**이유:**
- 빈 태그를 명시적 버전으로 변경
- Alpine 3.22 기반 경량 이미지 사용
- 7개 패치 버전 업그레이드

**파일:**
- [charts/memcached/Chart.yaml](../charts/memcached/Chart.yaml)
- [charts/memcached/values.yaml](../charts/memcached/values.yaml)

---

### 2. Nextcloud

**변경사항:**
- `appVersion`: `1.16.0` → `31.0.10`
- `nextcloud.version`: `28.0` → `31.0.10`
- `image.tag`: `28.0-apache` → `31.0.10-apache`

**이유:**
- appVersion이 잘못 설정되어 있었음 (1.16.0은 devpi 버전)
- Nextcloud 28.0 → 31.0.10 (stable 버전)
- 3개 메이저 버전 업그레이드

**참고:**
- `stable-apache` 태그와 동일
- Apache 변형 유지 (프로젝트 철학)
- FPM-Alpine 변형 가능하나 Nginx 추가 필요

**파일:**
- [charts/nextcloud/Chart.yaml](../charts/nextcloud/Chart.yaml)
- [charts/nextcloud/values.yaml](../charts/nextcloud/values.yaml)

---

### 3. RSSHub

**변경사항:**
- `appVersion`: `2025-04-06` → `2025-11-09`
- `image.tag`: `latest` → `2025-11-09`

**이유:**
- `latest` 태그를 날짜 기반 태그로 고정
- 재현 가능성 향상
- 7개월 분량 업데이트

**참고:**
- Chromium-bundled 변형 사용 가능: `chromium-bundled-2025-11-09`
- Puppeteer가 필요한 라우트 사용 시 고려

**파일:**
- [charts/rsshub/Chart.yaml](../charts/rsshub/Chart.yaml)
- [charts/rsshub/values.yaml](../charts/rsshub/values.yaml)

---

### 4. WireGuard

**변경사항:**
- `appVersion`: `latest` → `1.0.20250521`
- `image.tag`: `latest` → `1.0.20250521-r0-ls90`

**이유:**
- LinuxServer.io 빌드 버전 고정
- 프로덕션 안정성 향상
- 필요시 `latest`로 롤백 가능

**참고:**
- `ls90`: LinuxServer.io 빌드 번호
- `r0`: Alpine package revision
- `1.0.20250521`: WireGuard 도구 버전 (2025년 5월 21일)

**파일:**
- [charts/wireguard/Chart.yaml](../charts/wireguard/Chart.yaml)
- [charts/wireguard/values.yaml](../charts/wireguard/values.yaml)

---

### 5. Devpi ⚠️ **BREAKING CHANGE**

**변경사항:**
- `appVersion`: `1.16.0` → `6.17.0`
- `image.repository`: `ghcr.io/scriptonbasestar-containers/devpi/pypi` → `jonasal/devpi-server`
- `image.tag`: `latest` → `6.17.0-alpine`
- `pullPolicy`: `Always` → `IfNotPresent`

**이유:**
- 기존 GHCR 이미지가 비공개 (접근 불가)
- `jonasal/devpi-server`는 공개 이미지로 널리 사용됨
- Alpine 기반 경량 이미지 (약 150MB)
- devpi-server 6.x로 메이저 업그레이드

**⚠️ Breaking Changes:**
- 이미지 완전 교체로 인한 호환성 문제 가능
- devpi-server 6.x는 Python 3.8+ 필요
- 데이터 마이그레이션 필요할 수 있음
- 상세 마이그레이션 가이드: [charts/devpi/MIGRATION.md](../charts/devpi/MIGRATION.md)

**파일:**
- [charts/devpi/Chart.yaml](../charts/devpi/Chart.yaml)
- [charts/devpi/values.yaml](../charts/devpi/values.yaml)
- [charts/devpi/MIGRATION.md](../charts/devpi/MIGRATION.md) (신규)

---

## 변경하지 않은 차트

### 안정적인 차트들

| 차트 | Repository | Tag | appVersion | 사유 |
|------|-----------|-----|------------|------|
| **browserless-chrome** | `ghcr.io/browserless/chrome` | `1.61.1-puppeteer-21.4.1` | 1.61.1 | appVersion과 일치, 안정적 |
| **keycloak** | `quay.io/keycloak/keycloak` | `26.0.6` | 26.0.6 | appVersion과 일치, 최신 버전 |
| **rabbitmq** | `rabbitmq` | `3.13.1-management` | 3.13.1 | appVersion과 일치, management 변형 |
| **redis** | `redis` | `7.4.1-alpine` | 7.4.1 | appVersion과 일치, Alpine 사용 |
| **wordpress** | `wordpress` | `6.4.3-apache` | 6.4.3 | appVersion과 일치, Apache 변형 |

---

## 이미지 버전 관리 가이드

### Alpine vs Debian 선택

| 환경 | 권장 변형 | 이유 |
|------|----------|------|
| **프로덕션** | Alpine | 작은 크기, 빠른 배포, 보안 |
| **개발/테스트** | Alpine | 동일 환경 유지 |
| **호환성 문제** | Debian | 더 넓은 패키지 지원 |

### 태그 전략

```yaml
# 가장 안정적 (프로덕션)
tag: "1.6.39-alpine3.22"

# 패치 자동 업데이트
tag: "1.6-alpine3.22"

# 마이너 자동 업데이트
tag: "1-alpine3.22"

# 최신 Alpine (테스트 환경)
tag: "alpine"

# 최신 버전 (비권장)
tag: "latest"
```

### 버전 업데이트 체크리스트

1. **Docker Hub/Quay/GHCR 확인**
   - 최신 stable 태그 확인
   - Alpine 변형 존재 여부
   - OS 버전 (alpine3.22, alpine3.21 등)

2. **호환성 검증**
   - 차트의 다른 설정과 호환성
   - 외부 의존성 (PostgreSQL, Redis 등) 버전
   - Breaking changes 확인

3. **파일 업데이트**
   - `Chart.yaml`: `appVersion` 업데이트
   - `values.yaml`: `image.tag` 업데이트
   - 관련 문서 업데이트

4. **테스트**
   - `make lint` 통과
   - `make template` 확인
   - 로컬 Kind 클러스터에서 설치 테스트

---

## Bitnami 의존성 제거

### GitHub Actions Workflow

**변경사항:**
- `.github/workflows/release.yaml`에서 Bitnami 레포 추가 단계 제거

**이유:**
- 프로젝트 철학: "Avoid subchart complexity"
- 모든 차트가 외부 데이터베이스 사용
- `dependencies:` 섹션 없음

**파일:**
- [.github/workflows/release.yaml](../.github/workflows/release.yaml)

### Memcached NOTES.txt

**변경사항:**
- Bitnami 이미지 대신 busybox 사용
- 테스트 명령어 간소화
- Makefile 사용 권장

**변경 전:**
```bash
kubectl run --namespace default memcached-client --rm --tty -i --restart='Never' \
  --image docker.io/bitnami/memcached:latest -- \
  memcached-tool memcached:11211 stats
```

**변경 후:**
```bash
kubectl run --namespace default memcached-client --rm --tty -i --restart='Never' \
  --image busybox:latest -- \
  sh -c 'echo "stats" | nc memcached 11211'
```

**파일:**
- [charts/memcached/templates/NOTES.txt](../charts/memcached/templates/NOTES.txt)

---

## 다음 단계

### 완료

- [x] Memcached 이미지 업데이트 (1.6.39-alpine3.22)
- [x] Nextcloud 이미지 업데이트 (31.0.10-apache)
- [x] RSSHub 이미지 업데이트 (2025-11-09)
- [x] WireGuard 이미지 업데이트 (1.0.20250521-r0-ls90)
- [x] Devpi 이미지 교체 (jonasal/devpi-server:6.17.0-alpine)
- [x] Bitnami 의존성 제거
- [x] 모든 차트 lint 검증 통과
- [x] 마이그레이션 가이드 작성 (devpi)

### 즉시 필요

- [ ] Devpi 마이그레이션 테스트
  - 기존 데이터 백업 및 복원 테스트
  - 새 이미지 동작 검증
  - 호환성 문제 확인

### 장기 계획

- [ ] 자동 이미지 버전 체크 스크립트
- [ ] 월간 버전 업데이트 루틴
- [ ] values-example.yaml 파일들도 동기화
- [ ] Alpine 사용률 향상 (현재 50% → 목표 80%+)

---

## 상세 이미지 정보

### Memcached

**Docker Hub**: https://hub.docker.com/_/memcached

**사용 가능한 태그:**
- `1.6.39-alpine3.22` (권장)
- `1.6-alpine3.22` (자동 패치 업데이트)
- `1-alpine3.22` (자동 마이너 업데이트)
- `alpine` (최신 Alpine)

**크기:**
- Alpine: ~10MB
- Debian: ~80MB

---

### Nextcloud

**Docker Hub**: https://hub.docker.com/_/nextcloud

**사용 가능한 태그:**
- `31.0.10-apache` (stable, 권장)
- `32.0.1-apache` (latest)
- `31.0.10-fpm-alpine` (경량)

**변형 비교:**

| 변형 | 크기 | 웹서버 | 특징 |
|------|------|--------|------|
| apache | ~900MB | Apache 포함 | 간편한 배포 |
| fpm-alpine | ~400MB | Nginx 별도 | 경량, 복잡한 설정 |

---

### RSSHub

**Docker Hub**: https://hub.docker.com/r/diygod/rsshub

**사용 가능한 태그:**
- `2025-11-09` (권장, 날짜 기반)
- `chromium-bundled-2025-11-09` (Puppeteer 포함)
- `latest` (최신)

**변형 비교:**

| 변형 | 크기 | 용도 |
|------|------|------|
| Standard | ~500MB | 일반 RSS 피드 |
| chromium-bundled | ~1.5GB | Puppeteer 필요한 라우트 |

---

### WireGuard (LinuxServer.io)

**LSCR**: https://lscr.io/linuxserver/wireguard

**사용 가능한 태그:**
- `1.0.20250521-r0-ls90` (권장, 고정 버전)
- `version-1.0.20250521-r0` (semantic)
- `latest` (자동 업데이트)

**태그 구조:**
```
1.0.20250521-r0-ls90
│   │        │  └── LinuxServer build 번호
│   │        └───── Alpine package revision
│   └────────────── WireGuard 버전 (날짜 기반)
└────────────────── Major version
```

---

## 전체 차트 이미지 버전 요약

| 차트 | Repository | Tag | Alpine | Updated |
|------|-----------|-----|--------|---------|
| browserless-chrome | ghcr.io/browserless/chrome | 1.61.1-puppeteer-21.4.1 | ❌ | ✅ |
| devpi | jonasal/devpi-server | 6.17.0-alpine | ✅ | ✅ ⚠️ |
| keycloak | quay.io/keycloak/keycloak | 26.0.6 | ❌ | ✅ |
| memcached | memcached | 1.6.39-alpine3.22 | ✅ | ✅ |
| nextcloud | nextcloud | 31.0.10-apache | ❌ | ✅ |
| rabbitmq | rabbitmq | 3.13.1-management | ❌ | ✅ |
| redis | redis | 7.4.1-alpine | ✅ | ✅ |
| rsshub | diygod/rsshub | 2025-11-09 | ❌ | ✅ |
| wireguard | lscr.io/linuxserver/wireguard | 1.0.20250521-r0-ls90 | ✅ | ✅ |
| wordpress | wordpress | 6.4.3-apache | ❌ | ✅ |

**Alpine 사용률**: 5/10 (50%)
**Breaking Changes**: devpi (⚠️ 이미지 완전 교체)

---

## 참조

- [Docker Hub](https://hub.docker.com/)
- [Quay.io](https://quay.io/)
- [GHCR](https://ghcr.io/)
- [LinuxServer.io](https://www.linuxserver.io/)
- [Alpine Linux](https://alpinelinux.org/)

---

**Last Updated**: 2025-11-11
**Updated By**: Claude Code (Sonnet 4.5)
