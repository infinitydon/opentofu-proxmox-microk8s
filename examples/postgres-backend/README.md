# OpenTofu PostgreSQL state backend

This VM is dedicated to PostgreSQL, which is used solely as OpenTofu remote-state
storage. OpenTofu's native `pg` backend provides transactional state locking.

## Deployed VM

| Setting | Value |
|---|---|
| Proxmox node | `pve` |
| VM ID / name | `169` / `opentofu-state-postgres` |
| Template | `9006` (`ubuntu-24.04-noble-cloudinit`) |
| Storage | `ebenezer-stor1` |
| Disk | 64 GiB |
| CPU | 2 vCPU |
| Memory | 2 GiB maximum, 1 GiB balloon minimum |
| Network | `vmbr0`, static `192.168.88.3/24` |
| Gateway / DNS | `192.168.88.1` |
| PostgreSQL | `192.168.88.3:5432`, TLS required |

The disk expansion is complete: Proxmox reports 64 GiB, the guest sees a 64 GiB
disk and 63 GiB root partition, and the ext4 root filesystem is approximately 61 GiB.

## Credentials and client configuration

The root-only connection string is stored in `/etc/opentofu-backend.env`; it is not
stored in Git. Retrieve it securely from Linux/macOS:

```bash
ssh -i <PATH_TO_BACKEND_VM_SSH_KEY> \
  ubuntu@<POSTGRES_BACKEND_VM_IP> \
  'sudo cat /etc/opentofu-backend.env'
```

Or from PowerShell:

```powershell
ssh -i <PATH_TO_BACKEND_VM_SSH_KEY> ubuntu@<POSTGRES_BACKEND_VM_IP> `
  "sudo cat /etc/opentofu-backend.env"
```

Set `PG_CONN_STR` from that file and use a distinct schema for each independently
managed state. `PG_CONN_STR` is a backend environment variable, not a declaration
in `variables.tf`:

```bash
backend_vm_ip='<POSTGRES_BACKEND_VM_IP>'
backend_ssh_key='<PATH_TO_BACKEND_VM_SSH_KEY>'
export PG_CONN_STR="$(ssh -o BatchMode=yes -i "$backend_ssh_key" \
  "ubuntu@$backend_vm_ip" 'sudo sed -n "s/^PG_CONN_STR=//p" /etc/opentofu-backend.env')"
export PG_SCHEMA_NAME='<UNIQUE_STATE_SCHEMA>'
test -n "$PG_CONN_STR"
tofu init -reconfigure
```

PowerShell equivalent:

```powershell
$BackendVmIp = "<POSTGRES_BACKEND_VM_IP>"
$BackendSshKey = "<PATH_TO_BACKEND_VM_SSH_KEY>"
$StateSchema = "<UNIQUE_STATE_SCHEMA>"

$backendLines = ssh -o BatchMode=yes -i $BackendSshKey `
  "ubuntu@$BackendVmIp" "sudo cat /etc/opentofu-backend.env"
$connectionLine = $backendLines |
  Where-Object { $_ -like 'PG_CONN_STR=*' } |
  Select-Object -First 1
if (-not $connectionLine) { throw "PG_CONN_STR was not returned." }

$env:PG_CONN_STR = $connectionLine.Substring('PG_CONN_STR='.Length)
$env:PG_SCHEMA_NAME = $StateSchema
tofu init -reconfigure
```

The root module needs the block shown in `backend/backend.tofu.example`:

```hcl
terraform {
  required_version = ">= 1.10"
  backend "pg" {}
}
```

Use other schema names such as `vpp_host` for separate layers. Do not commit backend
credentials or state files. Client-side state encryption is also recommended for
secrets contained in state.

## Operations and backups

```bash
ssh -i <PATH_TO_BACKEND_VM_SSH_KEY> ubuntu@<POSTGRES_BACKEND_VM_IP>
sudo systemctl status postgresql
sudo -u postgres psql -d opentofu_backend -c '\dn'
sudo systemctl list-timers opentofu-pg-backup.timer
```

The installed timer retains 14 days of logical PostgreSQL dumps under
`/var/backups/opentofu-postgres`. Proxmox job `opentofu-state-postgres-vm169` backs up
VM 169 daily to `eben-stor-2`, retaining seven daily and four weekly backups.

## Recovery

1. Restore VM 169 from a Proxmox backup, retaining static address `192.168.88.3`.
2. Verify PostgreSQL, the backup timer, and `/etc/opentofu-backend.env`.
3. Run `tofu init` and a read-only `tofu plan` before permitting applies.

## Recreate the backend VM

The backend was deployed in two stages: Proxmox VM creation followed by PostgreSQL
guest configuration. The supplied scripts refuse to overwrite an existing VM or
rotate an existing `/etc/opentofu-backend.env` file.

### 1. Create the VM on Proxmox

Copy the creation script to the Proxmox node and run it as root. Override the
defaults through environment variables when required:

```bash
scp bootstrap/create-vm.sh root@<PROXMOX_HOST>:/tmp/create-opentofu-db-vm.sh
ssh root@<PROXMOX_HOST> \
  'VM_ID=<VM_ID> VM_NAME=<VM_NAME> TEMPLATE_ID=<TEMPLATE_VM_ID> STORAGE=<STORAGE_ID> bash /tmp/create-opentofu-db-vm.sh'
```

PowerShell equivalent:

```powershell
scp .\bootstrap\create-vm.sh root@<PROXMOX_HOST>:/tmp/create-opentofu-db-vm.sh
ssh root@<PROXMOX_HOST> `
  "VM_ID=<VM_ID> VM_NAME=<VM_NAME> TEMPLATE_ID=<TEMPLATE_VM_ID> STORAGE=<STORAGE_ID> bash /tmp/create-opentofu-db-vm.sh"
```

The deployed values were VM 169, `opentofu-state-postgres`, template 9006,
`ebenezer-stor1`, two vCPUs, 2 GiB maximum memory, 1 GiB balloon minimum, a 64 GiB
disk, and static address `192.168.88.3/24`. The script currently contains this
address, gateway, and DNS setting; edit those lines before running it in another
network.

Wait for cloud-init and SSH before continuing:

```powershell
ssh -i <BACKEND_VM_SSH_KEY> ubuntu@<POSTGRES_BACKEND_VM_IP> "cloud-init status --wait"
```

### 2. Install and secure PostgreSQL

```powershell
scp -i <BACKEND_VM_SSH_KEY> .\bootstrap\install-postgres-backend.sh `
  ubuntu@<POSTGRES_BACKEND_VM_IP>:/tmp/install-postgres-backend.sh
ssh -i <BACKEND_VM_SSH_KEY> ubuntu@<POSTGRES_BACKEND_VM_IP> `
  "sudo bash /tmp/install-postgres-backend.sh"
```

The installer creates database `opentofu_backend`, login role `opentofu`, a random
32-byte password, TLS-required client access, and root-only file
`/etc/opentofu-backend.env`. Its `pg_hba.conf` rule currently permits
`192.168.88.0/24`; change `hba_rule` for another management network.

### 3. Install logical database backups

```powershell
scp -i <BACKEND_VM_SSH_KEY> .\files\opentofu-pg-backup `
  .\files\opentofu-pg-backup.service .\files\opentofu-pg-backup.timer `
  ubuntu@<POSTGRES_BACKEND_VM_IP>:/tmp/
ssh -i <BACKEND_VM_SSH_KEY> ubuntu@<POSTGRES_BACKEND_VM_IP> `
  "sudo install -m 0755 /tmp/opentofu-pg-backup /usr/local/sbin/opentofu-pg-backup; sudo install -m 0644 /tmp/opentofu-pg-backup.service /etc/systemd/system/; sudo install -m 0644 /tmp/opentofu-pg-backup.timer /etc/systemd/system/; sudo systemctl daemon-reload; sudo systemctl enable --now opentofu-pg-backup.timer; sudo systemctl start opentofu-pg-backup.service"
```

The timer creates PostgreSQL custom-format dumps at 02:15 UTC and removes dumps
older than 14 days.

### 4. Configure the Proxmox VM backup

Run on the Proxmox host, adapting IDs, storage, and schedule:

```bash
pvesh create /cluster/backup \
  --id <BACKUP_JOB_ID> \
  --node <PROXMOX_NODE> \
  --vmid <BACKEND_VM_ID> \
  --storage <BACKUP_STORAGE_ID> \
  --schedule '03:00' \
  --mode snapshot \
  --compress zstd \
  --prune-backups 'keep-daily=7,keep-weekly=4' \
  --enabled 1
```

### 5. Verify the deployment

```bash
sudo systemctl is-active postgresql opentofu-pg-backup.timer
sudo -u postgres psql -d opentofu_backend -c '\dn'
sudo ls -l /etc/opentofu-backend.env /var/backups/opentofu-postgres
lsblk
df -h /
```

A fresh rebuild creates new credentials and contains no previous OpenTofu state.
Restore the latest database dump or VM backup before running an apply against
infrastructure that already exists.
