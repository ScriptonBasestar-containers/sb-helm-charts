# Helm Chart - ScriptonBasestar

## Installation

### Add Helm Repository

**GitHub Pages (Traditional)**
```bash
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update
```

**GHCR OCI Registry (Recommended)**
```bash
# No repository add needed - use OCI directly
helm install keycloak oci://ghcr.io/scriptonbasestar-containers/charts/keycloak --version 0.3.0
```

### Usage Examples

**Install from GitHub Pages**
```bash
helm install keycloak sb-charts/keycloak --version 0.3.0 -f values.yaml
```

**Install from OCI Registry**
```bash
helm install keycloak oci://ghcr.io/scriptonbasestar-containers/charts/keycloak --version 0.3.0 -f values.yaml
```

**Pull Chart**
```bash
# GitHub Pages
helm pull sb-charts/keycloak --version 0.3.0

# OCI Registry
helm pull oci://ghcr.io/scriptonbasestar-containers/charts/keycloak --version 0.3.0
```

## 프로젝트 목표 (NO_AI_SECTION)

개인 서버 및 간단한 서버 운영을 위한 차트

helm의 설정값만 가지고 소프트웨어를 설치할 수 있게 만든다는 컨셉은 잘못됐다.

`helm install {app_name} {repo_name}/{chart_name} --values simplevalue.yaml`
기본 value.yaml에서 몇가지 값만 오버라이드 해서 쓰라는 컨셉인데... 사실 그렇게 쓸 수는 없다.
표준 ingress에 대한 value도 차트마다 제각각인 것도 문제...

IaC에서 설치가 쉬운건 잠깐이고 유지보수가 용이하고 사용시에 오류가 없어야 하는데 helm의 복잡한 설정은 다음과 같은 이유로 지속적으로 오류를 발생시킨다.
- 앱의 업데이트에 따른 설정값의 변경
- docker 설정값의 변경
- helm 차트의 업데이트에 따른 설정값의 변경
이렇게 각각의 단계 끝에 있는 helm은 복잡성이 더 높아진다.

편하게 만들려고 하면 할 수록 점점 더 복잡해지고 앱에서 대규모의 변경이 발생했을 때 따라갈 수 없게 된다.
app-docker-helm 3단계로 복잡성이 꼬이게 된다.

하지만... docker에서 app의 설정값을 거의 그대로 사용하고 helm에서도 그대로 쓴다면? 복잡성 전파가 거의 사라진다.

어차피 장기적&안정적으로 서버를 운영하려면 소프트웨어를 이해하고 설정값을 수정해야한다. 쉬운 설치는 도움이 안 된다.

오래된 오픈소스는 대부분 설정파일을 기반으로 개발되어 있고 환경변수를 지원하더라도 싱글서버에서는 설정파일을 관리하는편이 더 오류가 적다.
만능헬름차트는 홈서버 나스용으로도 거의 못 쓰고 결국 커스텀을 해야한다.
그럴바에는... 환경변수를 config나 values에 포함시키는 편이 낫다.

도커에서 env를 기반으로 설정파일을 생성하도록 만들어놓은 경우가 많은데... 시키는대로 쓰면 편한데 특별한 상황이나 오류발생시 대처가 불가능하다.

helm의 가장 잘못된 설계는 config파일을 values에 대입하는 기능을 안 만든 부분이다.
하지만 이게 표준이 돼 버렸으니... 그 부분을 감안하고 써야한다. 아니면 커스텀 코드로 헬름차트를 덮어쓰도록 해 줘야한다(대부분 이렇게 쓰고 있을듯??)

## 다른차트와 차별점 (NO_AI_SECTION)
- 설정파일 그대로 활용, 환경변수 사용은 지양
    - 대부분의 오래된 오픈소스는 설정파일 기반으로 개발되어 있다.
    - 설정파일 위주 소프트웨어를 환경변수 기반인 도커로 변환하면서 문제가 발생한다.
- 서브차트 최대한 배제
    - 필수적으로 함께 사용되는 것들만 함께 설치
    - 일반적으로 별도 설치하는 db 등은 분리
    - 디비는 각 사이트마다 자신들이 원하는 옵션이 있어서 차트로 포함 해 봐야 실 배포에서 한번도 쓴 적이 없다.
- 심플한 도커이미지가 있는경우 사용하지만 없으면 도커부터 만들어 사용
