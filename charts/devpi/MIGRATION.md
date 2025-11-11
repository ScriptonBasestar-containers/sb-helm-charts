# Devpi Image Migration Guide

## Overview

Devpi 차트의 Docker 이미지가 변경되었습니다:

- **이전**: `ghcr.io/scriptonbasestar-containers/devpi/pypi:latest`
- **현재**: `jonasal/devpi-server:6.17.0-alpine`

## Breaking Changes

### 1. 이미지 변경

**이유:**
- 기존 GHCR 이미지가 공개되지 않음 (접근 불가)
- `jonasal/devpi-server`는 Docker Hub에서 공개적으로 사용 가능
- Alpine 기반으로 경량화 (약 150MB)
- devpi-server 6.x로 메이저 업그레이드

### 2. 버전 변경

- **appVersion**: `1.16.0` → `6.17.0`
- devpi-server 6.x는 Python 3.8+ 필요
- 설정 파일 형식 변경 가능성 있음

### 3. 포트 및 경로

`jonasal/devpi-server` 이미지의 기본 설정:
- **포트**: 3141 (동일)
- **데이터 경로**: `/data` (확인 필요)
- **로그**: stdout/stderr

## Migration Steps

### Step 1: 백업

기존 데이터를 백업합니다:

```bash
# PVC 데이터 백업
kubectl exec -it deployment/devpi -- tar czf /tmp/devpi-backup.tar.gz /data
kubectl cp devpi-pod:/tmp/devpi-backup.tar.gz ./devpi-backup.tar.gz
```

### Step 2: 기존 차트 제거

```bash
helm uninstall devpi
```

**⚠️ 주의**: PVC는 `Retain` 정책이 설정되어 있으면 자동 삭제되지 않습니다.

### Step 3: 새 이미지로 설치

```bash
# 최신 차트 pull
helm repo update

# 새 이미지로 설치
helm install devpi scripton-charts/devpi \
  --set image.repository=jonasal/devpi-server \
  --set image.tag=6.17.0-alpine
```

### Step 4: 데이터 마이그레이션 확인

```bash
# 로그 확인
kubectl logs -f deployment/devpi

# devpi 상태 확인
kubectl exec -it deployment/devpi -- devpi-server --version
```

## 호환성 확인

### devpi-server 6.x 요구사항

- **Python**: 3.8+
- **PostgreSQL**: (선택) 외부 PostgreSQL 사용 가능
- **Redis**: (선택) 캐싱용

### 설정 파일

devpi-server 6.x는 설정 파일 형식이 다를 수 있습니다. 기존 설정을 확인하세요:

```bash
kubectl exec -it deployment/devpi -- devpi-server --configfile /config/devpi.yml --version
```

## Rollback

문제 발생 시 이전 이미지로 롤백:

```bash
helm upgrade devpi scripton-charts/devpi \
  --set image.repository=ghcr.io/scriptonbasestar-containers/devpi/pypi \
  --set image.tag=latest \
  --set image.pullPolicy=Always
```

**⚠️ 주의**: GHCR 이미지가 비공개이므로 `imagePullSecrets` 설정 필요

## 알려진 문제

### 1. 포트 변경

`jonasal/devpi-server`의 기본 포트가 다를 수 있습니다. values.yaml에서 확인:

```yaml
service:
  port: 3141  # devpi 기본 포트 유지
```

### 2. 환경 변수

새 이미지는 다른 환경 변수를 사용할 수 있습니다. 문서 참조:
- https://hub.docker.com/r/jonasal/devpi-server

### 3. 데이터 디렉토리

데이터 디렉토리 경로가 변경되었을 수 있습니다:

```yaml
persistence:
  enabled: true
  mountPath: /data  # 기본값, 확인 필요
```

## 테스트 체크리스트

- [ ] devpi-server 버전 확인
- [ ] 기존 패키지 목록 확인
- [ ] 업로드 테스트
- [ ] 다운로드 테스트
- [ ] 인증 테스트 (사용자/비밀번호)
- [ ] 외부 연동 테스트 (PyPI 프록시)

## 지원

문제 발생 시:
1. GitHub Issues: https://github.com/scriptonbasestar-containers/sb-helm-charts/issues
2. jonasal/devpi-server 문서: https://hub.docker.com/r/jonasal/devpi-server

---

**Last Updated**: 2025-11-11
**Updated By**: Claude Code (Sonnet 4.5)
