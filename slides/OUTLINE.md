# Presentation script and run guide — Escape the Container

The whole details walkthrough of the lab is in
[`../WORKSHOP_GUIDE.md`](../WORKSHOP_GUIDE.md), the full solutions are in
[`../docs/SOLUTIONS.md`](../docs/SOLUTIONS.md), and the research background is in
the [README](../README.md).

---

## How we start the workshop (step by step)

Do this in order. The first minutes decide if the room follows us or not.

1. **Before the room fills up:** open the slides, and have one laptop ready with
   the lab already started (`./lab.sh up` finished). The first `up` downloads two
   images and takes a few minutes, so we do not want to do that live in front of
   everyone.
2. **Say the one rule up front:** nobody attacks their real laptop, everything
   happens inside a throwaway container. We repeat this on the safety slide, but it
   calms people to hear it early.
3. **Split by operating system:** tell the Windows people to use PowerShell with
   `.\lab.ps1`, and the macOS/Linux people to use `./lab.sh`. This saves a lot of
   confusion later.
4. **Let everyone run `up` now** (or check that they did it before). While it
   builds, we start the theory part, so the download happens in the background.
5. **Put people in pairs.** One drives (types), one reads the guide, and they swap
   each level. Pairs also matches the group-of-2 structure of the course.
6. **Keep the theory short.** The real learning is in the lab. We aim for about 10
   minutes of talking, then we flip to hands-on.

---

## Timing (about 60–75 minutes)

| Time | Part | What happens |
|---|---|---|
| 0–5 | Hook and setup check | The poll question, and everyone starts `./lab.sh up`. |
| 5–15 | Short theory | Slides 3 to 7. Keep it to about 10 minutes. |
| 15–20 | Quiz | The 7 questions below. Kahoot, hands, or paper. |
| 20–55 | Exercises (levels 1–7) | Pairs work through the levels, we walk around and help. |
| 55–65 | Debrief per level | What was wrong, why it worked, how to prevent it. |
| 65–75 | Wrap-up and Q&A | The one line, the checklist, questions. |

A realistic goal: everyone finishes levels 1 to 3, most do 4 and 5, and the faster
groups reach 6 and 7. We do not need everyone to finish all seven, we can show 6
and 7 in the debrief.

---

## The slides, with what to say

### Slide 1 — Title
**On the slide:**
- Escape the Container
- ESD 2026 · Group 12 · SEBIVenlo
- "A container is only as separated as the options you start it with."

**What we say:** Welcome, we are Group 12, and today we look at container escapes.
The one sentence on the slide is basically the whole workshop in one line. We will
come back to it at the end, and by then it should make full sense. The plan is a
little bit of theory and then a lot of hands-on, where everyone breaks out of
containers themselves.

---

### Slide 2 — Hook
**On the slide:**
- Quick poll: is a Docker container a security boundary?
- Spoiler: by default it is more of a convenience boundary.
- Today: you break out of 7 of them.

**What we say:** Let us start with a quick question, hands up: who thinks a Docker
container is a real security boundary, something you can safely put untrusted code
in? (Take the vote, count hands.) It is a very normal thing to believe, and it is
also where a lot of real problems come from. The honest answer is: by default a
container is more of a convenience boundary than a security boundary. It keeps
things tidy and separated for normal use, but it is not a strong wall. To show
this, today everyone will break out of seven containers that were started in a
risky way.

---

### Slide 3 — What is a container, really?
**On the slide:**
- Not a VM. No second kernel, nothing like a real wall.
- Just a normal process on the host that looks separated.
- Diagram: one kernel, many "separated" processes.

**What we say:** First we need a correct picture of what a container actually is,
because the wrong picture is where the danger starts. A container is not a small
computer and not a virtual machine. A virtual machine has its own kernel and the
hardware keeps it apart. A container does not. A container is just a normal program
running on the same system and the same kernel as everything else. The separation
you see is not a real wall, it is more like a set of settings that make the program
*look* like it is alone. If you remember one thing from this slide: all containers
on a machine share the one kernel.

---

### Slide 4 — The disguise: 4 kernel features
**On the slide:**
- **Namespaces** — private view of processes, mounts, network, users.
- **Capabilities** — root split into about 40 smaller permissions.
- **cgroups** — resource limits.
- **seccomp / AppArmor** — block certain system calls and actions.
- Weaken any one of them and the separation leaks.

**What we say:** So what makes a container look separated? Mostly four features from
the Linux kernel. First, namespaces. They give the container its own private view
of things like the running processes, the files and the network. Two programs in
different namespaces simply do not see the same things. Second, capabilities.
Normally root can do everything, and Linux splits that power into around 40 smaller
permissions, and a normal container only keeps a few of them. Third, cgroups, which
just limit how much CPU and memory a container may use. And fourth, seccomp and
AppArmor, which block certain actions and system calls that the container should
not be allowed to do. The important part: each of these is a separate setting, and
if you weaken even one of them, the separation starts to leak. Every level today is
one example of exactly that.

---

### Slide 5 — What is a "container escape"?
**On the slide:**
- Reach something on the host that was not separated: a mount, a socket, a shared
  namespace, or one permission that is too strong. Then go through it.
- Attacker side: one hacked container becomes root on the whole machine.
- Defender side: know the mistakes, close them.

**What we say:** Now we can define the word escape. A container escape means you
find one spot where the container can reach something on the host that was not
properly separated, and you go through it. That spot is usually one of four things:
a folder that was mounted in, a socket that was shared, a namespace that is shared
with the host, or one permission that is too strong. From the attacker side, this
turns one hacked container, for example a bug in a web app, into control over the
whole machine. From the defender side, which is really our side today, the goal is
to recognise these mistakes and close them. We learn the attack so we can prevent
it.

---

### Slide 6 — Why it matters (LG1)
**On the slide:**
- Containers run CI/CD, Kubernetes, multi-tenant SaaS, basically everywhere.
- Real incidents are rarely fancy 0-days, usually just missing safety settings.
- Stronger options exist (rootless/Podman, gVisor, Kata/Firecracker small VMs),
  but they are heavier. Most breaches are plain Docker set up wrong.

**What we say:** Why does this matter in practice? Because containers are
everywhere now: build systems, Kubernetes, and services where many customers share
the same machines. In all of these, people often trust the container as a security
boundary. And when something goes wrong in the real world, it is almost never a
fancy unknown exploit. It is usually just a missing safety setting, exactly the
kind we show today. There are stronger options that give real separation, like
rootless Docker, gVisor, or small lightweight VMs like Kata and Firecracker, but
they are heavier and slower, so many teams do not use them. That is why most
breaches are still just normal Docker that was set up wrong.

---

### Slide 7 — The lab is safe
**On the slide:**
- Docker-in-Docker: you escape onto a throwaway "victim host", never your laptop.
- `./lab.sh up` → `enter` → escape → `submit` → `down`.
- Ethics: only your own or allowed systems. You learn the attack to defend.

**What we say:** Before we start, the safety part, and this is important so nobody
is nervous. The lab uses Docker-in-Docker. That means `./lab.sh up` starts one
throwaway container that runs its own Docker inside it, and we call that the victim
host. Every container you enter is started inside that victim host, so when you
escape, you land on the victim host, not on your real laptop. When you run
`./lab.sh down`, the whole thing is deleted. The normal flow is: `up` once, then
`enter` a level, escape it, `submit` the flag you found, and `down` at the end. One
more thing, the ethics: these techniques are only for your own systems or systems
you are allowed to test. Doing this to machines you do not own is illegal. We learn
the attack so we can defend.

---

### Slide 8 — The 7 challenges (tease, do not spoil)
**On the slide:**
1. Whole host mounted in
2. Mounted Docker socket
3. Docker API on an open TCP port
4. `--privileged --pid=host`
5. Just two permissions (no `--privileged`!)
6. A normal container, but the platform exposed the API (CVE-2025-9074, 2025)
7. One permission (`DAC_READ_SEARCH`) reads the whole disk

**What we say:** Here are the seven challenges, and we only tease them, we do not
spoil the solutions. The nice part of the lab is that every level runs the exact
same, boring container image. The only thing that changes is *how* it is started.
Levels 1 to 5 are the classic setup mistakes. Levels 6 and 7 are newer and come
from real security problems from 2024 and 2025. Level 6 is special: the container
is completely normal, nothing is wrong with it, and it can still take the host,
because the platform itself had a bug. And Level 7 shows that even one single
permission that looks small can be enough. You will see all of this yourself in a
moment.

---

### Slide 8b — The scarier CVEs we only talk about (not run)
**On the slide:**
- **November 2025 `runc` group** (CVE-2025-31133 / -52565 / -52881): symlink and
  timing tricks make `runc` write to sensitive kernel files; one even gets around
  AppArmor/SELinux.
- **Leaky Vessels** (CVE-2024-21626): a leaked file reference plus `WORKDIR` puts
  you on the host filesystem.
- **CVE-2024-41110**: a `Content-Length: 0` request skips Docker's authorization
  plugins (score 9.9).
- Why not hands-on? They need a broken runtime on purpose, and installing one in a
  lab is the mistake we are warning against.

**What we say:** There are also some newer bugs that are more dangerous than our
levels, and we want to mention them, but we do not run them. In our levels, Docker
itself works correctly and a person just gave it bad options. In these CVEs, the
runtime itself, the low-level program that starts containers called `runc`, had the
bug. So even a correctly started container could be at risk. The November 2025
`runc` group uses symlink and timing tricks to make `runc` write to sensitive
kernel files, and one of them even gets around AppArmor and SELinux. Leaky Vessels
from 2024 uses a leaked file reference to put your process directly on the host
filesystem. And there is an engine bug where a request with an empty body skips the
permission checks. We do not run these on purpose, because to run them you would
have to install a known broken runtime, and that is exactly the kind of bad idea
this workshop warns against. The details are in Appendix A of the guide.

---

### Slide 9 — Quiz (before we start)
**On the slide:**
- 7 quick questions (see the Quiz section below).

**What we say:** Before we go into the lab, a short quiz, just to wake everyone up
and to set up the exercises. It is not a test, there are no grades, so just shout
the answers or raise your hand. (Run the 7 questions from the Quiz section below.)

---

### Slide 10 — Go (flip the classroom)
**On the slide:**
- In pairs, follow `WORKSHOP_GUIDE.md`, hints are included.
- Facilitators walk around and help.

**What we say:** Now it is your turn, this is the main part. Work in pairs and
follow the workshop guide, it has every level with hints that you can open step by
step. Try the hints before you ask us, and try to solve a level before you look at
the full solution. We will walk around the whole time, so if you are stuck, just
wave and we come over. Start with Level 1 and go in order, the levels build on each
other a little bit.

---

### Slide 11 — Debrief (after)
**On the slide:**
- Per level: what was wrong, why it worked, how to prevent it.

**What we say:** Let us quickly go through the levels together, now that everyone
has tried them. (For each level, keep it to three short points: what was the wrong
setting, why did the escape work, and how would you prevent it. Use the "Why this
works and how to stop it" parts from the guide.) Even if a group did not reach
Level 6 and 7, we show them here, because they are the most interesting and the
most modern ones.

---

### Slide 12 — Defensive checklist
**On the slide:**
- `--cap-drop=ALL`; no `--privileged`; treat one "small" permission as almost root.
- Do not mount `docker.sock` or host paths.
- No Docker API without login, and **update the platform** so it does not open one
  for you (CVE-2025-9074).
- **Update `runc`/Docker, and only run images and builds you trust** (Leaky
  Vessels, the runc group).
- seccomp/AppArmor on; rootless or user namespaces where you can.
- gVisor/Kata for untrusted workloads; Falco/Trivy to watch and check.

**What we say:** So what do you actually do with all of this? Here is the short
checklist. Drop all permissions by default and add back only what the app really
needs, and never use `--privileged` unless you really must. Do not mount the Docker
socket or host folders into a container. Do not open the Docker API without a login,
and keep Docker updated so the platform does not open it for you, like in Level 6.
Also update `runc` and only run images and builds you trust, because the runtime
gets its own bugs too. Keep seccomp and AppArmor on, use rootless or user
namespaces where you can, and for really untrusted workloads think about stronger
options like gVisor or Kata. The point is not to memorise every line, it is to see
that most of these are just "do not remove the safety settings".

---

### Slide 13 — Takeaway and sources
**On the slide:**
- "A container is only as separated as the options you start it with."
- Full references: `docs/SOURCES.md`. Questions?

**What we say:** And that brings us back to the one sentence from the start: a
container is only as separated as the options you start it with. The exact same
image was a safe prison or a wide open door, depending only on how it was run. All
our sources are in the sources file if you want to read more. Thank you, and now we
are happy to take questions.

---

## Quiz (with answers)

1. **True or false: a Docker container has its own kernel.**
   *False. It shares the host kernel. The separation is namespaces, cgroups and
   capabilities.*
2. **What does mounting `/var/run/docker.sock` into a container give an attacker?**
   *Basically root on the host (they can start a container that mounts `/`).*
3. **Which is more dangerous: `--privileged`, or `--cap-add=SYS_ADMIN`?**
   *A bit of a trick question. `--privileged` includes `SYS_ADMIN` and more, but a
   single too-strong permission can already be enough (Level 5). The label is not
   the point.*
4. **Why does the classic cgroup `release_agent` escape not work on this laptop?**
   *It needs cgroup v1, and modern systems use cgroup v2.*
5. **Name two ways to make a container safer against these escapes.**
   *Any of: `--cap-drop=ALL`, no `--privileged`, do not mount the socket, keep
   seccomp/AppArmor on, rootless/Podman, gVisor/Kata, TLS on the API.*
6. **A container has no mounts, no capabilities, is not privileged, and runs as a
   normal user. Can it still take the host? (CVE-2025-9074 / Level 6)**
   *Yes, if the platform leaves the engine API reachable from it. The container's
   own hardening does not matter when the root-level control channel is open.
   Update the platform, and never bind the API to a reachable address.*
7. **Is one single permission "safe"? (CAP_DAC_READ_SEARCH / Level 7)**
   *No. `DAC_READ_SEARCH` unlocks `open_by_handle_at`, which turns one read-only
   mount into read access to the whole disk behind it. Treat it as almost root.*

---

## While people work on the levels (how we help)

- Point people to the hints in `WORKSHOP_GUIDE.md` before we give a spoken hint.
- Things people often get stuck on:
  - **Level 3:** finding the host IP. Remind them of `ip route` and `default`.
  - **Level 4/5:** the many `nsenter` letters. Write `nsenter -t 1 -m -u -i -n -p`
    on the board and explain each letter.
  - **Level 6:** finding the host IP is the same `ip route` trick as Level 3. The
    surprise is that the container itself is completely normal, the API just
    answers. Let them try plain `curl` first (that is the real CVE), then show the
    `docker -H` way.
  - **Level 7:** the idea (handles ignore folders and mounts) is the hard part, not
    the command. `handle-read` with no arguments solves it. Spend the time on *why*
    inode 2 plus `CAP_DAC_READ_SEARCH` gets past the mount.
- If a level acts up: `./lab.sh reset <n>`. If the whole lab is stuck:
  `./lab.sh down && ./lab.sh up` (the flags change, that is fine).

---

## Safety points (say these out loud)

- Nobody attacks their real laptop. Everything happens inside a throwaway
  Docker-in-Docker "victim host" that `./lab.sh down` deletes.
- These techniques are illegal against systems you do not own. Frame it as
  defensive knowledge: you learn the attack so you can prevent it.

---

## If something breaks (troubleshooting)

| Symptom | Fix |
|---|---|
| `./lab.sh up` slow the first time | It is pulling `docker:28-dind` and `alpine`; later runs are cached. |
| "inner Docker engine did not come up" | `docker compose logs host`; make sure your Docker allows privileged containers; run `up` again. |
| `enter` gives `sh` instead of `bash` | Harmless fallback; bash is in the image, both work. |
| Level 3 cannot reach `:2375` | `./lab.sh reset 3` runs the socat setup on the host again. |
| Level 6 cannot reach `:2375` | Same socat listener as Level 3; `./lab.sh reset 6`. The container is supposed to be normal, do not "fix" it. |
| Level 7 `handle-read` errors on `open_by_handle_at` | It needs the loop disk; `./lab.sh reset 7` rebuilds it. If `mount -o loop` is refused, your Docker is not allowing privileged DinD, same requirement as Levels 4/5. |
| Want a clean start between classes | `./lab.sh down && ./lab.sh up`. |
| Windows: "running scripts is disabled" | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, then run `.\lab.ps1` again. |
| Windows: `.\lab.ps1 enter` shows no colours or an odd prompt | Use Windows Terminal or PowerShell 7; the classic consoles work but look plainer. |
| Git Bash: `enter` says "not a TTY" | Put `winpty` in front, or just use `lab.ps1` or WSL2. |

---

## Who presents what (LG3)

A simple split so everyone talks and everyone has commits:

- **Person A:** Slides 1 to 4 (intro and theory) + the README/research part.
- **Person B:** Slides 5 to 8b (escapes, why it matters, the challenges, the CVEs).
- Both together: run the hands-on part, walk around and help, and share the
  debrief and the checklist at the end.

Adjust this to the real group size. The main goal for LG3 is that everyone speaks
and everyone has visible contributions in the repository (commits, issues, PRs).
