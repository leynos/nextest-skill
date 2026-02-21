SHELL := /usr/bin/env bash

.PHONY: check-fmt lint typecheck test

check-fmt:
	@git diff --check -- .
	@echo "Patch format checks passed."

lint:
	@if rg -n "[[:blank:]]$$" README.md nextest/SKILL.md nextest/ref/*.md; then \
		echo "Trailing whitespace found." >&2; \
		exit 1; \
	else \
		echo "No trailing whitespace found."; \
	fi

typecheck:
	@echo "No typecheck checks defined for this docs-only repository."

test:
	@test -f nextest/SKILL.md
	@test -f nextest/ref/ci-patterns.md
	@test -f nextest/ref/filterset-dsl.md
	@echo "Documentation smoke tests passed."
