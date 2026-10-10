# Host HAProxy Endpoints

## Status

The host HAProxy API endpoint on TCP `6443` was configured and validated for Checkpoint 1. The TCP `80` listener described here is an optional single-address extension; it has not yet been applied or tested in this lab.

## Purpose and ownership

HAProxy is a host-owned service used for two distinct entry points: the stable K3s API endpoint on TCP `6443`, and an optional single-address HTTP entry point on TCP `80` for the demo Ingress. It is installed and configured on the libvirt host, not inside Kubernetes. It does not make the physical host highly available.

The API endpoint is required by the [K3s HA cluster build runbook](k3s-ha-cluster.md) before the additional K3s servers join. The HTTP endpoint is optional and should only be added after the demo Ingress works through the individual VM addresses, as described in the [workload routing runbook](k3s-workload-routing.md).

The lab host is `10.77.0.1` on the private libvirt network; the K3s VMs are `10.77.0.11`, `10.77.0.12`, and `10.77.0.13`. UFW denies incoming traffic by default. The rules below allow only the libvirt subnet to reach the host listeners. The NAT network does not expose these listeners to the home LAN or Internet.

## Install HAProxy

Run the commands on the libvirt host after the first K3s API server has been validated directly at `10.77.0.11:6443`:

```sh
sudo apt update
sudo apt install haproxy
```

Do not replace the package configuration. It contains useful global settings for the chroot, unprivileged `haproxy` user, admin stats socket, TLS defaults, and HTTP defaults. The packaged systemd service loads `/etc/haproxy/haproxy.cfg` and does not automatically load an apt-style `conf.d` directory.

Before each configuration change, back up the current file to a new, unique path. Do not overwrite an earlier backup:

```sh
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.before-k3s-api
```

If that backup path already exists, choose another name that records the date or change being made. Append the required named sections with `sudoedit /etc/haproxy/haproxy.cfg`, retaining the package configuration and any unrelated existing configuration.

## Configure the stable K3s API endpoint

Allow API connections from the lab subnet to the host endpoint:

```sh
sudo ufw status numbered
sudo ufw allow in from 10.77.0.0/24 to 10.77.0.1 port 6443 proto tcp comment 'K3s API via HAProxy (lab only)'
sudo ufw status numbered
```

If the exact lab rule already exists, keep it and do not add a duplicate.

Append these HAProxy sections to `/etc/haproxy/haproxy.cfg`:

```haproxy
defaults k3s_api_defaults
    mode tcp
    log global
    option tcplog
    option logasap
    timeout connect 5s
    timeout client 1h
    timeout server 1h

frontend k3s_api from k3s_api_defaults
    bind 10.77.0.1:6443
    default_backend k3s_api_servers

backend k3s_api_servers from k3s_api_defaults
    balance roundrobin
    option log-health-checks
    server k3s-1 10.77.0.11:6443 check inter 2s fall 2 rise 2
    server k3s-2 10.77.0.12:6443 check inter 2s fall 2 rise 2
    server k3s-3 10.77.0.13:6443 check inter 2s fall 2 rise 2
```

Validate the complete file before reloading the service:

```sh
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
sudo systemctl is-active haproxy
```

Update the host-side kubeconfig and verify the API through the stable endpoint before allowing K3s joiners to use it:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" config set-cluster default --server=https://10.77.0.1:6443
test "$(kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" config view --minify -o jsonpath='{.clusters[0].cluster.server}')" = 'https://10.77.0.1:6443'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

The API listener is TCP pass-through; HAProxy does not terminate TLS or inspect Kubernetes requests. TCP health checks verify that a backend accepts connections, not that etcd or the API is fully ready. The API validation commands check readiness separately. HAProxy logs are written to `/var/log/haproxy.log` by the Ubuntu package:

```sh
sudo tail -f /var/log/haproxy.log
```

## Add one host-side address for the demo Ingress

This step is optional. First complete the [workload routing runbook](k3s-workload-routing.md) through successful HTTP `200` responses from all three VM addresses. The Traefik LoadBalancer Service listens on each VM IP, while this host HAProxy listener provides one convenient address, `10.77.0.1:80`, for clients on the libvirt subnet.

Before binding the host address, inspect existing listeners and HAProxy configuration for a conflicting port-`80` bind. Do not replace or repurpose an unrelated host frontend:

```sh
sudo ss -lntp
sudo less /etc/haproxy/haproxy.cfg
```

Allow HTTP connections from the lab subnet to the host:

```sh
sudo ufw status numbered
sudo ufw allow in from 10.77.0.0/24 to 10.77.0.1 port 80 proto tcp comment 'K3s demo HTTP via HAProxy (lab only)'
sudo ufw status numbered
```

If the exact lab rule already exists, keep it and do not add a duplicate.

Back up the current HAProxy configuration to a new, unique file, then append these sections. For example, use this backup path if it does not already exist. The TCP mode preserves the HTTP Host header for Traefik's Ingress rule; health checks confirm that each node accepts connections on port `80`:

```sh
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.before-k3s-demo-http
```

```haproxy
defaults k3s_demo_http_defaults
    mode tcp
    log global
    option tcplog
    option logasap
    timeout connect 5s
    timeout client 1m
    timeout server 1m

frontend k3s_demo_http from k3s_demo_http_defaults
    bind 10.77.0.1:80
    default_backend k3s_traefik_nodes

backend k3s_traefik_nodes from k3s_demo_http_defaults
    balance roundrobin
    option log-health-checks
    server k3s-1 10.77.0.11:80 check inter 2s fall 2 rise 2
    server k3s-2 10.77.0.12:80 check inter 2s fall 2 rise 2
    server k3s-3 10.77.0.13:80 check inter 2s fall 2 rise 2
```

Validate the whole HAProxy configuration, then reload it:

```sh
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
sudo systemctl is-active haproxy
```

Test the single host address while preserving the Ingress Host header:

```sh
for request in $(seq 1 10); do curl --include --fail --show-error --resolve 'whoami.k3s-lab.test:80:10.77.0.1' http://whoami.k3s-lab.test/; done
```

Each response should be HTTP `200` and identify a `whoami` Pod. HAProxy chooses a Traefik node for each new TCP connection; the Ingress Host header then selects the Kubernetes Service route. For normal use without `curl --resolve`, configure a local or private DNS record for `whoami.k3s-lab.test` that points to `10.77.0.1`. This provides a stable host-side lab address, not host-level availability: all HAProxy traffic still depends on the same physical host.

## Logs and health checks

Follow `/var/log/haproxy.log` while testing. The TCP health checks mark a node listener down after two failed checks and up after two successful checks. They do not check the Traefik Pod, Ingress rule, or `whoami` readiness. The HTTP request tests validate those layers. With TCP pass-through, HAProxy sees connections and backend selection but not HTTP response status or body.

## Roll back only the demo HTTP endpoint

Inspect UFW rule numbers immediately before deleting the rule; numbers can change after each deletion:

```sh
sudo ufw status numbered
read -r -p 'UFW rule number for K3s demo HTTP: ' rule_number
test -n "$rule_number"
sudo ufw delete "$rule_number"
```

Use `sudoedit /etc/haproxy/haproxy.cfg` to remove only `k3s_demo_http_defaults`, `k3s_demo_http`, and `k3s_traefik_nodes`. Validate and reload the full file, preserving the API sections and any unrelated HAProxy configuration:

```sh
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
```

## Roll back the K3s API endpoint

The API endpoint is required while clients or joiners use `https://10.77.0.1:6443`. First point those clients at a valid API endpoint or stop using them, then inspect the numbered rules and remove only the rule with comment `K3s API via HAProxy (lab only)`:

```sh
sudo ufw status numbered
read -r -p 'UFW rule number for K3s API: ' rule_number
test -n "$rule_number"
sudo ufw delete "$rule_number"
```

Remove only `k3s_api_defaults`, `k3s_api`, and `k3s_api_servers` from the configuration. Keep any demo HTTP sections that are still in use. Validate and reload:

```sh
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
```

Do not restore a backup over later intentional HAProxy changes. Removing the HAProxy package is optional and outside this lab's cleanup because the package and service are host-owned and may serve other configurations. Terraform cleanup does not remove host-owned HAProxy configuration or UFW rules.
