# Jenkins Operations Makefile
# Usage: make -f make/ops/jenkins.mk <target>

JENKINS_NAMESPACE ?= devops
JENKINS_RELEASE ?= jenkins

# Port forwarding
.PHONY: jenkins-port-forward
jenkins-port-forward:
	kubectl port-forward -n $(JENKINS_NAMESPACE) svc/$(JENKINS_RELEASE) 8080:8080

# Get admin password
.PHONY: jenkins-admin-password
jenkins-admin-password:
	kubectl get secret -n $(JENKINS_NAMESPACE) $(JENKINS_RELEASE) -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo

# Shell into pod
.PHONY: jenkins-shell
jenkins-shell:
	kubectl exec -it -n $(JENKINS_NAMESPACE) deploy/$(JENKINS_RELEASE) -- /bin/bash

# View logs
.PHONY: jenkins-logs
jenkins-logs:
	kubectl logs -n $(JENKINS_NAMESPACE) -l app.kubernetes.io/name=jenkins -f

# Restart
.PHONY: jenkins-restart
jenkins-restart:
	kubectl rollout restart -n $(JENKINS_NAMESPACE) deploy/$(JENKINS_RELEASE)

# Status
.PHONY: jenkins-status
jenkins-status:
	kubectl get pods,svc,ingress -n $(JENKINS_NAMESPACE) -l app.kubernetes.io/name=jenkins
