# Internal helper for the local MkDocs Material preview. Not part of the
# deployment and not referenced by the public documentation.
#
# Run from the repository root:
#   make mkdoc-start [HOST=127.0.0.1] [PORT=8001]
#   make mkdoc-stop
#   make mkdoc-restart
#   make mkdoc-deploy      dispatch the GitHub Pages workflow for pushed main

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

HOST ?= 0.0.0.0
PORT ?= 8000

MKDOCS_DIR := mkdocs-material
MKDOCS_CFG := $(MKDOCS_DIR)/mkdocs.yml
PYTHON     := $(MKDOCS_DIR)/.venv/bin/python

# Local runtime state (ignored by Git).
RUN_DIR  := .mkdocs-run
PID_FILE := $(RUN_DIR)/mkdocs-serve.pid
LOG_FILE := $(RUN_DIR)/mkdocs-serve.log

# GitHub Pages deployment: dispatched, never automatic. The workflow runs
# only on workflow_dispatch, against main as already pushed to this remote.
GH            ?= gh
GITHUB_REPO   := ryansandigan/DELTA-deployment
DEPLOY_BRANCH := main
WORKFLOW_FILE := docs.yml
WORKFLOW_URL  := https://github.com/$(GITHUB_REPO)/actions/workflows/$(WORKFLOW_FILE)
# Accepted spellings of the origin remote (SSH, or the equivalent HTTPS).
REMOTE_URLS   := git@github.com:$(GITHUB_REPO).git \
                 ssh://git@github.com/$(GITHUB_REPO).git \
                 https://github.com/$(GITHUB_REPO).git \
                 https://github.com/$(GITHUB_REPO)

# The command line the server is started with. mkdoc-stop only terminates a
# process whose command line contains this exact config path plus "serve".
SERVE_CMD := $(PYTHON) -m mkdocs serve -f $(MKDOCS_CFG) -a $(HOST):$(PORT)

# Address to open in a browser: 0.0.0.0 binds every interface but is not a
# destination, so show the loopback address instead.
URL_HOST := $(if $(filter 0.0.0.0,$(HOST)),127.0.0.1,$(HOST))
URL      := http://$(URL_HOST):$(PORT)/

.DEFAULT_GOAL := help
.PHONY: help mkdoc-start mkdoc-stop mkdoc-restart mkdoc-deploy

help:
	@echo "MkDocs Material preview (local, internal)"
	@echo
	@echo "  make mkdoc-start     start the preview server in the background"
	@echo "  make mkdoc-stop      stop the server started by this Makefile"
	@echo "  make mkdoc-restart   stop, then start again"
	@echo "  make mkdoc-deploy    dispatch the GitHub Pages workflow ($(WORKFLOW_FILE))"
	@echo "                       for the already-pushed main branch (needs gh)"
	@echo
	@echo "  Bind address defaults to $(HOST):$(PORT); override with e.g."
	@echo "    make mkdoc-start HOST=127.0.0.1 PORT=8001"
	@echo
	@echo "  Deploy flow: commit -> push main -> make mkdoc-deploy -> watch"
	@echo "    $(WORKFLOW_URL)"
	@echo
	@echo "  Interpreter: $(PYTHON)"
	@echo "  Config:      $(MKDOCS_CFG)"
	@echo "  PID / log:   $(PID_FILE) / $(LOG_FILE)"

# Shell helper: prints the pid from $(PID_FILE) if that process is alive AND
# its command line is this repository's mkdocs serve. Otherwise prints nothing.
# A pid file that does not pass this check is stale and is removed.
define running_pid
	pid=""
	if [ -f "$(PID_FILE)" ]; then
		pid=$$(cat "$(PID_FILE)" 2>/dev/null || true)
		args=$$(ps -o args= -p "$${pid:-0}" 2>/dev/null || true)
		case "$$args" in
			*"-m mkdocs serve -f $(MKDOCS_CFG)"*) ;;
			*) pid=""; rm -f "$(PID_FILE)" ;;
		esac
	fi
endef

mkdoc-start:
	@if [ ! -x "$(PYTHON)" ]; then
		echo "ERROR: Linux interpreter not found: $(PYTHON)" >&2
		echo "Create it from $(MKDOCS_DIR)/ (python3 -m venv .venv && pip install -r requirements.txt)." >&2
		exit 1
	fi
	if [ ! -f "$(MKDOCS_CFG)" ]; then
		echo "ERROR: MkDocs config not found: $(MKDOCS_CFG)" >&2
		exit 1
	fi
	$(running_pid)
	if [ -n "$$pid" ]; then
		echo "MkDocs preview is already running (pid $$pid)."
		echo "  URL: $(URL)"
		echo "  Log: $(LOG_FILE)"
		exit 0
	fi
	mkdir -p "$(RUN_DIR)"
	nohup $(SERVE_CMD) > "$(LOG_FILE)" 2>&1 &
	pid=$$!
	echo "$$pid" > "$(PID_FILE)"
	# Wait briefly for the server to answer, so a bad port or config surfaces here.
	for i in $$(seq 1 30); do
		if curl -fs -o /dev/null "$(URL)"; then break; fi
		if ! kill -0 "$$pid" 2>/dev/null; then
			echo "ERROR: MkDocs preview exited during startup. Last log lines:" >&2
			tail -n 20 "$(LOG_FILE)" >&2 || true
			rm -f "$(PID_FILE)"
			exit 1
		fi
		sleep 0.5
	done
	if ! curl -fs -o /dev/null "$(URL)"; then
		echo "WARNING: server started (pid $$pid) but $(URL) is not answering yet; check $(LOG_FILE)." >&2
	fi
	echo "MkDocs preview started (pid $$pid)."
	echo "  URL: $(URL)  (bound to $(HOST):$(PORT))"
	echo "  Log: $(LOG_FILE)"

mkdoc-stop:
	@$(running_pid)
	if [ -z "$$pid" ]; then
		echo "MkDocs preview is not running (no valid pid in $(PID_FILE))."
		exit 0
	fi
	echo "Stopping MkDocs preview (pid $$pid)..."
	kill -TERM "$$pid"
	for i in $$(seq 1 20); do
		if ! kill -0 "$$pid" 2>/dev/null; then break; fi
		sleep 0.5
	done
	if kill -0 "$$pid" 2>/dev/null; then
		echo "Process $$pid did not exit after 10s; sending SIGKILL." >&2
		kill -KILL "$$pid" 2>/dev/null || true
		sleep 0.5
	fi
	rm -f "$(PID_FILE)"
	echo "MkDocs preview stopped. Log kept at $(LOG_FILE)."

mkdoc-restart:
	@$(MAKE) --no-print-directory mkdoc-stop
	$(MAKE) --no-print-directory mkdoc-start HOST="$(HOST)" PORT="$(PORT)"

# Dispatches the Pages workflow on the remote main branch. Every check below is
# read-only; the only write is the dispatch itself (no commit, push or tag).
mkdoc-deploy:
	@fail() { echo "ERROR: $$1" >&2; exit 1; }
	command -v "$(GH)" >/dev/null 2>&1 \
		|| fail "GitHub CLI ($(GH)) is not installed - see https://cli.github.com/"
	"$(GH)" auth status >/dev/null 2>&1 \
		|| fail "GitHub CLI is not authenticated - run: $(GH) auth login"
	remote=$$(git config --get remote.origin.url 2>/dev/null || true)
	case " $(REMOTE_URLS) " in
		*" $$remote "*) ;;
		*) fail "origin is '$${remote:-<unset>}', expected git@github.com:$(GITHUB_REPO).git" ;;
	esac
	branch=$$(git rev-parse --abbrev-ref HEAD)
	[ "$$branch" = "$(DEPLOY_BRANCH)" ] \
		|| fail "current branch is '$$branch', deploy only from $(DEPLOY_BRANCH)"
	[ -z "$$(git status --porcelain)" ] \
		|| fail "worktree is not clean - commit or stash first (git status)"
	git fetch --quiet origin "$(DEPLOY_BRANCH)" \
		|| fail "could not fetch origin/$(DEPLOY_BRANCH)"
	local_head=$$(git rev-parse HEAD); remote_head=$$(git rev-parse FETCH_HEAD)
	[ "$$local_head" = "$$remote_head" ] \
		|| fail "HEAD ($${local_head:0:12}) differs from origin/$(DEPLOY_BRANCH) ($${remote_head:0:12}) - push first"
	echo "Dispatching $(WORKFLOW_FILE) on origin/$(DEPLOY_BRANCH) @ $${local_head:0:12}..."
	"$(GH)" workflow run "$(WORKFLOW_FILE)" --ref "$(DEPLOY_BRANCH)"
	echo "Deployment dispatched. Watch it at:"
	echo "  $(WORKFLOW_URL)"
