build:
	rm -rf .unikraft/build/libclick/origin/click-a5384835a6cac10f8d44da4eeea8eaa8f8e6a0c2/elements/unikraft || true
	mkdir -p .unikraft/build/libclick/origin/click-a5384835a6cac10f8d44da4eeea8eaa8f8e6a0c2/elements/unikraft || true
	cp -r libs/click/unikraft .unikraft/build/libclick/origin/click-a5384835a6cac10f8d44da4eeea8eaa8f8e6a0c2/elements
	kraft build --no-configure --no-fetch --no-update --no-rootfs --sources-dir /scratch/paulz/.unikraft/sources --manifests-dir /scratch/paulz/.unikraft/manifests --log-type basic

run:
	./run.sh

dns-filter:
	cd filter-rs && cargo xtask build-dns-filter-ebpf --release && (cp target/bpfel-unknown-none/release/dns-filter ../rootfs/dns-filter || true)

udp-tcp-classifier:
	cd filter-rs && cargo xtask build-udp-tcp-classifier-ebpf --release && (cp target/bpfel-unknown-none/release/udp-tcp-classifier ../rootfs/udp-tcp-classifier || true)

ether-mirror:
	cd filter-rs && cargo xtask build-ether-mirror-ebpf --release && (cp target/bpfel-unknown-none/release/ether-mirror ../rootfs/ether-mirror || true)

disassemble-bpf:
	llvm-objdump -d @(BPF)

disassemble-jit-dump:
	objdump -D -b binary -mi386 -Maddr16,data16 rootfs/jit_dump.bin -Mintel

benchmark:
	cd benchmarks && cargo bench