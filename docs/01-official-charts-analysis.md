# 오피셜 Helm 차트 사용 권장 목록

## 핵심 원칙

> **"앱 특화 설정이 많고 단순한 구조면 자체 제작, 범용 인프라이거나 복잡한 분산 시스템이면 오피셜 차트"**

---

## 1. 오피셜 차트 권장 목록

### 데이터베이스

| 소프트웨어 | 차트 저장소 |
|-----------|------------|
| PostgreSQL | [CloudNativePG](https://github.com/cloudnative-pg/charts) |
| MySQL | [Percona Operator](https://github.com/percona/percona-server-mysql-operator) |
| MariaDB | [MariaDB Operator](https://github.com/mariadb-operator/mariadb-operator) |
| Redis | [Redis Operator](https://github.com/spotahome/redis-operator) |
| MongoDB | [MongoDB Community Operator](https://github.com/mongodb/mongodb-kubernetes-operator) |

### 메시징 & 캐싱

| 소프트웨어 | 차트 저장소 |
|-----------|------------|
| RabbitMQ | [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator) |
| Memcached | [Memcached Operator](https://github.com/ianlewis/memcached-operator) |
| Kafka | [Strimzi Kafka Operator](https://strimzi.io/) |
| NATS | [NATS Helm Charts](https://github.com/nats-io/k8s) |

### 모니터링 & 로깅

| 소프트웨어 | 차트 저장소 | 비고 |
|-----------|------------|------|
| Prometheus | [Prometheus Community](https://github.com/prometheus-community/helm-charts) | |
| Grafana | [Grafana Helm Charts](https://github.com/grafana/helm-charts) | |
| Loki | [Grafana Loki](https://github.com/grafana/helm-charts/tree/main/charts/loki) | |
| Thanos | [Stevehipwell Thanos](https://github.com/stevehipwell/helm-charts/tree/main/charts/thanos) | ⚠️ Bitnami 차트는 2025년 8월 정책 변경 |
| Elastic Stack | [Elastic Helm Charts](https://github.com/elastic/helm-charts) | |

### 인그레스 & 네트워킹

| 소프트웨어 | 차트 저장소 |
|-----------|------------|
| NGINX Ingress | [Kubernetes Ingress NGINX](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx) |
| Traefik | [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart) |
| cert-manager | [cert-manager](https://github.com/cert-manager/cert-manager/tree/master/deploy/charts/cert-manager) |
| MetalLB | [MetalLB](https://github.com/metallb/metallb/tree/main/charts/metallb) |

### 보안 & 인증

| 소프트웨어 | 차트 저장소 | 비고 |
|-----------|------------|------|
| HashiCorp Vault | [HashiCorp Vault](https://github.com/hashicorp/vault-helm) | |
| external-secrets | [External Secrets Operator](https://github.com/external-secrets/external-secrets/tree/main/deploy/charts/external-secrets) | |
| Keycloak | - | ⚠️ 자체 제작 유지 (앱 특화 설정 많음) |

### CI/CD

| 소프트웨어 | 차트 저장소 |
|-----------|------------|
| ArgoCD | [Argo CD](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd) |
| GitLab | [GitLab Helm Charts](https://gitlab.com/gitlab-org/charts/gitlab) |
| Jenkins | [Jenkins Helm Charts](https://github.com/jenkinsci/helm-charts) |

### 오브젝트 스토리지

| 소프트웨어 | 차트 저장소 | 판단 |
|-----------|------------|------|
| MinIO | [MinIO Official](https://github.com/minio/minio/tree/master/helm/minio) | 프로덕션 안정성 우선 시 |
| RustFS | - | ⚠️ 자체 제작 (Alpha 단계, 홈서버/실험용) |
| Ceph | [Rook Operator](https://rook.io/) | 복잡한 분산 스토리지 |

### 기타

| 소프트웨어 | 차트 저장소 |
|-----------|------------|
| Cassandra | [K8ssandra](https://github.com/k8ssandra/k8ssandra) |
| Consul | [HashiCorp Consul](https://github.com/hashicorp/consul-k8s/tree/main/charts/consul) |

---

## 2. 판단 기준

### 자체 제작 조건 (모두 만족 시)

- [ ] 앱 특화 설정이 많음
- [ ] 오피셜 차트가 설정 파일을 과도하게 추상화
- [ ] 간단한 Deployment/StatefulSet 구조
- [ ] 서브차트 의존성 최소
- [ ] 프로젝트 철학(설정 파일 우선)에 부합

### 오피셜 차트 사용 (하나라도 해당 시)

- [ ] 범용 인프라 컴포넌트
- [ ] 복잡한 클러스터링/분산 시스템
- [ ] CRD/Operator 기반 아키텍처
- [ ] 보안 크리티컬 컴포넌트
- [ ] 서브차트 의존성이 많음
- [ ] 운영 복잡도 > 설정 복잡도

### 유명 차트 비사용 조건 (하나라도 해당 시)

- [ ] 유료화 또는 라이센스 제약
- [ ] 커뮤니티 버전 기능 제한
- [ ] 상업적 이용 제한

---

## 3. 현재 프로젝트 차트 평가

### 자체 제작 유지 (권장)

| 차트 | 이유 |
|------|------|
| keycloak | 앱 특화 설정, PostgreSQL SSL, realm 관리 |
| wordpress | wp-config.php 직접 마운트, wp-cli 통합 |
| nextcloud | config.php 직접 관리, LinuxServer.io 이미지 |
| wireguard | wg0.conf 직접 마운트, 오피셜 차트 없음 |
| rustfs | 티어드 스토리지, 홈서버 최적화, Alpha 단계 |
| browserless-chrome | 오피셜 차트 없음 |
| devpi | 오피셜 차트 없음 |

### 오피셜 차트 전환 고려

| 차트 | 이유 | 권장 조치 |
|------|------|----------|
| redis | 범용 인프라, Sentinel/Cluster 미지원 | [Redis Operator](https://github.com/spotahome/redis-operator) |
| rabbitmq | 복잡한 클러스터링, 플러그인 관리 | [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator) |
| memcached | 범용 캐시 컴포넌트 | [Memcached Operator](https://github.com/ianlewis/memcached-operator) |

### 외부 차트 참조

| 차트 | 권장 조치 | 권장 대상 |
|------|----------|----------|
| rsshub | [NaturalSelectionLabs RSSHub](https://github.com/NaturalSelectionLabs/helm-charts/tree/main/charts/rsshub) 참조 | 홈서버, All-in-One 솔루션 |

**RSSHub 차트 선택 가이드:**
- **NSL 차트 권장**: 홈서버, 소규모 배포, 빠른 프로토타이핑 (Redis + Puppeteer 내장)
- **자체 차트 권장**: 프로덕션, 컴포넌트 독립 관리, 외부 Redis Operator 연동
- **상세 비교**: [docs/04-rsshub-chart-comparison.md](./04-rsshub-chart-comparison.md)

---

## 4. Decision Framework

```
1. 오피셜 차트 존재?
   ├─ 없음 → 자체 제작
   └─ 있음 → 2번

2. 복잡도 평가
   ├─ 분산/클러스터링/CRD/Operator → 오피셜 사용
   └─ 단순 Deployment → 3번

3. 설정 방식 평가
   ├─ 범용 인프라 → 오피셜 사용
   ├─ 설정 파일 잘 보존 → 오피셜 사용
   └─ 과도하게 추상화 → 4번

4. 프로젝트 철학 부합도
   ├─ 설정 파일 직접 마운트 가능 → 자체 제작 고려
   ├─ 앱 특화 도구 필요 → 자체 제작 고려
   └─ 간단한 ConfigMap → 자체 제작 가능

5. 유지보수 부담
   ├─ 업스트림 변경 빈번 → 오피셜 사용
   └─ 안정적인 구조 → 자체 제작 가능
```

---

## 5. 신규 차트 추가 시

1. 오피셜 차트 우선 검토: [Artifact Hub](https://artifacthub.io/), [CNCF](https://www.cncf.io/projects/)
2. Decision Framework 적용
3. 자체 제작 시 README에 근거 명시

---

## 참조

- [Artifact Hub](https://artifacthub.io/)
- [CNCF Projects](https://www.cncf.io/projects/)
- [Kubernetes Operators](https://operatorhub.io/)
- [CloudNativePG](https://cloudnative-pg.io/)
- [Strimzi Kafka Operator](https://strimzi.io/)
- [K8ssandra](https://k8ssandra.io/)
