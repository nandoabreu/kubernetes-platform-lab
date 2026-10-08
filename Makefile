.PHONY: status

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
	@df -hT / /home /var
	@df -B1 -P /home
	@stat -f -c 'type=%T block_size=%S blocks=%b free_blocks=%f available_blocks=%a' /home
	@printf '\n== Libvirt storage pool: extra ==\n'
	@virsh pool-refresh extra
	@virsh pool-info extra
	@printf '\n== Pool current use ==\n'
	@df -hT /home
	@du -sh /home/common/libvirt
	@set -- /home/common/libvirt/k3s*; if [ -e "$$1" ]; then ls -lh "$$@"; else printf 'No k3s files found in pool.\n'; fi
	@printf '\n== Libvirt networks and VMs ==\n'
	@virsh net-list --all
	@virsh list --all
	@printf '\n== VM domain details ==\n'
	@for domain in $$(virsh list --all --name); do \
	  [ -n "$$domain" ] || continue; \
	  printf '\n-- %s --\n' "$$domain"; \
	  virsh dominfo "$$domain"; \
	done
