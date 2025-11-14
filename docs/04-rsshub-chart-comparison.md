# RSSHub 차트 비교: 자체 제작 vs 외부 차트

## 개요

이 문서는 sb-helm-charts의 RSSHub 차트와 [NaturalSelectionLabs RSSHub 차트](https://github.com/NaturalSelectionLabs/helm-charts/tree/main/charts/rsshub)를 비교하여 권장 사항을 제시합니다.

---

## 1. 차트 기본 정보

### sb-helm-charts RSSHub (자체 제작)

| 항목 | 값 |
|------|-----|
| Chart Version | 0.1.0 |
| App Version | 2025-11-09 |
| 유지보수 | 자체 관리 |
| 저장소 | sb-helm-charts |
| 라이센스 | BSD-3-Clause |

### NaturalSelectionLabs RSSHub (외부)

| 항목 | 값 |
|------|-----|
| Chart Version | 0.1.1 (application-0.1.1) |
| App Version | latest (diygod/rsshub) |
| 유지보수 | NaturalSelectionLabs |
| 저장소 | https://naturalselectionlabs.github.io/helm-charts |
| Stars/Forks | 2 stars, 0 forks |
| Commits | 84 commits |

---

## 2. 기능 비교

### 2.1 핵심 기능

| 기능 | sb-helm-charts | NSL 차트 |
|------|----------------|----------|
| **기본 배포** | ✅ Deployment | ✅ Deployment |
| **RSSHub 컨테이너** | ✅ diygod/rsshub | ✅ diygod/rsshub |
| **Health Probes** | ✅ /healthz | ✅ (경로 미확인) |
| **Service** | ✅ ClusterIP:1200 | ✅ ClusterIP:80 |
| **Ingress** | ✅ 지원 | ✅ 지원 |

### 2.2 고급 기능

| 기능 | sb-helm-charts | NSL 차트 |
|------|----------------|----------|
| **HPA** | ✅ 지원 | ✅ 지원 (1-10 replicas) |
| **PDB** | ✅ 지원 | ✅ 지원 |
| **NetworkPolicy** | ✅ 지원 | ✅ 지원 (default-deny ingress) |
| **ServiceMonitor** | ✅ 지원 | ✅ 지원 |
| **Pod Security** | ✅ Non-root, drop ALL | ✅ Non-root, PSP 지원 |

### 2.3 외부 의존성

| 의존성 | sb-helm-charts | NSL 차트 |
|--------|----------------|----------|
| **Redis (캐싱)** | ❌ 미지원 (memory only) | ✅ **내장 Redis 컴포넌트** |
| **Puppeteer** | ❌ 미지원 | ✅ **내장 Browserless/Chrome** |
| **외부 Redis 연결** | ⚠️ extraEnv로 설정 | ✅ 기본 지원 |

**주요 차이점:**
- NSL 차트는 Redis와 Puppeteer를 **별도 Pod**로 배포
- sb-helm-charts는 RSSHub만 배포, 외부 서비스 연동 필요

---

## 3. 설정 철학 비교

### sb-helm-charts (Configuration-First)

**장점:**
- RSSHub 앱 자체에 집중
- 외부 의존성 명시적 분리
- 간단한 구조 (단일 Deployment)
- 프로젝트 철학 준수 (설정 파일 우선)

**단점:**
- Redis 캐싱 사용 시 별도 설치 필요
- Puppeteer 필요 시 browserless-chrome 차트 별도 설치
- 다중 컴포넌트 조합 설정 복잡도 증가

**values.yaml 구조:**
```yaml
rsshub:
  cache:
    type: "memory"  # 또는 redis (외부)
  redis:
    url: ""  # 외부 Redis 연결 문자열
  puppeteer:
    wsEndpoint: ""  # 외부 Puppeteer 엔드포인트
```

### NSL 차트 (All-in-One)

**장점:**
- ✅ **즉시 사용 가능** (Redis + Puppeteer 포함)
- ✅ **단일 차트로 완전한 스택 배포**
- ✅ **컴포넌트 간 통합 자동화**
- 프로덕션 환경 바로 적용 가능

**단점:**
- 서브 컴포넌트 제어 제한적
- Redis/Puppeteer 고급 설정 어려움
- 복잡한 아키텍처 (3개 컴포넌트)

**values.yaml 구조 (추정):**
```yaml
rsshub:
  # RSSHub 설정

redis:
  enabled: true  # 내장 Redis 활성화
  image: redis:7.0.7-alpine

puppeteer:
  enabled: true  # 내장 Puppeteer 활성화
  image: browserless/chrome:1.57-puppeteer-13.1.3
```

---

## 4. 아키텍처 비교

### sb-helm-charts 아키텍처

```
┌─────────────────────────────────────────────┐
│ sb-helm-charts RSSHub                       │
│                                             │
│  ┌──────────────────────────────┐          │
│  │ RSSHub Pod                    │          │
│  │ - diygod/rsshub:2025-11-09   │          │
│  │ - Memory Cache (기본)         │          │
│  │ - Port: 1200                  │          │
│  └──────────────────────────────┘          │
└─────────────────────────────────────────────┘
         ↓ (extraEnv 설정 필요)
┌─────────────────────────────────────────────┐
│ 외부 서비스 (별도 설치)                      │
│                                             │
│  ┌─────────────┐   ┌─────────────────────┐ │
│  │ Redis       │   │ browserless-chrome  │ │
│  │ (선택사항)   │   │ (선택사항)           │ │
│  └─────────────┘   └─────────────────────┘ │
└─────────────────────────────────────────────┘
```

**설치 예시:**
```bash
# 1. Redis 설치 (선택사항)
helm install redis ./charts/redis

# 2. Browserless Chrome 설치 (선택사항)
helm install browserless ./charts/browserless-chrome

# 3. RSSHub 설치 (Redis + Puppeteer 연동)
helm install rsshub ./charts/rsshub \
  --set extraEnv[0].name=CACHE_TYPE \
  --set extraEnv[0].value=redis \
  --set extraEnv[1].name=REDIS_URL \
  --set extraEnv[1].value=redis://redis:6379/ \
  --set extraEnv[2].name=PUPPETEER_WS_ENDPOINT \
  --set extraEnv[2].value=ws://browserless:3000
```

### NSL 차트 아키텍처

```
┌─────────────────────────────────────────────┐
│ NSL RSSHub Chart (All-in-One)               │
│                                             │
│  ┌──────────────────────────────┐          │
│  │ RSSHub Pod                    │          │
│  │ - diygod/rsshub:latest        │          │
│  │ - Port: 80                    │          │
│  └──────────────────────────────┘          │
│           ↓ ↑                               │
│  ┌──────────────────────────────┐          │
│  │ Redis Pod                     │          │
│  │ - redis:7.0.7-alpine          │          │
│  │ - Port: 6379                  │          │
│  └──────────────────────────────┘          │
│           ↓ ↑                               │
│  ┌──────────────────────────────┐          │
│  │ Puppeteer Pod                 │          │
│  │ - browserless/chrome          │          │
│  │ - Port: 3000                  │          │
│  └──────────────────────────────┘          │
└─────────────────────────────────────────────┘
```

**설치 예시:**
```bash
# 단일 명령으로 전체 스택 배포
helm repo add nsl https://naturalselectionlabs.github.io/helm-charts
helm install rsshub nsl/rsshub

# Redis + Puppeteer 자동 구성 완료
```

---

## 5. 사용 사례별 권장

### 5.1 개발/테스트 환경

**권장: sb-helm-charts** ✅

**이유:**
- 메모리 캐시로 충분
- 외부 의존성 불필요
- 빠른 배포 및 삭제
- 리소스 최소화

**설치:**
```bash
helm install rsshub ./charts/rsshub
# Memory cache 사용, Redis/Puppeteer 없음
```

### 5.2 프로덕션 환경 (단순 RSS)

**권장: sb-helm-charts + 외부 Redis** ✅

**이유:**
- Redis는 프로덕션급 별도 차트 사용 (Redis Operator 권장)
- Puppeteer 불필요 (정적 RSS만)
- 각 컴포넌트 독립 스케일링
- 운영 유연성 최대화

**설치:**
```bash
# 1. Redis Operator 설치
helm install redis-operator redis-operator/redis-operator

# 2. Redis 인스턴스 생성
kubectl apply -f redis-failover.yaml

# 3. RSSHub 설치 (외부 Redis 연동)
helm install rsshub ./charts/rsshub -f values-prod.yaml
```

### 5.3 프로덕션 환경 (Full Feature)

**권장: NSL 차트** ⚠️

**이유:**
- ✅ Redis + Puppeteer 자동 구성
- ✅ 즉시 사용 가능
- ✅ 단일 차트로 전체 스택 관리
- ⚠️ 단, Redis/Puppeteer 고급 설정 제한적

**대안: sb-helm-charts + 개별 컴포넌트** (추천)
- Redis: Redis Operator 사용
- Puppeteer: browserless-chrome 차트 사용
- RSSHub: sb-helm-charts 사용
- **장점:** 각 컴포넌트 최적화 가능

### 5.4 홈서버 / 소규모 배포

**권장: NSL 차트** ✅

**이유:**
- All-in-One 편의성
- 복잡도 최소화
- 빠른 설정
- 소규모 환경에서 서브 컴포넌트 제어 불필요

---

## 6. 마이그레이션 가이드

### 6.1 sb-helm-charts → NSL 차트

**시나리오:** All-in-One 솔루션 필요

**Step 1: 현재 설정 백업**

```bash
helm get values rsshub -o yaml > rsshub-values-backup.yaml
```

**Step 2: NSL 차트 저장소 추가**

```bash
helm repo add nsl https://naturalselectionlabs.github.io/helm-charts
helm repo update
```

**Step 3: 설정 변환**

```yaml
# sb-helm-charts values.yaml
rsshub:
  cache:
    type: "memory"
  logLevel: "info"

# NSL 차트 values.yaml (추정)
rsshub:
  env:
    - name: LOG_LEVEL
      value: "info"

redis:
  enabled: true  # 내장 Redis 활성화

puppeteer:
  enabled: true  # 내장 Puppeteer 활성화
```

**Step 4: 기존 차트 제거 및 새 차트 설치**

```bash
# 기존 차트 제거
helm uninstall rsshub

# NSL 차트 설치
helm install rsshub nsl/rsshub -f nsL-values.yaml
```

### 6.2 NSL 차트 → sb-helm-charts

**시나리오:** 컴포넌트 독립 관리 필요

**Step 1: 외부 Redis 설치**

```bash
helm install redis ./charts/redis -f redis-values.yaml
```

**Step 2: Browserless Chrome 설치 (선택사항)**

```bash
helm install browserless ./charts/browserless-chrome
```

**Step 3: RSSHub 설치 (외부 서비스 연동)**

```bash
helm install rsshub ./charts/rsshub \
  --set rsshub.cache.type=redis \
  --set rsshub.redis.url=redis://redis:6379/ \
  --set rsshub.puppeteer.wsEndpoint=ws://browserless:3000
```

**Step 4: NSL 차트 제거**

```bash
helm uninstall rsshub-nsl
```

---

## 7. 결론 및 권장사항

### 7.1 최종 권장

| 환경 | 권장 차트 | 이유 |
|------|-----------|------|
| **개발/테스트** | sb-helm-charts | 단순성, 리소스 최소화 |
| **프로덕션 (단순)** | sb-helm-charts + 외부 Redis | 독립 스케일링, 운영 유연성 |
| **프로덕션 (Full)** | sb-helm-charts + 개별 컴포넌트 | 최적화, 고급 설정 |
| **홈서버 / 소규모** | NSL 차트 | All-in-One 편의성 |

### 7.2 sb-helm-charts 유지 권장 이유

1. **프로젝트 철학 준수**
   - Configuration-first 접근
   - 외부 의존성 명시적 분리
   - 설정 파일 우선 (extraEnv 활용)

2. **운영 유연성**
   - Redis: Redis Operator로 HA 구성 가능
   - Puppeteer: browserless-chrome 차트로 독립 스케일링
   - 각 컴포넌트 버전 독립 관리

3. **프로덕션 최적화**
   - Redis: Sentinel/Cluster 구성
   - Puppeteer: GPU 지원, 멀티 인스턴스
   - RSSHub: CPU/메모리 독립 튜닝

### 7.3 NSL 차트 사용 고려 시점

1. **빠른 프로토타이핑**
   - 즉시 사용 가능한 전체 스택 필요
   - 설정 최소화 우선

2. **소규모 배포**
   - 홈서버, 개인 프로젝트
   - 운영 복잡도 최소화

3. **임시 환경**
   - 데모, 테스트 배포
   - 일회성 사용

### 7.4 액션 아이템

**sb-helm-charts RSSHub 개선:**
- [x] README에 외부 차트 참조 추가
- [ ] Redis 연동 가이드 추가 (values-example.yaml)
- [ ] Puppeteer 연동 가이드 추가
- [ ] 프로덕션 배포 아키텍처 다이어그램

**문서화:**
- [x] 차트 비교 문서 작성 (본 문서)
- [ ] CLAUDE.md에 권장사항 업데이트
- [ ] 01-official-charts-analysis.md 업데이트

---

## 8. 참조

- [NaturalSelectionLabs Helm Charts](https://github.com/NaturalSelectionLabs/helm-charts)
- [RSSHub 공식 문서](https://docs.rsshub.app/)
- [sb-helm-charts RSSHub](../charts/rsshub/)
- [sb-helm-charts Redis](../charts/redis/)
- [sb-helm-charts Browserless Chrome](../charts/browserless-chrome/)

---

## 9. 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|----------|
| 2025-01-14 | 1.0 | 초안 작성 - 자체 차트 vs NSL 차트 비교 분석 |
