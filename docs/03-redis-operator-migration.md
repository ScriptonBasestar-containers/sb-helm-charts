# Redis Operator 마이그레이션 가이드

## 개요

이 문서는 현재 sb-helm-charts의 Redis 차트를 [Spotahome Redis Operator](https://github.com/spotahome/redis-operator)로 마이그레이션하는 방법을 설명합니다.

**마이그레이션 권장 이유:**
- 자동 failover 기능 (Sentinel 기반)
- 고가용성 (HA) 지원
- Master-Replica 자동 전환
- 프로덕션 안정성 향상
- 범용 인프라 컴포넌트로 적합

---

## 1. 현재 차트 vs Redis Operator 비교

### 현재 Redis 차트 (자체 제작)

| 특징 | 지원 여부 |
|------|----------|
| 배포 방식 | StatefulSet (단일 인스턴스) |
| 고가용성 | ❌ 미지원 (수동 복구 필요) |
| 자동 Failover | ❌ 미지원 |
| Sentinel | ❌ 미지원 |
| Master-Replica | ❌ 미지원 (단일 노드만) |
| 설정 관리 | ✅ redis.conf 직접 마운트 |
| 인증 | ✅ 비밀번호 인증 |
| 모니터링 | ✅ Prometheus metrics exporter |
| 적합 환경 | 개발/테스트, 단순 캐시 서버 |

### Redis Operator (Spotahome)

| 특징 | 지원 여부 |
|------|----------|
| 배포 방식 | CRD 기반 (RedisFailover) |
| 고가용성 | ✅ 자동 HA (Sentinel) |
| 자동 Failover | ✅ Master 장애 시 자동 전환 |
| Sentinel | ✅ 3개 이상 Sentinel 배포 |
| Master-Replica | ✅ 1 Master + N Replicas |
| 설정 관리 | ✅ CONFIG SET 명령어 동적 적용 |
| 인증 | ✅ 비밀번호 인증 |
| 모니터링 | ✅ Prometheus ServiceMonitor |
| 적합 환경 | **프로덕션, 고가용성 필수 환경** |

---

## 2. Redis Operator 아키텍처

### 구성 요소

```
RedisFailover CRD
├── Redis StatefulSet
│   ├── Master (1개)
│   └── Replicas (N개)
├── Sentinel Deployment
│   └── Sentinel Pods (3+개)
├── ConfigMaps
│   ├── rfr-<NAME> (Redis 설정)
│   └── rfs-<NAME> (Sentinel 설정)
└── Services
    └── rfs-<NAME> (Sentinel 서비스)
```

### Failover 메커니즘

1. **정상 상태**: Sentinel이 Master 모니터링
2. **Master 장애 감지**: Sentinel이 Master 응답 없음 확인
3. **투표**: Sentinel 간 투표로 Failover 결정
4. **Replica 승격**: 가장 적합한 Replica를 새 Master로 승격
5. **재구성**: 나머지 Replica들을 새 Master에 연결
6. **복구**: 기존 Master 복구 시 Replica로 재가입

**평균 복구 시간**: 30초 ~ 2분 (Sentinel 설정에 따라 다름)

---

## 3. 마이그레이션 전 체크리스트

### 요구사항 확인

- [ ] Kubernetes 1.21+ 클러스터
- [ ] Helm 3.2.0+ 설치
- [ ] PersistentVolume 프로비저너 지원
- [ ] 최소 4개 노드 권장 (Master 1 + Replica 2 + Sentinel 3)
- [ ] 기존 Redis 데이터 백업 완료

### 리소스 요구사항

**현재 Redis 차트 (단일 인스턴스):**
- CPU: 100m ~ 1000m
- Memory: 128Mi ~ 512Mi
- Storage: 8Gi (기본값)

**Redis Operator (HA 구성):**
- **Redis Pods**: (1 Master + 2 Replicas) × (100m CPU, 128Mi RAM, 8Gi Storage) = 약 3배
- **Sentinel Pods**: 3개 × (100m CPU, 128Mi RAM) = 추가 300m CPU, 384Mi RAM
- **총 추가 리소스**: 약 4배 증가

### 다운타임 계획

**다운타임 필요 시나리오:**
- 데이터 마이그레이션 (dump.rdb 복사)
- 애플리케이션 연결 문자열 변경

**예상 다운타임**: 5분 ~ 15분 (데이터 크기에 따라)

---

## 4. 설치 가이드

### Step 1: Redis Operator 설치

```bash
# Helm 저장소 추가
helm repo add redis-operator https://spotahome.github.io/redis-operator
helm repo update

# Operator 설치
helm install redis-operator redis-operator/redis-operator \
  --namespace redis-system \
  --create-namespace

# 설치 확인
kubectl get pods -n redis-system
kubectl get crd | grep redis
```

**확인 사항:**
- `redisfailovers.databases.spotahome.com` CRD 생성 완료
- `redis-operator` Pod가 Running 상태

### Step 2: 기존 Redis 데이터 백업

```bash
# 현재 Redis 인스턴스 백업
kubectl exec my-redis-0 -n default -- redis-cli BGSAVE

# dump.rdb 복사
kubectl cp my-redis-0:/data/dump.rdb ./redis-backup-$(date +%Y%m%d).rdb -n default

# 백업 파일 확인
ls -lh redis-backup-*.rdb
```

### Step 3: RedisFailover 리소스 생성

`redis-failover.yaml` 파일 생성:

```yaml
apiVersion: databases.spotahome.com/v1
kind: RedisFailover
metadata:
  name: my-redis
  namespace: default
spec:
  sentinel:
    replicas: 3
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  redis:
    replicas: 3  # 1 Master + 2 Replicas
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 1000m
        memory: 512Mi
    storage:
      persistentVolumeClaim:
        metadata:
          name: redis-data
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 8Gi
    # Redis 설정 (선택사항)
    customConfig:
      - "maxmemory 256mb"
      - "maxmemory-policy allkeys-lru"
      - "save 900 1"
      - "save 300 10"
```

배포:

```bash
kubectl apply -f redis-failover.yaml

# 리소스 생성 확인
kubectl get redisfailover -n default
kubectl get pods -n default -l redisfailovers.databases.spotahome.com/name=my-redis
```

**생성된 리소스:**
- StatefulSet: `rfr-my-redis` (Redis 3개: 1 Master + 2 Replicas)
- Deployment: `rfs-my-redis` (Sentinel 3개)
- Service: `rfs-my-redis` (Sentinel 서비스)
- ConfigMaps: `rfr-my-redis`, `rfs-my-redis`

### Step 4: 데이터 복원 (선택사항)

```bash
# Master Pod 찾기
MASTER_POD=$(kubectl get pods -n default -l redisfailovers-role=master -o jsonpath='{.items[0].metadata.name}')

# 백업 파일 복사
kubectl cp ./redis-backup-20250114.rdb $MASTER_POD:/data/dump.rdb -n default

# Redis 재시작 (StatefulSet 재시작)
kubectl rollout restart statefulset/rfr-my-redis -n default

# 데이터 복원 확인
kubectl exec $MASTER_POD -n default -- redis-cli DBSIZE
```

### Step 5: 애플리케이션 연결 문자열 변경

**기존 연결 방식:**
```
Host: my-redis.default.svc.cluster.local
Port: 6379
```

**Operator 연결 방식 (Sentinel 사용):**
```
Sentinel Service: rfs-my-redis.default.svc.cluster.local
Sentinel Port: 26379
Master Name: mymaster
Redis Port: 6379
```

**애플리케이션 코드 예시 (Python):**

```python
from redis.sentinel import Sentinel

# Sentinel 연결
sentinel = Sentinel([
    ('rfs-my-redis.default.svc.cluster.local', 26379)
])

# Master 연결 (자동 failover)
master = sentinel.master_for('mymaster', socket_timeout=0.1)
master.set('key', 'value')

# Replica 연결 (읽기 전용)
slave = sentinel.slave_for('mymaster', socket_timeout=0.1)
value = slave.get('key')
```

**애플리케이션 코드 예시 (Go):**

```go
import (
    "github.com/go-redis/redis/v8"
)

// Sentinel 클라이언트 생성
rdb := redis.NewFailoverClient(&redis.FailoverOptions{
    MasterName:    "mymaster",
    SentinelAddrs: []string{"rfs-my-redis.default.svc.cluster.local:26379"},
})

// 자동 failover 지원
err := rdb.Set(ctx, "key", "value", 0).Err()
```

### Step 6: 기존 Redis 제거

```bash
# 기존 Helm 릴리스 삭제
helm uninstall my-redis -n default

# PVC 삭제 (필요 시)
kubectl delete pvc redis-data-my-redis-0 -n default
```

---

## 5. 운영 가이드

### 5.1 상태 확인

```bash
# RedisFailover 상태
kubectl get redisfailover my-redis -n default -o yaml

# Master/Replica 확인
kubectl get pods -n default -l redisfailovers.databases.spotahome.com/name=my-redis -o wide

# Master Pod 찾기
kubectl get pods -n default -l redisfailovers-role=master

# Sentinel 상태 확인
kubectl exec rfs-my-redis-<POD-ID> -n default -- redis-cli -p 26379 SENTINEL masters
kubectl exec rfs-my-redis-<POD-ID> -n default -- redis-cli -p 26379 SENTINEL replicas mymaster
```

### 5.2 Failover 테스트

**수동 Failover:**

```bash
# Master Pod 강제 종료
MASTER_POD=$(kubectl get pods -n default -l redisfailovers-role=master -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $MASTER_POD -n default

# Failover 진행 확인 (30초~2분 소요)
kubectl get pods -n default -l redisfailovers.databases.spotahome.com/name=my-redis -w

# 새 Master 확인
kubectl get pods -n default -l redisfailovers-role=master
```

### 5.3 설정 변경

**동적 설정 변경 (재시작 불필요):**

```bash
# RedisFailover 리소스 수정
kubectl edit redisfailover my-redis -n default

# customConfig 섹션에 추가
spec:
  redis:
    customConfig:
      - "maxmemory 512mb"
      - "maxmemory-policy volatile-lru"
```

Operator가 자동으로 `CONFIG SET` 명령어를 실행하여 모든 Redis 인스턴스에 적용합니다.

### 5.4 스케일링

**Replica 개수 변경:**

```bash
kubectl patch redisfailover my-redis -n default --type='json' \
  -p='[{"op": "replace", "path": "/spec/redis/replicas", "value": 5}]'
```

**주의사항:**
- Master는 항상 1개 (자동 관리)
- Replica 최소 2개 권장 (failover 보장)
- Sentinel 최소 3개 (quorum 보장)

### 5.5 백업 및 복원

**자동 백업 (CronJob 활용):**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: redis-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # 매일 새벽 2시
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: redis:7-alpine
            command:
            - sh
            - -c
            - |
              MASTER_POD=$(kubectl get pods -l redisfailovers-role=master -o jsonpath='{.items[0].metadata.name}')
              kubectl exec $MASTER_POD -- redis-cli BGSAVE
              kubectl cp $MASTER_POD:/data/dump.rdb /backup/redis-backup-$(date +%Y%m%d).rdb
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: redis-backup-pvc
          restartPolicy: OnFailure
```

---

## 6. 모니터링

### Prometheus ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-failover
  namespace: default
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: redis-failover
  endpoints:
  - port: metrics
    interval: 30s
```

### 주요 메트릭

- `redis_up`: Redis 인스턴스 상태 (1 = UP, 0 = DOWN)
- `redis_master_repl_offset`: Master replication offset
- `redis_connected_slaves`: 연결된 Replica 개수
- `sentinel_masters`: Sentinel이 모니터링하는 Master 수
- `sentinel_master_status`: Master 상태 (1 = OK)

### Grafana 대시보드

Spotahome Redis Operator 공식 대시보드:
- [Grafana Dashboard ID: 11835](https://grafana.com/grafana/dashboards/11835)

---

## 7. 트러블슈팅

### Master Failover가 발생하지 않음

**증상:**
- Master Pod 삭제 후에도 새 Master가 선출되지 않음

**원인 및 해결:**

```bash
# Sentinel 로그 확인
kubectl logs rfs-my-redis-<POD-ID> -n default

# Quorum 설정 확인
kubectl exec rfs-my-redis-<POD-ID> -n default -- redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster

# Sentinel 개수 확인 (최소 3개 필요)
kubectl get pods -n default -l app.kubernetes.io/component=sentinel
```

**해결 방법:**
- Sentinel replicas를 3개 이상으로 설정
- 네트워크 정책 확인 (Sentinel ↔ Redis 통신 허용)

### Split-Brain 상태 (여러 Master 존재)

**증상:**
- 여러 Pod가 Master로 동작

**확인:**

```bash
# 모든 Redis Pod에서 역할 확인
kubectl get pods -n default -l redisfailovers.databases.spotahome.com/name=my-redis -o name | \
  xargs -I {} kubectl exec {} -n default -- redis-cli INFO replication | grep role
```

**해결:**

```bash
# Operator 재시작
kubectl rollout restart deployment/redis-operator -n redis-system

# Sentinel 재시작
kubectl rollout restart deployment/rfs-my-redis -n default
```

### 데이터 동기화 지연

**증상:**
- Replica가 Master보다 오래된 데이터를 가짐

**확인:**

```bash
# Replication lag 확인
MASTER_POD=$(kubectl get pods -n default -l redisfailovers-role=master -o jsonpath='{.items[0].metadata.name}')
kubectl exec $MASTER_POD -n default -- redis-cli INFO replication
```

**해결:**
- 네트워크 대역폭 확인
- Replica 리소스 제한 증가 (CPU, Memory)
- `repl-backlog-size` 증가 (customConfig)

---

## 8. 마이그레이션 롤백

### Operator → 기존 차트로 롤백

**Step 1: 데이터 백업**

```bash
MASTER_POD=$(kubectl get pods -n default -l redisfailovers-role=master -o jsonpath='{.items[0].metadata.name}')
kubectl exec $MASTER_POD -n default -- redis-cli BGSAVE
kubectl cp $MASTER_POD:/data/dump.rdb ./redis-rollback-backup.rdb -n default
```

**Step 2: RedisFailover 삭제**

```bash
kubectl delete redisfailover my-redis -n default
```

**Step 3: 기존 차트 재설치**

```bash
helm install my-redis ./charts/redis -f my-values.yaml -n default
```

**Step 4: 데이터 복원**

```bash
kubectl cp ./redis-rollback-backup.rdb my-redis-0:/data/dump.rdb -n default
kubectl delete pod my-redis-0 -n default
```

---

## 9. 비용 및 성능 비교

### 리소스 비용 (월간 예상)

**가정:**
- AWS EKS 클러스터
- t3.medium 노드 (2 vCPU, 4GB RAM)
- EBS gp3 스토리지

| 항목 | 기존 Redis 차트 | Redis Operator (HA) | 차이 |
|------|----------------|---------------------|------|
| Redis Pods | 1개 (100m CPU, 128Mi RAM) | 3개 (300m CPU, 384Mi RAM) | +2개 |
| Sentinel Pods | 0개 | 3개 (300m CPU, 384Mi RAM) | +3개 |
| Storage | 8Gi | 24Gi (8Gi × 3) | +16Gi |
| 총 CPU | 100m | 600m | +500m |
| 총 Memory | 128Mi | 768Mi | +640Mi |
| **월간 비용** | **~$10** | **~$40** | **+$30** |

### 성능

**처리량 (ops/sec):**
- 기존: ~50,000 ops/sec (단일 인스턴스)
- Operator: ~150,000 ops/sec (Replica 읽기 분산)

**가용성 (Uptime):**
- 기존: 99.5% (수동 복구)
- Operator: 99.95% (자동 failover)

---

## 10. 권장 사항

### Operator 사용 권장

- ✅ **프로덕션 환경**
- ✅ **고가용성 필수 서비스**
- ✅ **24/7 운영 서비스**
- ✅ **자동 복구 필요**
- ✅ **읽기 부하 분산 필요**

### 기존 차트 유지 권장

- ✅ **개발/테스트 환경**
- ✅ **단순 캐시 서버**
- ✅ **임시 데이터 저장**
- ✅ **리소스 제약 환경**
- ✅ **단일 애플리케이션 전용**

---

## 11. 참조

- [Spotahome Redis Operator GitHub](https://github.com/spotahome/redis-operator)
- [Redis Sentinel 문서](https://redis.io/docs/manual/sentinel/)
- [Helm Chart 저장소](https://artifacthub.io/packages/helm/redis-operator/redis-operator)
- [Redis Operator CRD 스펙](https://github.com/spotahome/redis-operator/blob/master/api/redisfailover/v1/types.go)
- [Prometheus ServiceMonitor](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/user-guides/getting-started.md)

---

## 12. 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|----------|
| 2025-01-14 | 1.0 | 초안 작성 |
