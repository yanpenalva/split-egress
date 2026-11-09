.PHONY: test dry-run install

test:
	bash tests/smoke.sh

dry-run:
	bin/egress-check --dry-run --config config/egress-check.example.env --mihomo-config config/mihomo.example.yaml

install:
	bash scripts/install.sh
