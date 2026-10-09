.PHONY: help requirements check status

LIBVIRT_POOL ?= extra
LIBVIRT_VOLUME_DIR ?= /home/common/libvirt
HOST_STORAGE_PATH ?= /home
HOST_FILESYSTEMS ?= / /home /var

help:
	@printf '%s\n' \
	  'requirements  Check whether the documented command-line tools are available' \
	  'check         Run static Terraform and Ansible validation' \
	  'status        Capture host, storage, network, and VM capacity' \
	  '' \
	  'The tested status defaults can be overridden, for example:' \
	  '  make status LIBVIRT_POOL=default LIBVIRT_VOLUME_DIR=/var/lib/libvirt/images HOST_STORAGE_PATH=/var'

requirements:
	@missing=0; \
	for command in git make terraform ansible-playbook kubectl virsh qemu-img; do \
	  if command -v "$$command" >/dev/null 2>&1; then \
	    printf 'found:   %s\n' "$$command"; \
	  else \
	    printf 'missing: %s\n' "$$command"; \
	    missing=1; \
	  fi; \
	done; \
	exit $$missing

check:
	terraform fmt -check -recursive
	terraform -chdir=terraform validate
	cd ansible && ansible-playbook playbooks/k3s.yml --syntax-check

status:
	@printf '== Snapshot ==\n'
	@date --iso-8601=seconds
	@hostnamectl --static
	@printf '\n== Host resources ==\n'
	@uptime
	@nproc
	@free -h
	@swapon --show
	@printf '\n== Filesystems ==\n'
	@df -hT $(HOST_FILESYSTEMS)
	@df -B1 -P "$(HOST_STORAGE_PATH)"
	@stat -f -c 'type=%T block_size=%S blocks=%b free_blocks=%f available_blocks=%a' "$(HOST_STORAGE_PATH)"
	@printf '\n== Libvirt storage pool: %s ==\n' "$(LIBVIRT_POOL)"
	@virsh pool-refresh "$(LIBVIRT_POOL)"
	@virsh pool-info "$(LIBVIRT_POOL)"
	@printf '\n== Pool current use ==\n'
	@df -hT "$(LIBVIRT_VOLUME_DIR)"
	@du -sh "$(LIBVIRT_VOLUME_DIR)"
	@set -- "$(LIBVIRT_VOLUME_DIR)"/k3s*; if [ -e "$$1" ]; then ls -lh "$$@"; else printf 'No k3s files found in pool.\n'; fi
	@printf '\n== Libvirt networks and VMs ==\n'
	@virsh net-list --all
	@virsh list --all
	@printf '\n== VM domain details ==\n'
	@for domain in $$(virsh list --all --name); do \
	  [ -n "$$domain" ] || continue; \
	  printf '\n-- %s --\n' "$$domain"; \
	  virsh dominfo "$$domain"; \
	done
