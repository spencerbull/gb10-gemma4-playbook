.PHONY: bootstrap start status benchmark stop

bootstrap:
	./scripts/bootstrap.sh

start:
	./scripts/start.sh

status:
	./scripts/status.sh

benchmark:
	./scripts/benchmark.sh

stop:
	./scripts/stop.sh
