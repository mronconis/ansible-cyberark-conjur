# AAP + CyberArk Conjur Demo

Demonstrates **Ansible Automation Platform** (Automation Controller) retrieving an SSH private key from **CyberArk Conjur** via the built-in **CyberArk Conjur Secrets Manager Lookup** credential plugin, then running a Job Template that pings a target host.

This lab runs **AWX** locally as the open-source Automation Controller. The Conjur credential model is the same as in Red Hat AAP.

```text
Controller (AWX)
  Project (Git SCM) ──clone──► this repository
  Machine.ssh_key_data ──credential plugin──► Conjur OSS
  Job Template: ansible/playbooks/ping.yml ──SSH──► target VM
```

---

## Prerequisites

| Tool | Notes |
|------|--------|
| Podman | `podman machine start` |
| Vagrant + `vagrant_utm` + UTM (`utmctl` on `PATH`) | Target VM |
| kind + kubectl | Local Controller |
| Python 3.11+, jq, ssh-keygen | Bootstrap helpers |

---

## Usage

```bash
make setup   # Conjur + VM + Controller + credentials / Job Template
make demo    # Launch Job Template → expect successful ping
make status
make down
make clean   # down + wipe generated keys/secrets/VM
```

| | |
|-|-|
| UI | http://127.0.0.1:8088 |
| Login | `controller/.controller.env` |

---

## What the demo proves

1. Controller authenticates to Conjur as `host/ansible/control-node`.
2. Machine credential field `ssh_key_data` is sourced from Conjur (`ansible/target/ssh_private_key`).
3. The playbook has **no** Conjur lookups — secrets are resolved by Controller before the job runs.

Objects created on Controller: Conjur lookup credential, Machine credential, inventory host `target`, Git project (from `origin`), Job Template `conjur-demo-ping`.

The Controller project uses **Git SCM** (`PROJECT_SCM_URL`, default: `git remote get-url origin`). Public HTTPS remotes need no Source Control credential. Override with `PROJECT_SCM_URL` / `PROJECT_SCM_BRANCH` if needed.

---

## Layout

```text
Makefile
scripts/setup.sh          # full lab bootstrap
ansible/playbooks/ping.yml
conjur/                   # Conjur OSS (Podman)
controller/               # AWX on kind + configure/launch
vagrant/                  # target VM
keys/                     # SSH keypair (generated, gitignored)
```

---

## Notes

- From Controller pods, Conjur is `https://host.containers.internal:8443` and the VM is `host.containers.internal:<forwarded-ssh-port>`.
- To use an existing AAP Controller instead of local AWX, set `CONTROLLER_*` in `controller/.controller.env`, ensure Conjur/VM are reachable, then run `controller/scripts/configure.sh` and `make demo`.
- Lab only — do not expose ports `8088`, `8443`, `8080`, or `8432` beyond the workstation.
