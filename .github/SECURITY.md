# Security Policy

## Supported Versions

We provide security updates for the following chart versions:

| Chart Version | Supported          |
| ------------- | ------------------ |
| 0.3.x         | :white_check_mark: |
| 0.2.x         | :white_check_mark: |
| 0.1.x         | :x:                |

**Note**: Security updates are provided for stable releases (0.2.x and 0.3.x). Development versions (0.1.x) are not supported for security patches.

## Reporting a Vulnerability

We take the security of sb-helm-charts seriously. If you discover a security vulnerability, please follow these steps:

### 1. **Do Not** Create Public Issues

Please **do not** create public GitHub issues for security vulnerabilities. This could put users at risk before a fix is available.

### 2. Report Privately

Report security vulnerabilities by:

- **Email**: [INSERT SECURITY EMAIL ADDRESS]
- **Subject Line**: `[SECURITY] Brief description of vulnerability`

Include the following information in your report:

- **Chart name and version** affected
- **Description** of the vulnerability
- **Steps to reproduce** the issue
- **Potential impact** of the vulnerability
- **Suggested fix** (if available)
- **Your contact information** for follow-up questions

### 3. Response Timeline

We aim to respond to security reports according to the following timeline:

- **Initial Response**: Within 48 hours of receiving the report
- **Vulnerability Assessment**: Within 5 business days
- **Fix Development**: Depends on severity and complexity
- **Public Disclosure**: After patch is released and users have had time to update

### 4. Severity Levels

We classify vulnerabilities according to the following severity levels:

#### Critical
- Allows unauthorized access to cluster resources
- Allows privilege escalation to cluster-admin
- Exposes sensitive data (passwords, tokens, certificates)
- **Response Time**: 24-48 hours, emergency patch release

#### High
- Allows unauthorized access to application data
- Allows denial of service attacks
- Exposes internal network topology
- **Response Time**: 1 week, expedited patch release

#### Medium
- Information disclosure (non-sensitive)
- Limited denial of service
- Configuration weaknesses
- **Response Time**: 2-3 weeks, regular patch release

#### Low
- Minor security improvements
- Best practice violations
- **Response Time**: Next regular release

## Security Best Practices

When deploying charts from this repository, we recommend following these security best practices:

### 1. External Database Security

All charts use external databases. Ensure your database deployments follow security best practices:

- Enable SSL/TLS connections (see Keycloak chart for SSL examples)
- Use strong passwords (minimum 16 characters, random generation recommended)
- Configure network policies to restrict database access
- Regular security updates for database software
- Enable mutual TLS (mTLS) where supported

### 2. Secrets Management

- **Never** commit secrets to Git repositories
- Use Kubernetes Secrets for sensitive data
- Consider external secret management (HashiCorp Vault, AWS Secrets Manager, etc.)
- Rotate secrets regularly
- Use separate secrets for different environments (dev/staging/prod)

### 3. Network Policies

- Enable NetworkPolicy resources in your cluster
- Use the provided NetworkPolicy templates in charts
- Restrict ingress/egress traffic to minimum required
- Isolate namespaces with network policies

### 4. RBAC and Service Accounts

- Use dedicated ServiceAccounts for each application
- Follow principle of least privilege
- Regularly audit RBAC permissions
- Avoid using default ServiceAccount

### 5. Resource Limits

- Always set resource requests and limits
- Prevent resource exhaustion attacks
- Use PodDisruptionBudgets for high availability
- Configure HorizontalPodAutoscaler limits

### 6. Ingress and TLS

- Always use HTTPS for production deployments
- Use valid TLS certificates (Let's Encrypt, cert-manager)
- Configure proper TLS cipher suites
- Enable HSTS headers

### 7. Image Security

- Use specific image tags, not `latest`
- Verify image signatures where available
- Scan images for vulnerabilities (Trivy, Clair, etc.)
- Use trusted registries (Docker Hub official, GHCR)

### 8. Chart Updates

- Subscribe to GitHub notifications for this repository
- Review CHANGELOG.md before updating
- Test updates in non-production environments first
- Follow semantic versioning guidelines for breaking changes

## Known Security Considerations

### Development Charts (0.1.x)

Charts with version 0.1.x are in active development and should **not** be used in production environments without thorough security review.

### External Dependencies

This repository provides Helm charts only. Security of the deployed applications depends on:

- **Upstream application security**: Keycloak, Nextcloud, WordPress, etc.
- **Container image security**: LinuxServer.io, official Docker Hub images
- **Kubernetes cluster security**: Your cluster's security configuration

We monitor upstream security advisories and update charts accordingly, but users are responsible for:

- Monitoring upstream security announcements
- Updating `appVersion` in their deployments
- Applying security patches promptly

### StatefulSet Data Persistence

- StatefulSet volumes use `Retain` reclaim policy by default
- Deleting a chart release **does not** delete PersistentVolumes
- Manually delete PVs to remove sensitive data
- Consider encryption at rest for sensitive data

## Security Advisories

Security advisories for this repository will be published via:

- GitHub Security Advisories
- Release notes with `[SECURITY]` tag
- CHANGELOG.md with clear security indicators

Subscribe to repository notifications to receive security updates.

## Disclosure Policy

When a security vulnerability is fixed:

1. A patch is developed and tested privately
2. A new chart version is released with fix
3. Security advisory is published on GitHub
4. CHANGELOG.md is updated with security notice
5. Users are notified via GitHub release notifications

We follow responsible disclosure practices and coordinate with reporters to ensure proper timeline and credit.

## Security Contact

For security-related inquiries that are not vulnerabilities (security questions, best practices, etc.), you can:

- Open a public discussion in GitHub Discussions
- Create a regular GitHub issue with `security` label
- Reach out via the project's communication channels

## Acknowledgments

We appreciate the security research community's efforts in responsibly disclosing vulnerabilities. Security researchers who report valid vulnerabilities will be acknowledged in:

- Security advisory (unless anonymity is requested)
- CHANGELOG.md release notes
- GitHub release notes

Thank you for helping keep sb-helm-charts and our users safe!
