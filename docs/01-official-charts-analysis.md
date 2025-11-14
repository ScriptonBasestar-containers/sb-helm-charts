# 오피셜 Helm 차트 사용 권장 목록

## 문서 개요

이 문서는 ScriptonBasestar Helm Charts 프로젝트에서 **자체 제작하지 않고 오피셜 차트를 사용하는 것이 권장되는** 소프트웨어 목록과 그 판단 기준을 정리합니다.

---

## 1. 오피셜 차트 사용 권장 목록

### 1.1 데이터베이스 (Databases)

| 소프트웨어 | 차트 저장소 | 권장 이유 |
|-----------|------------|----------|
| **PostgreSQL** | [CloudNativePG](https://github.com/cloudnative-pg/charts) | ✅ CNCF Sandbox 프로젝트<br>✅ Operator 기반 HA, 복제, 백업 지원<br>✅ 복잡한 데이터베이스 운영 로직 |
| **MySQL** | [Percona Operator](https://github.com/percona/percona-server-mysql-operator) | ✅ 복제, 클러스터링 자동화<br>✅ Percona MySQL 공식 Operator<br>✅ 복잡한 초기화 스크립트 관리 |
| **MariaDB** | [MariaDB Operator](https://github.com/mariadb-operator/mariadb-operator) | ✅ Galera 클러스터 지원<br>✅ Primary-Secondary 복제 자동화 |
| **Redis** | [Redis Operator](https://github.com/spotahome/redis-operator) | ✅ Sentinel, Cluster 모드 지원<br>✅ 복잡한 복제 토폴로지 관리 |
| **MongoDB** | [MongoDB Community Operator](https://github.com/mongodb/mongodb-kubernetes-operator) | ✅ 공식 Operator<br>✅ Replica Set, Sharding 지원 |

**프로젝트 철학 부합도**: ⭐⭐⭐⭐⭐ (완벽)
- 데이터베이스는 **항상 외부 의존성**으로 관리 (서브차트 금지)
- 복잡한 클러스터링/복제 로직은 오피셜 차트가 더 안정적
- 설정 파일 추상화보다 운영 안정성이 우선

---

### 1.2 메시징 & 캐싱 (Messaging & Caching)

| 소프트웨어 | 차트 저장소 | 권장 이유 |
|-----------|------------|----------|
| **RabbitMQ** | [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator) | ✅ 공식 Operator<br>✅ 클러스터링, 쿼럼 큐 자동 구성<br>✅ 복잡한 플러그인 생태계 |
| **Memcached** | [Memcached Operator](https://github.com/ianlewis/memcached-operator) | ✅ Operator 기반 관리<br>✅ 커넥션 풀링, 메모리 관리 |
| **Apache Kafka** | [Strimzi Kafka Operator](https://strimzi.io/) | ✅ CNCF Sandbox 프로젝트<br>✅ ZooKeeper/KRaft 모드 모두 지원<br>✅ 매우 복잡한 분산 시스템 |
| **NATS** | [NATS Helm Charts](https://github.com/nats-io/k8s) | ✅ 공식 차트, JetStream 지원<br>✅ 클러스터 모드 설정 복잡 |

**프로젝트 철학 부합도**: ⭐⭐⭐⭐⭐ (완벽)
- 범용 인프라 컴포넌트 (앱 특화 설정 없음)
- 클러스터링/분산 시스템 운영 복잡도 높음
- 이미 프로젝트의 keycloak, nextcloud 등이 외부 Redis 사용 전제

**⚠️ 현재 프로젝트 상태**:
- `charts/redis/`, `charts/rabbitmq/`, `charts/memcached/` 존재 (v0.1.0)
- 이들은 오피셜 차트로 대체 고려 필요 (섹션 3 참조)

---

### 1.3 모니터링 & 로깅 (Monitoring & Logging)

| 소프트웨어 | 차트 저장소 | 권장 이유 |
|-----------|------------|----------|
| **Prometheus** | [Prometheus Community](https://github.com/prometheus-community/helm-charts) | ✅ 공식 커뮤니티 차트<br>✅ Operator, Adapter, Alertmanager 통합<br>✅ kube-prometheus-stack 권장 |
| **Grafana** | [Grafana Helm Charts](https://github.com/grafana/helm-charts) | ✅ 공식 차트<br>✅ 대시보드 프로비저닝 자동화<br>✅ 플러그인 관리 복잡 |
| **Loki** | [Grafana Loki](https://github.com/grafana/helm-charts/tree/main/charts/loki) | ✅ 공식 차트<br>✅ 분산 모드, S3 백엔드 지원 |
| **Elastic Stack** | [Elastic Helm Charts](https://github.com/elastic/helm-charts) | ✅ 공식 차트<br>✅ Elasticsearch 클러스터링 매우 복잡<br>✅ Kibana, Logstash, Beats 통합 |

**프로젝트 철학 부합도**: ⭐⭐⭐⭐⭐ (완벽)
- 복잡한 분산 시스템 (특히 Elasticsearch)
- 앱 특화 설정보다 인프라 운영 로직 중심
- 자체 제작 시 유지보수 부담 매우 큼

---

### 1.4 인그레스 & 네트워킹 (Ingress & Networking)

| 소프트웨어 | 차트 저장소 | 권장 이유 |
|-----------|------------|----------|
| **NGINX Ingress** | [Kubernetes Ingress NGINX](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx) | ✅ Kubernetes 공식 프로젝트<br>✅ 복잡한 Lua 스크립트, 플러그인 관리 |
| **Traefik** | [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart) | ✅ 공식 차트<br>✅ 동적 설정, 미들웨어 관리 복잡 |
| **cert-manager** | [cert-manager](https://github.com/cert-manager/cert-manager/tree/master/deploy/charts/cert-manager) | ✅ CNCF 프로젝트 공식 차트<br>✅ ACME, Vault, Venafi 통합<br>✅ CRD 기반 복잡한 아키텍처 |
| **MetalLB** | [MetalLB](https://github.com/metallb/metallb/tree/main/charts/metallb) | ✅ 공식 차트<br>✅ L2/BGP 모드 네트워크 설정 복잡 |

**프로젝트 철학 부합도**: ⭐⭐⭐⭐⭐ (완벽)
- 클러스터 레벨 인프라 컴포넌트
- 앱 수준의 간단한 설정이 아님
- Kubernetes API 깊숙한 통합 필요

---

### 1.5 보안 & 인증 (Security & Authentication)

| 소프트웨어 | 차트 저장소 | 권장 이유 |
|-----------|------------|----------|
| **HashiCorp Vault** | [HashiCorp Vault](https://github.com/hashicorp/vault-helm) | ✅ 공식 차트<br>✅ HA, Raft 스토리지, unsealing 복잡<br>✅ 보안 크리티컬 컴포넌트 |
| **external-secrets** | [External Secrets Operator](https://github.com/external-secrets/external-secrets/tree/main/deploy/charts/external-secrets) | ✅ CNCF Sandbox 프로젝트<br>✅ CRD 기반, Vault/AWS/GCP 통합 |

**프로젝트 철학 부합도**: ⭐⭐⭐⭐ (매우 적합)
- 보안 컴포넌트는 검증된 구현 필수
- 자체 제작 시 보안 리스크 높음

**⚠️ 예외**: Keycloak은 **자체 제작 유지 권장**
- 이유: 앱 특화 설정이 많고, 프로젝트에서 상세 튜닝 필요
- 현재 차트 (v0.3.0) 완성도 높음 (PostgreSQL SSL, clustering 지원)

---

### 1.6 CI/CD

| 소프트웨어 | 차트 저장소 | 권장 이유 |
|-----------|------------|----------|
| **ArgoCD** | [Argo CD](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd) | ✅ 공식 차트<br>✅ GitOps 워크플로우 복잡<br>✅ SSO, RBAC 통합 많음 |
| **GitLab** | [GitLab Helm Charts](https://gitlab.com/gitlab-org/charts/gitlab) | ✅ 공식 차트<br>✅ 매우 복잡한 서브차트 구조<br>✅ 자체 제작 불가능한 수준 |
| **Jenkins** | [Jenkins Helm Charts](https://github.com/jenkinsci/helm-charts) | ✅ 공식 차트<br>✅ 플러그인 관리, 에이전트 설정 복잡 |

**프로젝트 철학 부합도**: ⭐⭐⭐⭐⭐ (완벽)
- 매우 복잡한 서브차트 구조 (특히 GitLab)
- 앱 특화 설정보다 운영 복잡도가 핵심
- 자체 제작 시 유지보수 불가능

---

### 1.7 Object Storage (오브젝트 스토리지)

| 소프트웨어 | 차트 저장소 | 판단 | 권장 이유 |
|-----------|------------|------|----------|
| **MinIO** | [MinIO Official](https://github.com/minio/minio/tree/master/helm/minio) | ⚖️ 상황 판단 | ✅ 공식 차트, 엔터프라이즈 지원<br>✅ 안정적인 프로덕션 사용<br>⚠️ 라이센스 변경 (AGPLv3 → 독점)<br>⚠️ 설정 복잡도 높음 |
| **RustFS** | [공식 차트](https://github.com/rustfs/rustfs/tree/main/helm) | ⚠️ 자체 제작 권장 | ⚠️ Alpha 단계 (v1.0.0-alpha.66)<br>⚠️ 프로덕션 미권장 (공식 경고)<br>✅ 공식 차트는 기본 기능만 제공<br>✅ 프로젝트 철학 부합 (설정 파일 우선)<br>✅ 티어드 스토리지 등 고급 기능 필요 |
| **Ceph** | [Rook Operator](https://rook.io/) | ✅ 오피셜 사용 | ✅ CNCF Graduated 프로젝트<br>✅ 매우 복잡한 분산 스토리지<br>✅ Operator 필수 |
| **SeaweedFS** | [SeaweedFS Helm](https://github.com/seaweedfs/seaweedfs/tree/master/k8s/charts/seaweedfs) | ⚖️ 상황 판단 | ✅ 공식 차트 존재<br>⚠️ 설정 복잡도 중간<br>⚠️ 커뮤니티 크기 작음 |

**프로젝트 철학 부합도**: ⭐⭐⭐ (중간)

**RustFS 자체 제작 근거**:
1. **Alpha 소프트웨어**: 공식 차트도 기본 기능만 제공, 프로덕션 안정성 부족
2. **설정 파일 우선**: 프로젝트 철학에 완벽히 부합
3. **고급 기능 필요**:
   - Tiered Storage (Hot SSD + Cold HDD)
   - 홈서버/스타트업 최적화 설정
   - Production features (NetworkPolicy, PDB, ServiceMonitor)
4. **학습 기회**: 분산 스토리지 패턴 구현 경험

**MinIO vs RustFS 선택 기준**:
- **프로덕션 안정성 우선** → MinIO 공식 차트
- **학습 및 실험** → RustFS 자체 차트
- **홈서버/NAS** → RustFS 자체 차트 (리소스 최적화)
- **엔터프라이즈 지원 필요** → MinIO 공식 차트

---

### 1.8 기타 복잡한 분산 시스템

| 소프트웨어 | 차트 저장소 | 권장 이유 |
|-----------|------------|----------|
| **Cassandra** | [K8ssandra](https://github.com/k8ssandra/k8ssandra) | ✅ CNCF Sandbox 프로젝트<br>✅ Operator 기반 복잡한 분산 데이터베이스<br>✅ 노드 관리, 백업, 복구 자동화 |
| **Consul** | [HashiCorp Consul](https://github.com/hashicorp/consul-k8s/tree/main/charts/consul) | ✅ 공식 차트<br>✅ 서비스 메시, 분산 KV 복잡 |

---

## 2. 자체 제작 vs 오피셜 차트 판단 기준

### 2.1 자체 제작이 적절한 경우

다음 **모든** 조건을 만족할 때만 자체 제작 고려:

- [ ] **앱 특화 설정**이 많음 (범용 인프라가 아님)
- [ ] 오피셜 차트가 **설정 파일을 과도하게 추상화**함
- [ ] **간단한 Deployment/StatefulSet** 구조 (복잡한 클러스터링 없음)
- [ ] **서브차트 의존성**이 없거나 최소화 가능
- [ ] 프로젝트 철학 (설정 파일 우선)에 **완벽히 부합**

**현재 프로젝트 자체 제작 차트 (유지 권장)**:
- ✅ **Keycloak**: 앱 특화 설정 많음, PostgreSQL SSL, realm 관리
- ✅ **WordPress**: wp-config.php 직접 마운트, wp-cli 통합
- ✅ **Nextcloud**: config.php 직접 관리, LinuxServer.io 이미지
- ✅ **WireGuard**: wg0.conf 직접 마운트, NET_ADMIN capabilities
- ✅ **RustFS**: 티어드 스토리지, 홈서버/스타트업 최적화, Alpha 소프트웨어
- ✅ **browserless-chrome**: 오피셜 차트 없음
- ✅ **devpi**: 오피셜 차트 없음

---

### 2.2 오피셜 차트 사용이 적절한 경우

다음 **하나라도** 해당하면 오피셜 차트 사용:

- [ ] **범용 인프라 컴포넌트** (데이터베이스, 캐시, 메시징)
- [ ] **복잡한 클러스터링/분산** 시스템
- [ ] **CRD/Operator 기반** 아키텍처
- [ ] **보안 크리티컬** 컴포넌트 (Vault, cert-manager)
- [ ] **서브차트 의존성**이 매우 많음 (GitLab, Elastic Stack)
- [ ] **운영 복잡도**가 설정 복잡도보다 큼

### 2.3 유명 차트를 사용하지 않는 경우

다음 **하나라도** 해당하면 유명 차트를 사용하지 않음:

- [ ] **유료화** 되었거나 라이센스 제약이 심한 경우 (예: Bitnami 엔터프라이즈 전환)
- [ ] **라이센스 정책**이 개인/소규모 프로젝트에 부담스러운 경우
- [ ] **커뮤니티 버전 제한**으로 필수 기능 사용 불가
- [ ] **상업적 이용 제한**이 있는 경우

**참고**: Bitnami는 최근 엔터프라이즈 중심으로 전환하면서 일부 차트가 유료화되었습니다. 이러한 경우 커뮤니티 버전을 찾거나 자체 제작을 고려합니다.

---

### 2.4 Decision Framework 체크리스트

신규 차트 추가 시 다음 순서로 판단:

```
1. 오피셜 차트 존재 여부 확인
   ├─ 없음 → 자체 제작
   └─ 있음 → 2번으로

2. 복잡도 평가
   ├─ 분산 시스템/클러스터링 → 오피셜 차트 사용
   ├─ CRD/Operator 기반 → 오피셜 차트 사용
   └─ 단순 Deployment → 3번으로

3. 설정 방식 평가
   ├─ 범용 인프라 (DB, 캐시 등) → 오피셜 차트 사용
   ├─ 오피셜 차트가 설정 파일 잘 보존 → 오피셜 차트 사용
   └─ 오피셜 차트가 과도하게 추상화 → 4번으로

4. 프로젝트 철학 부합도 평가
   ├─ 설정 파일 직접 마운트 가능 → 자체 제작 고려
   ├─ 앱 특화 운영 도구 필요 (wp-cli, kc-cli) → 자체 제작 고려
   └─ 간단한 ConfigMap 수준 → 자체 제작 가능

5. 유지보수 부담 평가
   ├─ 업스트림 변경 빈번 → 오피셜 차트 사용
   └─ 안정적인 설정 구조 → 자체 제작 가능
```

---

## 3. 현재 프로젝트 차트 평가

### 3.1 자체 제작 차트 (유지 권장)

| 차트 | 버전 | 평가 | 권장 조치 |
|------|------|------|----------|
| **keycloak** | v0.3.0 | ✅ 완성도 높음<br>PostgreSQL SSL, clustering 지원 | 유지 |
| **wordpress** | v0.1.0 | ✅ wp-config.php 직접 마운트<br>wp-cli 통합 | 유지 |
| **nextcloud** | v0.1.0 | ✅ config.php 직접 관리<br>LinuxServer.io 이미지 | 유지 |
| **wireguard** | v0.1.0 | ✅ wg0.conf 직접 마운트<br>오피셜 차트 없음 | 유지 |
| **rustfs** | v0.1.0 | ✅ 티어드 스토리지 지원<br>✅ 홈서버/스타트업 최적화<br>⚠️ Alpha 소프트웨어 | 유지 (학습/실험 목적)<br>프로덕션: MinIO 검토 |
| **browserless-chrome** | - | ✅ 오피셜 차트 없음 | 유지 |
| **devpi** | - | ✅ 오피셜 차트 없음 | 유지 |
| **rsshub** | v0.1.0 | ⚠️ 외부 차트 참조 권장 | [RSSHub 차트](https://github.com/NaturalSelectionLabs/helm-charts/tree/main/charts/rsshub) 검토 |

---

### 3.2 인프라 차트 (오피셜 차트 전환 고려)

| 차트 | 버전 | 문제점 | 권장 조치 |
|------|------|--------|----------|
| **redis** | v0.1.0 | ❌ 범용 인프라 컴포넌트<br>❌ Sentinel/Cluster 미지원<br>❌ Operator 기반 차트 권장 | [Redis Operator](https://github.com/spotahome/redis-operator) 검토 |
| **rabbitmq** | v0.1.0 | ❌ 복잡한 클러스터링 로직<br>❌ 플러그인 관리 복잡<br>❌ 공식 Operator 권장 | [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator) 검토 |
| **memcached** | v0.1.0 | ❌ 범용 캐시 컴포넌트<br>❌ Operator 기반 관리 권장 | [Memcached Operator](https://github.com/ianlewis/memcached-operator) 검토 |

**프로젝트 철학 부합도**: ⭐⭐ (부합하지 않음)
- 이들은 **범용 인프라**로서 앱 특화 설정이 없음
- 프로젝트가 추구하는 "설정 파일 보존"의 대상이 아님
- 복잡한 클러스터링 로직은 오피셜 차트가 훨씬 안정적

---

## 4. 실행 권장사항

### 4.1 신규 차트 추가 시

1. **오피셜 차트 우선 검토**
   - Artifact Hub: https://artifacthub.io/
   - CNCF 프로젝트: https://www.cncf.io/projects/
   - 공식 Operator/차트 저장소

2. **Decision Framework 적용** (섹션 2.4 참조)

3. **자체 제작 시 문서화 필수**
   - `charts/{name}/README.md`에 "왜 자체 제작했는지" 명시
   - 오피셜 차트와의 차이점 설명

---

## 5. 요약

### 핵심 원칙

> **"앱 특화 설정이 많고 단순한 구조면 자체 제작, 범용 인프라이거나 복잡한 분산 시스템이면 오피셜 차트"**

### 자체 제작 vs 오피셜 차트 한눈에 보기

| 분류 | 자체 제작 | 오피셜 차트 |
|------|----------|------------|
| **앱 특화 설정** | WordPress, Nextcloud, Keycloak | - |
| **범용 인프라** | - | CloudNativePG, Percona, Redis Operator |
| **복잡한 분산 시스템** | - | Strimzi (Kafka), Elasticsearch, GitLab |
| **클러스터링** | Keycloak (앱 특화) | RabbitMQ Operator, Redis Operator |
| **CRD/Operator 기반** | - | cert-manager, ArgoCD |
| **보안 크리티컬** | - | Vault, external-secrets |

### 현재 프로젝트 상태

- ✅ **자체 제작 유지**: keycloak, wordpress, nextcloud, wireguard, browserless-chrome, devpi
- ⚠️ **오피셜 차트 전환 고려**: redis, rabbitmq, memcached
- 📝 **외부 차트 참조**: rsshub

---

## 참조

- [Artifact Hub](https://artifacthub.io/)
- [CNCF Projects](https://www.cncf.io/projects/)
- [Kubernetes Operators](https://operatorhub.io/)
- [CloudNativePG](https://cloudnative-pg.io/)
- [Strimzi Kafka Operator](https://strimzi.io/)
- [K8ssandra](https://k8ssandra.io/)
