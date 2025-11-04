# WireGuard Helm Chart

[WireGuard](https://www.wireguard.com/) is a fast, modern, secure VPN tunnel that uses state-of-the-art cryptography.

## Features

- ✅ **Configuration file approach**: Direct wg0.conf support (recommended)
- ✅ **Auto-generation mode**: LinuxServer.io environment variable mode (optional)
- ✅ **No external dependencies**: No database required
- ✅ **Flexible deployment**: Supports LoadBalancer, NodePort, or ClusterIP
- ✅ **Security**: NET_ADMIN capabilities without full privileged mode
- ✅ **Persistent storage**: PVC for peer configurations and QR codes
- ✅ **Health probes**: Liveness, readiness, and startup probes
- ✅ **Network policy**: Optional ingress/egress traffic control
- ✅ **k3s optimized**: Works with k3s default storage and networking
- ✅ **Easy management**: Makefile commands for common operations

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- WireGuard kernel module installed on nodes (or wireguard-go fallback)
- PersistentVolume support (for config persistence)
- LoadBalancer or NodePort for external access

## Quick Start

### 1. Check WireGuard Kernel Module

```bash
# On your Kubernetes nodes
lsmod | grep wireguard

# If not present, install it
sudo apt install wireguard  # Debian/Ubuntu
sudo yum install wireguard-tools  # RHEL/CentOS
```

### 2. Install the Chart (Manual Mode - Recommended)

```bash
# Generate server keys
wg genkey | tee server-private.key | wg pubkey > server-public.key

# Generate peer keys
wg genkey | tee peer1-private.key | wg pubkey > peer1-public.key

# Create values file
cat > my-wireguard-values.yaml <<EOF
wireguard:
  mode: "manual"

  serverConfig: |
    [Interface]
    Address = 10.13.13.1/24
    ListenPort = 51820
    PrivateKey = $(cat server-private.key)
    PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

    [Peer]
    PublicKey = $(cat peer1-public.key)
    AllowedIPs = 10.13.13.2/32

  privateKey: "$(cat server-private.key)"

service:
  type: LoadBalancer  # or NodePort for k3s
  port: 51820

persistence:
  enabled: true
  size: 1Gi
  storageClass: "local-path"  # k3s default
EOF

# Install
helm install my-wireguard ./charts/wireguard -f my-wireguard-values.yaml
```

### 3. Get Connection Information

```bash
# Get LoadBalancer IP
kubectl get svc my-wireguard

# Or use Makefile
make -f Makefile.wireguard.mk wg-endpoint

# Get server public key
make -f Makefile.wireguard.mk wg-pubkey
```

### 4. Create Client Configuration

Create a `client.conf` file:

```ini
[Interface]
PrivateKey = <paste peer1-private.key content>
Address = 10.13.13.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = <paste server-public.key content>
Endpoint = <LOADBALANCER_IP>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### 5. Connect

```bash
# Linux
sudo wg-quick up ./client.conf

# macOS
# Use WireGuard app and import client.conf

# iOS/Android
# Use WireGuard app and scan QR code or import file
```

## Configuration

### Configuration Modes

#### Manual Mode (Recommended)

Use pure wg0.conf file - follows "config files over environment variables" philosophy.

```yaml
wireguard:
  mode: "manual"
  serverConfig: |
    [Interface]
    Address = 10.13.13.1/24
    ListenPort = 51820
    PrivateKey = YOUR_PRIVATE_KEY

    [Peer]
    PublicKey = PEER_PUBLIC_KEY
    AllowedIPs = 10.13.13.2/32
```

**Pros:**
- Full control over configuration
- Portable to non-Kubernetes environments
- GitOps friendly
- No abstraction layer

**Cons:**
- Manual key generation required
- No automatic QR codes

#### Auto Mode (Convenience)

Use LinuxServer.io auto-generation via environment variables.

```yaml
wireguard:
  mode: "auto"
  auto:
    serverUrl: "vpn.example.com"
    peers: 5
    internalSubnet: "10.13.13.0"
```

**Pros:**
- Automatic key generation
- QR codes for mobile devices
- Less initial configuration

**Cons:**
- Environment variable heavy
- Keys stored in container filesystem
- Requires PVC for persistence

### Service Types

#### LoadBalancer (Recommended for Cloud)

```yaml
service:
  type: LoadBalancer
  port: 51820
```

Requires MetalLB, cloud provider LB, or k3s ServiceLB (klipper-lb).

#### NodePort (Recommended for k3s)

```yaml
service:
  type: NodePort
  port: 51820
  nodePort: 31820  # Optional: fixed port
```

Best for k3s or bare-metal without LoadBalancer. Configure router port forwarding:
- External: UDP 51820 → Node IP:31820

#### ClusterIP (Internal Only)

```yaml
service:
  type: ClusterIP
  port: 51820
```

Only accessible within Kubernetes cluster.

### Storage

```yaml
persistence:
  enabled: true
  size: 1Gi
  storageClass: "local-path"  # k3s default
  reclaimPolicy: Retain  # Keep data after chart deletion
```

**Stored data:**
- Peer configurations (auto mode)
- QR codes (auto mode)
- Generated keys (auto mode)
- WireGuard state

### Security

```yaml
securityContext:
  capabilities:
    add:
      - NET_ADMIN   # Required: network interface management
      - SYS_MODULE  # Optional: kernel module loading
  privileged: false  # Avoid full privileged mode

podSecurityContext:
  sysctls:
    - name: net.ipv4.ip_forward
      value: "1"
    - name: net.ipv4.conf.all.src_valid_mark
      value: "1"
```

### Network Policy

```yaml
networkPolicy:
  enabled: true
  ingress:
    ipBlocks:
      - 0.0.0.0/0  # Allow VPN from anywhere
  egress:
    allowAll: true  # Allow VPN traffic to anywhere
```

## Makefile Commands

```bash
# Show WireGuard status
make -f Makefile.wireguard.mk wg-show

# Get peer configuration (auto mode)
make -f Makefile.wireguard.mk wg-get-peer PEER=peer1

# List all peers (auto mode)
make -f Makefile.wireguard.mk wg-list-peers

# Display QR code (auto mode)
make -f Makefile.wireguard.mk wg-qr PEER=peer1

# Show current config
make -f Makefile.wireguard.mk wg-config

# Get server public key
make -f Makefile.wireguard.mk wg-pubkey

# Restart WireGuard
make -f Makefile.wireguard.mk wg-restart

# View logs
make -f Makefile.wireguard.mk wg-logs

# Open shell
make -f Makefile.wireguard.mk wg-shell

# Get service endpoint
make -f Makefile.wireguard.mk wg-endpoint

# Get help
make -f Makefile.wireguard.mk help
```

## Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `wireguard.mode` | Configuration mode: `manual` or `auto` | `"manual"` |
| `wireguard.serverConfig` | wg0.conf file content (manual mode) | `""` |
| `wireguard.privateKey` | Server private key (manual mode) | `""` |
| `wireguard.auto.serverUrl` | Public URL/IP (auto mode) | `""` |
| `wireguard.auto.peers` | Number of peers to generate (auto mode) | `5` |
| `wireguard.auto.internalSubnet` | VPN subnet (auto mode) | `"10.13.13.0"` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | PVC size | `"1Gi"` |
| `persistence.storageClass` | Storage class | `""` |
| `service.type` | Service type: LoadBalancer, NodePort, or ClusterIP | `"LoadBalancer"` |
| `service.port` | WireGuard port | `51820` |
| `service.protocol` | Protocol (must be UDP) | `"UDP"` |
| `resources.limits.cpu` | CPU limit | `"500m"` |
| `resources.limits.memory` | Memory limit | `"256Mi"` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |

See [values.yaml](values.yaml) for all available options.

## Advanced Configuration

### Split Tunnel (Only Route VPN Subnet)

```yaml
wireguard:
  serverConfig: |
    [Interface]
    Address = 10.13.13.1/24
    ListenPort = 51820
    PrivateKey = YOUR_KEY

    [Peer]
    PublicKey = PEER_KEY
    # Only route VPN traffic through tunnel
    AllowedIPs = 10.13.13.0/24
```

Client config:
```ini
[Peer]
AllowedIPs = 10.13.13.0/24  # Only VPN subnet, not all traffic
```

### Full Tunnel (All Traffic Through VPN)

```yaml
wireguard:
  serverConfig: |
    [Interface]
    Address = 10.13.13.1/24
    ListenPort = 51820
    PrivateKey = YOUR_KEY
    # Enable NAT for internet access
    PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

    [Peer]
    PublicKey = PEER_KEY
    AllowedIPs = 10.13.13.0/24
```

Client config:
```ini
[Peer]
AllowedIPs = 0.0.0.0/0, ::/0  # Route all traffic
```

### Site-to-Site VPN

```yaml
wireguard:
  serverConfig: |
    [Interface]
    Address = 10.13.13.1/24
    ListenPort = 51820
    PrivateKey = SITE_A_KEY

    # Site B connection
    [Peer]
    PublicKey = SITE_B_KEY
    Endpoint = site-b.example.com:51820
    AllowedIPs = 10.13.14.0/24
    PersistentKeepalive = 25
```

## Troubleshooting

### Pod Not Starting

**Symptom:** Pod stuck in `Pending` or `CrashLoopBackOff`

**Solutions:**
1. Check if NET_ADMIN capability is supported:
   ```bash
   kubectl describe pod <pod-name>
   ```

2. Verify WireGuard kernel module:
   ```bash
   # On node
   lsmod | grep wireguard
   ```

3. Check pod events:
   ```bash
   kubectl describe pod -l app.kubernetes.io/name=wireguard
   ```

### VPN Connects But No Internet

**Symptom:** Can ping VPN gateway but can't reach internet

**Solutions:**
1. Verify iptables rules in PostUp/PostDown
2. Check IP forwarding on node:
   ```bash
   sysctl net.ipv4.ip_forward
   # Should be 1
   ```

3. Check NAT rules:
   ```bash
   kubectl exec <pod> -- iptables -t nat -L
   ```

### Can't Connect to VPN

**Symptom:** Connection timeout

**Solutions:**
1. Verify service endpoint:
   ```bash
   make -f Makefile.wireguard.mk wg-endpoint
   ```

2. Check LoadBalancer status:
   ```bash
   kubectl get svc wireguard
   ```

3. Verify firewall/router port forwarding (for NodePort)

4. Check server public key matches client config:
   ```bash
   make -f Makefile.wireguard.mk wg-pubkey
   ```

### Connection Drops Frequently

**Symptom:** VPN disconnects after a few minutes

**Solutions:**
1. Enable PersistentKeepalive in client config:
   ```ini
   [Peer]
   PersistentKeepalive = 25
   ```

2. Adjust MTU (try 1420 or 1380):
   ```ini
   [Interface]
   MTU = 1420
   ```

3. Check NAT timeout settings on router

### Permission Denied Errors

**Symptom:** `Operation not permitted` errors in logs

**Solutions:**
1. Ensure NET_ADMIN capability is enabled in values.yaml
2. Check pod security policy/standards
3. Verify sysctl settings in podSecurityContext

## Production Considerations

### Security Best Practices

1. **Use strong keys**: Generate new keys for production
   ```bash
   wg genkey | tee server-private.key | wg pubkey > server-public.key
   ```

2. **Limit AllowedIPs**: Only allow necessary IP ranges

3. **Enable NetworkPolicy**: Restrict traffic to VPN port only

4. **Rotate keys periodically**: Update keys every 6-12 months

5. **Use TLS for config distribution**: Don't share configs over plain HTTP

### High Availability

WireGuard is designed as a point-to-point protocol. For HA:

1. **Multiple servers**: Deploy separate WireGuard instances with different endpoints
2. **DNS round-robin**: Use multiple A records
3. **Failover**: Configure clients with multiple peers

Note: This chart uses `replicas: 1` and `Recreate` strategy as WireGuard doesn't support horizontal scaling for a single VPN gateway.

### Monitoring

1. **Metrics**: WireGuard doesn't export Prometheus metrics by default
2. **Logs**: Monitor pod logs for handshake failures
3. **Health checks**: Liveness/readiness probes check interface status

```bash
# Check current connections
make -f Makefile.wireguard.mk wg-show

# Monitor logs
make -f Makefile.wireguard.mk wg-logs
```

### Backup and Recovery

**Manual mode:**
- Config is in Git (values.yaml) - no backup needed
- Keys in Kubernetes Secrets - backup with Velero or similar

**Auto mode:**
- Backup PVC containing generated configs
- Store QR codes externally for disaster recovery

```bash
# Backup peer configs (auto mode)
kubectl cp <pod>:/config ./wireguard-backup/
```

## Migration

### From Other VPN Solutions

**From OpenVPN:**
- WireGuard is significantly faster
- Simpler configuration
- Better mobile battery life
- Use similar network topology

**From IPsec:**
- Easier key management
- Better performance
- Simpler troubleshooting

### Upgrading This Chart

```bash
# Check current version
helm list

# Upgrade
helm upgrade my-wireguard ./charts/wireguard -f my-values.yaml

# Rollback if needed
helm rollback my-wireguard
```

## License

This Helm chart is licensed under the BSD 3-Clause License. See the [LICENSE](../../LICENSE) file for details.

WireGuard is licensed under the GPLv2.

## Resources

- [WireGuard Official Site](https://www.wireguard.com/)
- [WireGuard Quick Start](https://www.wireguard.com/quickstart/)
- [LinuxServer WireGuard Image](https://github.com/linuxserver/docker-wireguard)
- [sb-helm-charts Repository](https://github.com/scriptonbasestar-docker/sb-helm-charts)

## Contributing

Contributions are welcome! Please follow the project's contribution guidelines.

## Support

For issues and questions:
- Chart issues: [GitHub Issues](https://github.com/scriptonbasestar-docker/sb-helm-charts/issues)
- WireGuard questions: [WireGuard Mailing List](https://lists.zx2c4.com/mailman/listinfo/wireguard)
