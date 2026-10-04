# Linux Debugging Scenarios

A small, self-contained lab for practicing the **most common Linux
troubleshooting flows** an SRE / DevOps / backend engineer sees in
real life. Each scenario is a single shell script that plants a
realistic fault, plus a built-in `cleanup` sub-command that undoes
the damage.

No hints are given while a scenario is running - the script just
sets the stage. Once the user decides they are done, they re-run
the script with the `cleanup` argument (or simply delete the
generated `.scenario*_build/` and `.scenario*_lab/` directories)
to tear the lab back down.

> The point of these is to build the muscle memory of reaching for
> the right tool before reading a tutorial. Try to solve each one
> with the standard CLI only.

---

## Scenarios at a glance

| # | File                              | Fault                                            | What you practice                                                                  |
|---|-----------------------------------|--------------------------------------------------|------------------------------------------------------------------------------------|
| 1 | `scenario1-cpu-hog.sh`            | A process is consuming huge CPU                  | `top`, `htop`, `ps`, `pidstat`, killing a process                                   |
| 2 | `scenario2-nginx-port-bind.sh`    | nginx won't start because port 80 is taken       | `lsof`, `netstat`, `ss`, reading nginx error log, config validation                |
| 3 | `scenario3-disk-fill.sh`          | `/` is ~90% full because of runaway logs         | `df`, `du`, `find -size`, safe log rotation / deletion                             |
| 4 | `scenario4-network-misconfig.sh`  | App unreachable due to misconfigured network     | `ip`, `ip netns`, routing tables, DNS, `/etc/hosts`                                |
| 5 | `scenario5-memory-leak.sh`        | A process is leaking memory                      | `top` by RES, `ps --sort=-%mem`, `pidstat -r`, `/proc/<pid>/status`                |

---

## Running a scenario

Each script is self-contained. Most do not need root, except where
network namespaces (`scenario4`) or low ports (`scenario2`) are
involved.

```bash
# Example
bash scenario1-cpu-hog.sh
# ... investigate ...
bash scenario1-cpu-hog.sh cleanup
```

The script prints a "READY" banner at the end describing the
problem in plain English. After that, you are on your own.

---

## What each scenario teaches

### 1. CPU consumption by an application
A small C program tight-loops forever; several copies are launched
in the background. Load average climbs and the system feels sluggish.

**Skills you build:**
- Reading `top` / `htop` and understanding CPU% vs load average.
- Using `ps auxf` to see the process tree.
- Using `pidstat 1` to watch CPU usage over time.
- Sending the right signal (`kill -15` then `kill -9`).
- Understanding "this process is not a kernel task, it is userland."

**Why it matters:** In production, runaway CPU is usually either
a tight loop in your own code, an unbounded worker pool, or a
crypto miner someone snuck in. Recognizing the pattern quickly
is half the battle.

---

### 2. nginx won't start because port 80 is bound
A Python `http.server` is already squatting on port 80; the lab
nginx config asks for the same port. `nginx -t` passes, but
`nginx` itself errors out on bind.

**Skills you build:**
- Reading nginx's error log and translating `bind() to 0.0.0.0:80
  failed (48: Address already in use)` into a plan.
- `sudo lsof -i :80`, `sudo ss -ltnp 'sport = :80'`,
  `sudo netstat -anp tcp | grep '\.80 '` - three flavours of
  the same answer.
- Killing the right process (and *not* the one you meant to keep).
- Validating config with `nginx -t` before reloading.
- End-to-end verification with `curl -I`.

**Why it matters:** "Address already in use" is one of the most
common `systemd`-era errors. Being able to identify the squatter
in under a minute is a basic on-call reflex.

---

### 3. Disk full from runaway logs
A lab directory under the repo is bloated with one runaway 250 MB
log file and a couple of decoys. The script does not touch the
real `/` partition; the lab is intended to be inspected with `du`
the same way you would inspect `/var/log`.

**Skills you build:**
- `df -h` to confirm the symptom, then `du -sh /*` or
  `du -ah /var/log | sort -h | tail` to find the culprit.
- Using `find / -xdev -size +100M -type f` to surface huge files
  anywhere on a filesystem.
- Checking for deleted-but-open files with `lsof +L1` (these hold
  space but `du` does not see them).
- Deciding whether to truncate (`> file`) or delete (`rm`).
- Setting up a log rotation policy so it does not happen again.

**Why it matters:** A full `/` will refuse logins, drop writes
from databases, and page the on-call at 3 a.m. Knowing how to
*find* the offender before you *fix* it is the difference
between a five-minute fix and a much longer one.

---

### 4. Application can't be reached (network misconfig)
A real HTTP service runs inside a Linux network namespace, but
the namespace has: no DNS entry for the service's hostname, no
default route, and a sparse `/etc/hosts`. The service is fine -
the network plumbing is the problem.

**Skills you build:**
- Recognizing the difference between "the app is down" and
  "I can't reach the app" (connectivity vs. application health).
- Reading routing tables: `ip route`, `ip a`, `ip netns exec ...`.
- Diagnosing DNS: `/etc/hosts`, `/etc/resolv.conf`,
  `getent hosts <name>`, `dig` / `nslookup`.
- Adding a static route or fixing the missing host entry.
- Understanding that Linux namespaces are a safe way to rehearse
  network surgery without touching production.

**Why it matters:** Most "the app is down" tickets turn out to
be DNS, routing, or firewall issues. This scenario trains you
to peel those layers apart methodically.

---

### 5. Process leaking memory
A small C program `malloc()`s a chunk of RAM every second and
never frees it. Three of them are launched, with the same
process name - only their RSS grows at different rates.

**Skills you build:**
- Sorting `top` / `htop` by `RES` (resident size) or `%MEM`.
- `ps aux --sort=-%mem | head` to rank the worst offenders.
- `pidstat -r 1` to watch RSS grow over time.
- `smem -rs rss` for PSS-aware ranking.
- Reading `/proc/<pid>/status` (`VmRSS`, `VmSize`, `VmData`).
- Killing the right process while leaving siblings alone.

**Why it matters:** A leaking process eventually triggers the
OOM killer, which picks a *victim*, not the *guilty*. Being
able to identify the real leaker from RSS growth - and not
just from process name - is what saves the box.

---

## Philosophy

- **No hand-holding.** The script sets the stage and then steps
  out of the way. You are supposed to feel the same mild panic
  you feel on a real on-call shift.
- **No "real" damage.** Every lab writes to a directory under
  this repo. The host's real `/`, `/var/log`, or running services
  are never touched (scenario 4 uses a network namespace, scenario
  2 binds 80 on the loopback only).
- **Reversible.** Every script has a `cleanup` argument that
  removes everything it created and stops everything it started.
- **Realistic tools.** The lab expects the same CLI you would
  reach for in production: `top`, `ps`, `lsof`, `ss`, `du`, `df`,
  `ip`, `pidstat`, `/proc`. No proprietary dashboards.

The goal is for the user to leave these scenarios with the
quiet confidence of someone who has *already seen* the error
messages they are going to see at 2 a.m.

Happy debugging.
