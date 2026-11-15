# Escape the Container

> A hands-on workshop about container escapes: how the separation around a Docker
> container actually works, how common setup mistakes break it open, and how you
> stop that.
>
> **ESD 2026 · Group 12 · Fontys**

A safe lab you start with one script, a guide with exercises, an answer key,
and the research behind it.

| I want to… | Go to |
|---|---|
| Just start hacking | [Quick start](#quick-start) |
| Learn the theory and do the exercises | [`WORKSHOP_GUIDE.md`](WORKSHOP_GUIDE.md) |
| See the full solutions | [`docs/SOLUTIONS.md`](docs/SOLUTIONS.md) |
| Run the workshop (presentation script + plan) | [`slides/OUTLINE.md`](slides/OUTLINE.md) |
| Understand the research | [Background](#background-lg1) below |

---

## Quick start

**You need:** Docker and the Docker Compose plugin.
Everything the lab needs comes as Docker images.

- **Windows:** Docker Desktop (with the WSL2 backend, which is the default). Use
  the **`lab.ps1`** launcher from a normal PowerShell window.
- **macOS:** Docker Desktop. Use **`./lab.sh`** from the Terminal.
- **Linux:** Docker Engine and the Compose plugin. Use **`./lab.sh`**.

> The lab runs the same on all three. Docker Desktop gives you a Linux VM, and the
> whole lab (and every escape) happens inside that VM.

**Linux / macOS:**
```bash
git clone https://github.com/FontysVenlo/esd-2026-workshop-g12
cd esd-2026-workshop-g12

./lab.sh up          # build and start the lab (first run pulls two images)
./lab.sh levels      # see the 7 escape challenges
./lab.sh enter 1     # go into level 1's container, now escape it
# ...find the flag on the host, then:
./lab.sh submit 1 'ESD26{...}'
./lab.sh down        # stop and wipe everything when you are done
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/FontysVenlo/esd-2026-workshop-g12
cd esd-2026-workshop-g12

.\lab.ps1 up          # build and start the lab (first run pulls two images)
.\lab.ps1 levels      # see the 7 escape challenges
.\lab.ps1 enter 1     # go into level 1's container, now escape it
# ...find the flag on the host, then:
.\lab.ps1 submit 1 'ESD26{...}'
.\lab.ps1 down        # stop and wipe everything when you are done
```
> First time only, if PowerShell blocks the script:
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

Every level puts you inside a container. The goal is always the same: break out
of the container, read `/flags/levelN.txt` on the host, and submit the
`ESD26{...}` flag you found.

---

## Is this safe to run on my laptop?

Yes. You never attack your own machine.

The lab uses Docker-in-Docker (DinD). `./lab.sh up` starts one throwaway "victim
host" container that runs its own Docker engine inside. Every container you enter
is started by that inner engine, so when you escape, you land on the victim host's
filesystem (a container called `victim-host`), not on your real system.

```
your laptop  (your real files are here, untouched)
└─ victim-host         <- a throwaway DinD container = "the host" you escape ONTO
   │   (holds /flags/levelN.txt)
   └─ levelN           <- the vulnerable container you start INSIDE
          escape ───────────────────────► read the flag on victim-host
```

`./lab.sh down` (or `.\lab.ps1 down`) deletes the victim host, its volume, and
everything you did. We checked this: after an escape, `hostname` says
`victim-host`, and your real home folder is nowhere to be seen.

> **Ethics and scope.** These techniques are for your own lab and for testing you
> are allowed to do. Running container escapes against machines you do not own is
> illegal. See [Responsible use](#responsible-use).

---

## The 7 challenges

Every level runs the exact same, boring Alpine image. The only thing that changes
is *how* the container is started. That is the whole lesson: a container is only
as separated as the options you start it with.

| # | Setup mistake | Where you see this in the real world |
|---|---|---|
| 1 | `-v /:/mnt/host` - whole host mounted in | Mounting host folders "for convenience" |
| 2 | `-v /var/run/docker.sock` - Docker socket exposed | CI runners, "docker-in-docker" tricks |
| 3 | Docker engine API on TCP `:2375`, no login | Thousands are open on the public internet |
| 4 | `--privileged --pid=host` | "Just make it work" privileged containers |
| 5 | `--cap-add=SYS_ADMIN,SYS_PTRACE --pid=host` (no `--privileged`!) | Too many permissions |
| 6 | Engine API reachable from a **normal** container | **CVE-2025-9074** (Docker Desktop, 2025) |
| 7 | `--cap-drop=ALL --cap-add=DAC_READ_SEARCH` + one mount | One "small" permission = read the whole disk |

Levels 1 to 5 are the classic setup mistakes. Levels 6 and 7 come from recent
CVEs. The most dangerous ones that sit in the runtime itself (the November 2025
`runc` group, Leaky Vessels) are in the [research section below](#recent-real-world-container-escape-cves-20242025)
and in the guide's Appendix A. We only talk about those instead of running them,
and the reason why is itself part of the lesson.

Full walkthrough and fixes: [`WORKSHOP_GUIDE.md`](WORKSHOP_GUIDE.md).

---

## Background (LG1)

### What actually separates a container?

A container is not a virtual machine. It is a normal Linux process on the host
kernel, wrapped in a few kernel features that make it *look* separated:

- **Namespaces** - give the process its own view of processes, mounts, network,
  users, hostname, IPC. (`man 7 namespaces`)
- **Control groups (cgroups)** - limit resources like CPU and memory.
- **Capabilities** - split root's power into about 40 pieces (for example
  `CAP_SYS_ADMIN`). A container normally only gets a few. (`man 7 capabilities`)
- **seccomp** - filters which system calls the process may use (Docker ships a
  default block-list).
- **LSMs (AppArmor / SELinux)** - extra access rules on top.

All of these use the same one kernel. Weaken any of them and the separation
starts to leak. That is what every level in this lab shows.

### Why is it useful to learn container escapes?

Containers are everywhere (CI/CD, Kubernetes, multi-tenant SaaS). Teams often
treat them as a security boundary, but by default they are more of a convenience
boundary. Knowing the escapes helps you:

- **As attacker/pentester:** turn one hacked container (for example "code
  execution in the web app") into control over the whole machine.
- **As defender/DevOps:** recognise the setup mistakes that make this easy, and
  close them.

### Related technologies (pros and cons)

| Approach | What it is | Pros | Cons |
|---|---|---|---|
| **Docker (default runc)** | Namespaces + cgroups + caps + seccomp | Fast, everywhere, almost native speed | Shares host kernel; a wrong setting means escape |
| **Rootless Docker / Podman** | No root daemon, runs as normal user via user namespaces | No root daemon; an escape lands as a normal user | Some features limited; not perfect |
| **gVisor (runsc)** | A kernel in user space that catches the system calls | Much smaller attack surface | Slower; some system calls not supported |
| **Kata Containers / Firecracker** | Each container in a small lightweight VM | Real VM-level separation | Heavier; needs virtualization |
| **seccomp / AppArmor / SELinux hardening** | Tighten the default runc sandbox | Cheap, extra layer | Easy to turn off ("it broke my app") |

The takeaway for the workshop: stronger separation does exist (small VMs, gVisor,
rootless), but most real incidents are just plain Docker started with the safety
options removed, which is exactly the cases in this lab.

### Recent real-world container-escape CVEs (2024–2026)

A wrong setup (the lab's Levels 1 to 7) is the normal case, but the runtime and
the platform also get their own CVEs, where even a correctly started container can
be at risk. These are the "more dangerous" ones. In the workshop we only *talk*
about them, we do not run them, because to run them you would need a broken version
of the runtime on purpose, and installing a known broken `runc` on a laptop that
people use for real is exactly the kind of thing this workshop warns against.
(Level 6 is the one recent bug where we can rebuild the important part safely.)
#### CVE-2026-126329 / CVE-2026-126330** - Docker Sandboxes (Nov 2026): local root
  privilege escalation through untrusted state/config directories (High, 7.3), and a
  removed auto-assigned host-port publication that can be silently restored (Low,
  2.4). Fixed in Docker Sandboxes 0.53.0.

#### The runc breakout group - November 2025 (CVE-2025-31133, -52565, -52881)
`runc` is the low-level program that actually starts containers under Docker and
Kubernetes. In November 2025 three related escapes were found (each with a score
of about 7.3, rated High). They share one idea: they trick `runc` during its own
setup, using symlinks and timing, so that a write which should go to a harmless
place goes to a sensitive kernel file instead:

- **CVE-2025-31133** - replace `/dev/null` with a link to a kernel file. `runc`
  then mounts that file writable. Point it at the right spot and you get a
  breakout, or you can crash the host.
- **CVE-2025-52565** - a timing trick on the `/dev/console` mount that again gives
  writable access to sensitive kernel files.
- **CVE-2025-52881** - send writes meant for one path to a real kernel file, and
  this one even gets around AppArmor/SELinux. The most advanced of the three.

These can be triggered by bad mount settings, including a `RUN --mount=…` line in
a Dockerfile. So even "I only build untrusted images, I do not run them" is enough
to be at risk. **Fix:** `runc` 1.2.8 / 1.3.3 / 1.4.0-rc.3 or newer. **Reduce the
risk:** use user namespaces (so container-root is not host-root), do not run as
root, and only build and run images you trust. Note that AppArmor/SELinux do not
fully stop -52881.

#### Leaky Vessels - January 2024 (CVE-2024-21626, the famous one)
A leak of an internal file reference in `runc` 1.1.11 and older, connected to the
`WORKDIR` instruction. `runc` accidentally left open a reference that pointed into
the **host** filesystem. If you then set the working directory of a container to
`/proc/self/fd/<N>`, your program starts directly on the host filesystem, where
you can read or overwrite host files (for example replace a host program). Score
8.6. It came together with three BuildKit bugs (CVE-2024-23651/-23652/-23653)
about build-time mounts and cache. **Fix:** `runc` 1.1.12, BuildKit 0.12.5. A
simple way to think about it: one leaked file reference is like a tunnel through
all the separation at once.

#### Docker engine permission bypass - July 2024 (CVE-2024-41110)
An old 2018 bug came back: an API request with `Content-Length: 0` could skip the
authorization plugins, so a request that a plugin should have blocked was still
sent to the engine and done. Score 9.9. It only affects setups that use such
plugins, but for those it is a full bypass. **Fix:** engine 23.0.14 / 27.1.0.

#### CVE-2025-9074 - the one we actually run (Level 6)
Docker Desktop made the engine API reachable from every container without any
login (score 9.3, August 2025). This is exactly what we rebuilt safely as
[Level 6](WORKSHOP_GUIDE.md#level-6---the-platforms-own-back-door). **Fix:** Docker
Desktop 4.44.3.

#### The classic one for context - CVE-2019-5736
The escape that made everybody take `runc` seriously. A bad container overwrote
the host's copy of the `runc` program itself, so the next time someone did
`docker exec` or attached, attacker code ran as root on the host. It was fixed six
years ago, and it is the reason modern `runc` makes a sealed in-memory copy of
itself before running. The 2024 and 2025 bugs above had to find new ways around
exactly that fix.

**The common thread:** wrong setup (Levels 1 to 7) is the normal case, but the
runtime and the platform also get their own bugs. That is why "update `runc` and
Docker quickly" and "only run images and builds you trust" belong on the checklist
right next to `--cap-drop=ALL`.

### Escapes we only discuss (they need a vulnerable kernel or runtime)

Some famous escapes are left out of the hands-on part on purpose, and the reason
why is actually a good lesson about where the real limits are:

- **cgroup-v1 `release_agent`** - an old escape on privileged containers that
  writes a small program which the kernel then runs on the host. It needs the old
  **cgroup v1**. Modern Linux (including the machine this was built on) uses
  **cgroup v2**, where this trick does not work anymore. A nice example of a fix
  that just ships by default over time.
- **`core_pattern` abuse** (`CAP_SYS_ADMIN`) - you overwrite a kernel setting so
  that a crashing program starts your program instead. This setting is shared with
  the real kernel, so in our nested lab it would reach the *real* machine. That is
  exactly why we do not run it, it would break our "you never touch your laptop"
  promise.
- **Mounting the raw disk** in a privileged container - if the real host disks are
  visible under `/dev`, you can mount the host disk directly. Same containment
  problem in a nested lab.

The point for defence: all of these need something that is shared with the real
kernel, or an old kernel that was not fixed yet. Using several layers (cgroup v2,
seccomp, dropping permissions, user namespaces, gVisor/Kata) closes them.

### Detection and hardening tools worth knowing

- **`amicontained`**, **`deepce`**, **`linpeas`** - list the weaknesses of a
  container (nice to run *inside* a level to see what an attacker sees).
- **CIS Docker Benchmark**, **`docker-bench-security`** - check your config.
- **Trivy / Grype** - scan images and configs for problems.
- **Falco / Tetragon** - notice escape behaviour at runtime (for example a
  container process running `nsenter` or writing `release_agent`).

---

## Repository layout

```
.
├── README.md              ← you are here (overview + research / LG1)
├── WORKSHOP_GUIDE.md       ← participant guide: theory + exercises (LG2)
├── lab.sh                  ← launcher for Linux / macOS
├── lab.ps1                 ← launcher for Windows (PowerShell)
├── docker-compose.yml      ← the DinD "victim host"
├── docs/
│   ├── SOLUTIONS.md        ← full answer key (facilitators)
│   └── SOURCES.md          ← references and sources
├── slides/
│   └── OUTLINE.md          ← presentation script + run guide (quiz, timing, troubleshooting)
└── lab/
    ├── host/               ← the victim-host (DinD) image + facilitator scripts
    ├── vulnerable/         ← the single harmless image every level runs
    └── flags/              ← flags (generated fresh per run; git-ignored)
```

## Command reference

On Windows, use `.\lab.ps1` instead of `./lab.sh`, the commands are the same.

| Command | What it does |
|---|---|
| `./lab.sh up` | Build and start the lab; generate fresh unique flags |
| `./lab.sh levels` | List the 7 challenges |
| `./lab.sh enter <n>` | (Re)create level `<n>` and drop into a shell |
| `./lab.sh start <n>` | (Re)create level `<n>` without attaching |
| `./lab.sh submit <n> <flag>` | Check a flag you found |
| `./lab.sh reset <n>` | Rebuild level `<n>` from scratch |
| `./lab.sh status` | Show what is running |
| `./lab.sh down` | Stop and wipe the whole lab |

---

## Responsible use

This material is only for education and for testing you are allowed to do: your
own lab, CTFs, or systems where you have written permission. Getting into computer
systems without permission is a crime (for example the Dutch *Computercriminaliteit*
law, the German §202 StGB, the US CFAA). Please be responsible.

## Sources and further reading

See [`docs/SOURCES.md`](docs/SOURCES.md) for the full reference list (Docker docs,
NIST/CIS benchmarks, Trail of Bits, Snyk, HackTricks, man pages, and the specific
escape write-ups this workshop is based on).

## License / attribution

Coursework for the ESD 2026 module. The escape techniques are well-documented
public knowledge; the specific sources are listed in `docs/SOURCES.md` and in
`docs/SOLUTIONS.md`.
