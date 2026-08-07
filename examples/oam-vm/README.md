# MicroK8s OAM VM

This independent OpenTofu root bootstraps the Linux management VM from which all
cluster OpenTofu and Ansible operations run.

Defaults:

- Name: `microk8s-oam`
- Address: `192.168.88.4/24`
- Template: `9006` (`ubuntu-24.04-noble-cloudinit`)
- Storage: `ebenezer-stor1`
- Resources: 2 vCPU, 4096 MB RAM, 50 GB disk
- PostgreSQL state schema: `microk8s_oam`

Set `PG_CONN_STR`, `PG_SCHEMA_NAME=microk8s_oam`, and
`TF_VAR_proxmox_api_token` before running `tofu init` and `tofu apply`.

The OAM VM is intentionally outside the cluster state. Destroying or rebuilding a
MicroK8s cluster therefore cannot delete its management host.

## Bootstrap procedure

After OpenTofu creates the VM, connect as `ubuntu` and install the Linux control
tools:

```bash
sudo apt-get update
sudo apt-get install -y ansible-core git jq unzip curl make python3-pip \
  python3-proxmoxer python3-requests
curl -fsSLo /tmp/tofu.zip \
  https://github.com/opentofu/opentofu/releases/download/v1.12.1/tofu_1.12.1_linux_amd64.zip
unzip /tmp/tofu.zip -d /tmp/tofu
sudo install -m 0755 /tmp/tofu/tofu /usr/local/bin/tofu
```

Install the Ubuntu guest SSH key as `~/.ssh/prox_vm_key` with mode `0600`.
Create `~/.config/microk8s-oam/environment` with mode `0600` containing the
PostgreSQL connection, state schema, and Proxmox token. If the file was copied
from Windows, normalize it once:

```bash
sed -i 's/\r$//' ~/.config/microk8s-oam/environment
```

The deployed OAM VM currently uses VM ID 170 and static address
`192.168.88.4`.
