STAGE ?= 01-boot-vm
POOL := lab-pool
POOL_PATH := $(CURDIR)/pool

.PHONY: list pool render

list:
	@ls -1 recipes/zero-to-k3s

pool:
	@virsh -c qemu:///system pool-info $(POOL) >/dev/null 2>&1 || { \
		virsh -c qemu:///system pool-define-as $(POOL) dir --target $(POOL_PATH); \
		test -d $(POOL_PATH) || virsh -c qemu:///system pool-build $(POOL); \
		virsh -c qemu:///system pool-start $(POOL); \
	}
	@virsh -c qemu:///system pool-info $(POOL) | grep -q 'State:.*running' || virsh -c qemu:///system pool-start $(POOL)
	@virsh -c qemu:///system pool-autostart $(POOL) >/dev/null

render:
	@test -d recipes/zero-to-k3s/$(STAGE) || { echo "unknown stage: $(STAGE)"; exit 1; }
	rm -rf infra
	mkdir -p infra
	cp -r recipes/zero-to-k3s/$(STAGE)/. infra/
