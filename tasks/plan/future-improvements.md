# 향후 개선 작업 목록

**생성일**: 2025-11-25
**범위**: v1.2.0 이후 또는 병렬 진행 가능한 작업

---

## 1. 문서화 작업

### 1.1 Security Hardening Guide
**파일**: `docs/SECURITY_HARDENING_GUIDE.md`
**복잡도**: Medium
**내용**:
- Pod Security Standards (PSS) 적용 가이드
- Network Policy 템플릿 및 패턴
- RBAC 최소 권한 원칙
- Secret 암호화 및 rotation
- Container hardening (non-root, capabilities)
- Image 보안 (signing, scanning)
- Audit logging 설정

### 1.2 Observability Stack Guide
**파일**: `docs/OBSERVABILITY_STACK_GUIDE.md`
**복잡도**: Medium
**내용**:
- Prometheus + Loki + Tempo + Mimir 통합 배포
- 데이터 흐름 아키텍처
- Grafana 데이터소스 설정
- 통합 대시보드 구성
- 알림 파이프라인

### 1.3 Multi-Tenancy Guide
**파일**: `docs/MULTI_TENANCY_GUIDE.md`
**복잡도**: Medium
**내용**:
- 네임스페이스 기반 격리
- ResourceQuota 설정
- Network Policy로 테넌트 분리
- Mimir/Loki 멀티테넌시
- RBAC 테넌트별 권한

### 1.4 Upgrade Guide
**파일**: `docs/UPGRADE_GUIDE.md`
**복잡도**: Simple
**내용**:
- 일반 업그레이드 절차
- Breaking changes 체크리스트
- 롤백 절차
- 데이터 백업/복구

---

## 2. 신규 차트

### 2.1 Consul Chart
**우선순위**: Low
**복잡도**: Complex
**용도**:
- Service discovery
- Service mesh (Connect)
- KV store
- Configuration management

### 2.2 Vector Chart
**우선순위**: Medium
**복잡도**: Medium
**용도**:
- Promtail 대안
- 로그/메트릭 통합 수집
- 변환 파이프라인
- 다중 백엔드 지원

### 2.3 Thanos Chart
**우선순위**: Low
**복잡도**: Complex
**용도**:
- Prometheus HA 대안
- Global query view
- 장기 저장소 (S3)
- Downsampling

### 2.4 Jaeger Chart
**우선순위**: Low
**복잡도**: Medium
**용도**:
- Tempo 대안
- 분산 트레이싱
- Cassandra/Elasticsearch 백엔드

---

## 3. 대시보드 확장

### 3.1 차트별 개별 대시보드
```
dashboards/
├── existing/
│   ├── prometheus-overview.json
│   ├── loki-overview.json
│   ├── tempo-overview.json
│   └── kubernetes-cluster.json
├── charts/
│   ├── keycloak-dashboard.json
│   ├── postgresql-dashboard.json
│   ├── kafka-dashboard.json
│   ├── elasticsearch-dashboard.json
│   └── redis-dashboard.json
└── slo/
    ├── slo-overview.json
    └── error-budget.json
```

### 3.2 SLO/SLI 대시보드
**내용**:
- Availability SLO
- Latency SLO (p50, p95, p99)
- Error budget tracking
- Burn rate 알림

### 3.3 비용 모니터링 대시보드
**내용**:
- 리소스 사용량 추이
- 네임스페이스별 비용 추정
- 노드 효율성
- Spot instance 활용률

---

## 4. 알림 규칙 확장

### 4.1 차트별 알림 규칙
```
alerting-rules/
├── existing/
│   ├── prometheus-alerts.yaml
│   ├── kubernetes-alerts.yaml
│   ├── loki-alerts.yaml
│   ├── tempo-alerts.yaml
│   └── mimir-alerts.yaml
├── charts/
│   ├── keycloak-alerts.yaml
│   ├── postgresql-alerts.yaml
│   ├── kafka-alerts.yaml
│   └── elasticsearch-alerts.yaml
└── slo/
    └── slo-alerts.yaml
```

### 4.2 SLO 기반 알림
**내용**:
- Multi burn rate alerts
- Error budget exhaustion
- SLO breach prediction

---

## 5. 운영 개선

### 5.1 Makefile 확장
**파일**: `make/ops/` 하위
**내용**:
- 신규 차트용 명령어
- 통합 배포 명령어
- 백업/복구 자동화

### 5.2 CI/CD 개선
**내용**:
- GitHub Actions 워크플로우 개선
- Chart testing (ct) 통합
- 자동 버전 범핑
- Release notes 자동 생성

### 5.3 Helm Unittest 도입
**파일**: `tests/` 또는 각 차트 `templates/tests/`
**내용**:
- 템플릿 유닛 테스트
- values 조합 테스트
- Regression 방지

---

## 6. Major Version Migrations

### 6.1 Immich v2
**브랜치**: `feature/immich-v2`
**현재**: 1.122.3 → **목표**: 2.3.1
**Breaking Changes**:
- API 변경
- 환경 변수 변경
- DB 마이그레이션

### 6.2 Airflow v3
**브랜치**: `feature/airflow-v3`
**현재**: 2.8.1 → **목표**: 3.1.3
**Breaking Changes**:
- 새로운 executor 모델
- DAG 포맷 변경
- Provider 패키지 구조

### 6.3 MLflow v3
**브랜치**: `feature/mlflow-v3`
**현재**: 2.9.2 → **목표**: 3.6.0
**요구사항**:
- Python 3.10+
- 새로운 API

### 6.4 pgAdmin v9
**브랜치**: `feature/pgadmin-v9`
**현재**: 8.13 → **목표**: 9.10
**변경사항**:
- UI 변경
- 새로운 기능

---

## 7. 품질 개선

### 7.1 차트 표준화
- [ ] 모든 차트 values.yaml 구조 통일
- [ ] 공통 헬퍼 함수 정리
- [ ] 라벨/어노테이션 표준화
- [ ] 리소스 기본값 검토

### 7.2 문서 품질
- [ ] 모든 README에 Prerequisites 섹션
- [ ] 모든 README에 Troubleshooting 섹션
- [ ] 예제 values 파일 검증
- [ ] 스크린샷/다이어그램 추가

### 7.3 보안 검토
- [ ] 모든 차트 SecurityContext 검토
- [ ] 기본값으로 non-root 실행
- [ ] read-only rootFilesystem 적용
- [ ] capabilities drop 확인

---

## 작업 우선순위 매트릭스

| 작업 | 영향도 | 복잡도 | 우선순위 |
|------|--------|--------|----------|
| OpenTelemetry Collector | High | Complex | **1** |
| Security Hardening Guide | High | Medium | **2** |
| Vault Integration | Medium | Medium | **3** |
| Immich v2 Migration | Medium | Medium | **4** |
| SLO Dashboards | Medium | Medium | 5 |
| Vector Chart | Medium | Medium | 6 |
| 차트별 대시보드 | Low | Simple | 7 |
| Consul Chart | Low | Complex | 8 |

---

## 참고

이 문서는 향후 작업 계획을 위한 참고 자료입니다.
실제 구현 시 최신 버전 및 요구사항을 확인하세요.
