SHELL := /bin/bash
TOFU_PARALLELISM ?= 1

.PHONY: init plan infra inventory configure deploy destroy

init:
	tofu init
plan:
	tofu plan -out=cluster.tfplan
infra:
	./scripts/pre-apply.py cluster.tfplan
	tofu apply -parallelism=$(TOFU_PARALLELISM) cluster.tfplan
inventory:
	cd ansible && ./inventory.py --list | jq .
configure:
	cd ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/deploy.yml
deploy: plan infra configure
destroy:
	cd ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/teardown.yml
	tofu destroy -auto-approve -parallelism=$(TOFU_PARALLELISM)
