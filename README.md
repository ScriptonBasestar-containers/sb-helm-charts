# Helm Chart - ScriptonBasestar

helm 차트 의외로 쓸만한게 없어서 따로 만들어서(커스텀 해서) 써야한다

기존 helm 차트에서 기능 삭제해서 가볍게 수정.

## Charts
- Nextcloud: 

## 용도별

### Network
- openldap
- squid

### Data
- mariadb
- redis
- postgresql
- memcached
- mongodb
- cassandra

### K3s
- coredns
- cert-manager
- traefik
- istio

### Message
- rabbitmq
- kafka
- zookeeper

### DevOps
- argo-cd

### Etc
- nextcloud
- keycloak
- consul
- vault

## 외

차트없는것들
그리고 kafka처럼 zookeepr와 너무 합쳐져있는것들
때문에 시작했지만
helm차트는 용도에 따라 따로 만들어야 한다는 것
