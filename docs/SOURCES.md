# Sources and references

All the techniques in this workshop are public and well-documented security
knowledge. The list below is what our research and the exercises are based
on.

## Container isolation fundamentals
- Linux man pages: `namespaces(7)`, `capabilities(7)`, `cgroups(7)`, `user_namespaces(7)`,
  `nsenter(1)`, `seccomp(2)`. https://man7.org/linux/man-pages/
- Docker Docs - *Runtime privilege and Linux capabilities*.
  https://docs.docker.com/engine/containers/run/#runtime-privilege-and-linux-capabilities
- Docker Docs - *Docker security*.
  https://docs.docker.com/engine/security/
- Docker Docs - *Protect the Docker daemon socket* (TLS on the API).
  https://docs.docker.com/engine/security/protect-access/

## Container escape techniques
- HackTricks - *Docker Breakout / Privilege Escalation* (mounted socket,
  privileged, capabilities, `release_agent`, `core_pattern`).
  https://hacktricks.wiki/en/network-services-pentesting/2375-pentesting-docker.html
- Trail of Bits - *Understanding Docker container escapes*.
  https://blog.trailofbits.com/2019/07/19/understanding-docker-container-escapes/
- Snyk - container escape / breaking out of Docker write-ups:
  - *Leaky Vessels: Docker and runc container breakout vulnerabilities* (overview).
    https://snyk.io/blog/leaky-vessels-docker-runc-container-breakout-vulnerabilities
  - *Leaky Vessels deep dive: escaping from Docker one syscall at a time*.
    https://snyk.io/blog/leaky-vessels-container-vuln-deep-dive
  - *CVE-2024-23653: BuildKit build-time container breakout*.
    https://snyk.io/blog/cve-2024-23653-buildkit-grpc-securitymode-privilege-check
- NCC Group - container capability abuse and hardening:
  - Aaron Grattafiori, *Understanding and Hardening Linux Containers* (covers
    `CAP_SYS_ADMIN` and the risk of individual capabilities in depth).
    https://www.nccgroup.com/research/understanding-and-hardening-linux-containers/
    - PDF: https://nccgroup.com/media/eoxggcfy/_ncc_group_understanding_hardening_linux_containers-1-1.pdf
  - Jesse Hertz, *Abusing Privileged and Unprivileged Linux Containers* (PDF).
    https://nccgroup.com/media/bjobstnx/_container_whitepaper.pdf
- Felix Wilhelm (@_fel1x) - the well-known privileged cgroup `release_agent` PoC
  (cgroup v1). Original tweet (July 2019):
  https://twitter.com/_fel1x/status/1151487051986087936
  - fuller write-up of the same technique by Alex Chapman:
  https://ajxchapman.github.io/containers/2020/11/19/privileged-container-escape.html
- Sebastian Krahmer - *shocker* (`open_by_handle_at`, `CAP_DAC_READ_SEARCH`), the
  historical arbitrary-host-file-read escape. Exploit-DB (Docker 0.11 VMM-container
  breakout, source header "shocker: docker PoC ... (C) 2014 Sebastian Krahmer"):
  https://www.exploit-db.com/exploits/33808
  - analysis: https://medium.com/@fun_cuddles/docker-breakout-exploit-analysis-a274fff0e6b3

## Recent real-world CVEs (2024–2026) - Levels 6–7
- **CVE-2025-9074** - Docker Desktop: unauthenticated Engine API reachable from
  containers (Level 6). Docker advisory + fix in Desktop 4.44.3.
  https://www.docker.com/blog/ (Aug 2025 security release) ·
  https://nvd.nist.gov/vuln/detail/CVE-2025-9074 ·
  The Hacker News write-up: https://thehackernews.com/2025/08/docker-fixes-cve-2025-9074-critical.html
- **CVE-2026-126329 / CVE-2026-126330** - Docker Sandboxes (Nov 2026): local root
  privilege escalation through untrusted state/config directories (High, 7.3), and a
  removed auto-assigned host-port publication that can be silently restored (Low,
  2.4). Fixed in Docker Sandboxes 0.53.0.
  https://nvd.nist.gov/vuln/detail/CVE-2026-126329 ·
  https://nvd.nist.gov/vuln/detail/CVE-2026-126330 ·
  OpenCVE: https://app.opencve.io/cve/?vendor=docker
- **CVE-2025-31133 / CVE-2025-52565 / CVE-2025-52881** - the Nov-2025 `runc`
  breakout trio (symlink/race abuse of mount setup → writes to non-namespaced
  `/proc`). CNCF technical overview:
  https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/ ·
  https://nvd.nist.gov/vuln/detail/CVE-2025-31133
- **CVE-2024-21626** - "Leaky Vessels": `runc` `WORKDIR`/leaked-fd container
  breakout (+ BuildKit CVE-2024-23651/-23652/-23653). Snyk disclosure:
  https://snyk.io/blog/cve-2024-21626-runc-process-cwd-container-breakout/ ·
  Red Hat RHSB-2024-001: https://access.redhat.com/security/vulnerability/RHSB-2024-001
- **CVE-2024-41110** - Docker Engine AuthZ-plugin bypass via `Content-Length: 0`.
  https://github.com/moby/moby/security/advisories/GHSA-v23v-6jw2-98fq
- **CVE-2019-5736** - the classic `runc` `/proc/self/exe` overwrite (context for
  why modern `runc` seals itself). https://nvd.nist.gov/vuln/detail/CVE-2019-5736
- **`open_by_handle_at(2)` / the "shocker" technique** (Level 7). Man page:
  https://man7.org/linux/man-pages/man2/open_by_handle_at.2.html · Trail of Bits
  write-up on `CAP_DAC_READ_SEARCH` abuse (see "Understanding Docker container
  escapes", linked above).
- Browse the live Docker CVE list: https://app.opencve.io/cve/?vendor=docker

## Hardening, benchmarks & tooling
- CIS Docker Benchmark. https://www.cisecurity.org/benchmark/docker
- NIST SP 800-190 - *Application Container Security Guide*.
  https://csrc.nist.gov/pubs/sp/800/190/final
- `docker-bench-security`. https://github.com/docker/docker-bench-security
- Trivy (image + misconfig scanning). https://github.com/aquasecurity/trivy
- Falco (runtime detection). https://falco.org/
- Tetragon (eBPF runtime enforcement). https://github.com/cilium/tetragon

## Enumeration tools referenced
- `amicontained` (Jess Frazelle). https://github.com/genuinetools/amicontained
- `deepce` - Docker Enumeration & Escalation. https://github.com/stealthcopter/deepce
- `linpeas` / PEASS-ng. https://github.com/carlospolop/PEASS-ng

## Stronger isolation alternatives (competing products)
- Podman / rootless containers. https://podman.io/
- gVisor (`runsc`). https://gvisor.dev/
- Kata Containers. https://katacontainers.io/
- Firecracker microVMs. https://firecracker-microvm.github.io/
- Sysbox (secure nested/Docker-in-Docker runtime). https://github.com/nestybox/sysbox

## Lab building blocks
- `docker:dind` official image (Docker-in-Docker). https://hub.docker.com/_/docker
- `alpine` official image. https://hub.docker.com/_/alpine
- `socat`, used to open the engine on TCP for Level 3. https://linux.die.net/man/1/socat
