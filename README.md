# Helm Chart - ScriptonBasestar

helm 차트 의외로 쓸만한게 없어서 따로 만들어서(커스텀 해서) 써야함

helm이 대규모 인프라를 위해 설계한답시고 조금 설계가 잘못된 것 같은데
nextcloud같은거 설치하면서 dependency로 설정된 경우 mariadb랑 redis까지 따로 설치한다.
일회용 테스트 인프라를 설계할게 아니라면 dependency에 대한 ping-pong을 확인하고 서버가 실행된다던가 하는식으로 움직여야 할 것 같은데


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
