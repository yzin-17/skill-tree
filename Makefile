.PHONY: up down status test health
up:
	python3 scripts/local.py up
down:
	python3 scripts/local.py down
status:
	python3 scripts/local.py status
health:
	python3 scripts/local.py health
test:
	python3 scripts/local.py test
