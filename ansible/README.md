# Ansible — Elasticsearch Host Configuration

This directory contains an Ansible role that configures OS-level settings required to run Elasticsearch in production on Ubuntu hosts. These settings are mandatory — Elasticsearch's bootstrap checks will refuse to start the node if critical ones are missing.

The same settings can be applied manually using `scripts/set_important_es_sysconfig.sh`. The Ansible role exists for when the stack needs to be deployed across multiple hosts consistently and repeatably.


## Why OS Configuration is Required

Elasticsearch is designed to use all available resources on a host. The Linux defaults for several kernel and system parameters are too conservative for a database that manages large memory-mapped files, holds many open file handles, and requires stable low-latency I/O. Without these settings, Elasticsearch either refuses to start (in production mode) or logs warnings and runs with degraded performance (in development mode).

Elasticsearch automatically switches from development mode to production mode when `network.host` is set to anything other than `localhost`. In production mode, failed bootstrap checks are fatal — the node will not start.


## What the Role Configures

### 1. Virtual Memory — `vm.max_map_count`

```
vm.max_map_count = 262144
```

Elasticsearch uses memory-mapped files (mmap) for its index segments via Lucene. The kernel limits how many distinct memory-mapped regions a process can have. The default on most Linux systems is `65530`, which is far too low for a node with many indices and shards.

Setting this to `262144` is the minimum required. It is applied immediately via `sysctl` and persisted in `/etc/sysctl.conf` to survive reboots.

### 2. Disable Swapping

```
vm.swappiness = 1
```

Swapping Elasticsearch's heap to disk causes severe GC pauses and query latency spikes that are extremely difficult to diagnose. Even occasional swapping is harmful.

`vm.swappiness = 1` tells the kernel to avoid swapping except under extreme memory pressure, while avoiding the side effects of setting it to `0` entirely. Combined with `bootstrap.memory_lock: true` in `elasticsearch.yml`, this ensures the JVM heap is never swapped out.

### 3. File Descriptor Limit

```
elasticsearch  nofile  65535
```

Applied via `/etc/security/limits.conf` (or `/etc/security/limits.d/`).

Each Lucene segment requires one or more open file handles, and each index can have hundreds of segments. On a node with many indices, the default limit of `1024` open files is exhausted quickly, causing `Too many open files` errors. The minimum recommended value is `65535`.

### 4. Memory Lock (memlock)

```
elasticsearch  memlock  unlimited
```

Required to allow Elasticsearch to lock its heap in RAM (`bootstrap.memory_lock: true`). Without this, the OS ignores the memory lock request and the heap remains swappable.

### 5. Max Threads — `nproc`

```
elasticsearch  nproc  4096
```

Elasticsearch uses many threads across different thread pools (search, indexing, management, etc.). The default `nproc` limit on some systems is low enough to cause `unable to create native thread` errors under load.

### 6. TCP Retransmission Timeout

```
net.ipv4.tcp_retries2 = 5
```

The default value (`15`) means the kernel retries a failed TCP connection for up to 15 minutes before giving up. In a distributed cluster where a node has gone down, this causes other nodes to wait up to 15 minutes before detecting the failure and initiating recovery.

Setting this to `5` reduces the failure detection window to approximately 6 seconds, allowing the cluster to react to node failures much faster.


## Role Structure

```
ansible/
  roles/
    es-sysconfig/
      tasks/
        main.yml      # applies all settings above
      defaults/
        main.yml      # default variable values (swappiness, limits, etc.)
      handlers/
        main.yml      # sysctl reload handler
  inventory/
    hosts.yml         # target hosts
  site.yml            # top-level playbook
```


## Usage

```bash
# Run against all hosts in inventory
ansible-playbook -i inventory/hosts.yml site.yml

# Run against a specific host group
ansible-playbook -i inventory/hosts.yml site.yml --limit es_nodes

# Dry run (check mode — no changes applied)
ansible-playbook -i inventory/hosts.yml site.yml --check

# Run only tasks tagged with a specific setting
ansible-playbook -i inventory/hosts.yml site.yml --tags vm_max_map_count
```


## Relation to the Setup Script

`scripts/set_important_es_sysconfig.sh` applies the same settings imperatively on a single host. It is useful for quick setup or when Ansible is not available.

The Ansible role is the right tool when:
- The stack runs on more than one physical host
- Hosts need to be reprovisioned consistently (staging, DR environments)
- Changes need to be tracked in version control and applied idempotently

Both the script and the role should stay in sync — if a new setting is added to one, it should be added to the other.


## Reference

Elastic official documentation on required system configuration:
https://www.elastic.co/docs/deploy-manage/deploy/self-managed/important-system-configuration