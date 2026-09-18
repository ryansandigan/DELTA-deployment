# Publishing the MkDocs site on GitHub Pages

Maintainer guide for the documentation website built from `mkdocs-material/`.
It is not DELTA operator documentation and is not part of the published site.

GitHub Pages hosts the rendered static site. Publishing it is **not** a GitHub
Release and creates no release, tag or `gh-pages` branch: a GitHub Actions
workflow builds the site and uploads it to Pages as an artifact. The workflow
never runs on its own — not on push, not on a schedule. Deployment is a
deliberate step, `make mkdoc-deploy`, run from a clean, pushed `main`.

## Contents

- [Project details](#project-details)
- [1. Prerequisites and repository layout](#1-prerequisites-and-repository-layout)
- [2. Set up the local MkDocs environment](#2-set-up-the-local-mkdocs-environment)
- [3. Build, check and preview locally](#3-build-check-and-preview-locally)
- [4. `mkdocs.yml` and the site URL](#4-mkdocsyml-and-the-site-url)
- [5. The GitHub Actions workflow](#5-the-github-actions-workflow)
- [6. One-time GitHub Pages configuration](#6-one-time-github-pages-configuration)
- [7. Install GitHub CLI on Ubuntu / WSL](#7-install-github-cli-on-ubuntu--wsl)
- [8. Authenticate GitHub CLI](#8-authenticate-github-cli)
- [9. Deploy — first time and every update](#9-deploy--first-time-and-every-update)
- [10. Monitor a deployment](#10-monitor-a-deployment)
- [11. Troubleshooting](#11-troubleshooting)

---

## Project details

| | |
|---|---|
| Repository | `ryansandigan/DELTA-deployment` |
| Source branch | `main` |
| Workflow | `.github/workflows/docs.yml` (name: *Deploy documentation*, trigger: `workflow_dispatch` only) |
| Site source | `mkdocs-material/` (`mkdocs.yml`, `docs/`, `requirements.txt`) |
| Published URL | <https://ryansandigan.github.io/DELTA-deployment/> |
| Actions URL | <https://github.com/ryansandigan/DELTA-deployment/actions/workflows/docs.yml> |
| Deploy command | `make mkdoc-deploy` from the repository root |

The Pages URL follows GitHub's project-site pattern,
`https://<owner>.github.io/<repository>/` — the repository name becomes the
path, which is why `site_url` in `mkdocs.yml` ends in `/DELTA-deployment/`.

---

## 1. Prerequisites and repository layout

You need:

- a clone of the repository with working SSH access
  (`git@github.com:ryansandigan/DELTA-deployment.git`) and write permission;
- Python 3.9 or newer on the machine you build from — the Linux venv in this
  repository was created with Python 3.12 on Ubuntu/WSL;
- GitHub CLI (`gh`), installed and signed in — [step 7](#7-install-github-cli-on-ubuntu--wsl)
  and [step 8](#8-authenticate-github-cli). It is needed only to deploy, not
  to build or preview;
- `make`, for the preview and deploy targets.

The parts of the repository that matter here:

```text
DELTA-deployment/
├── .github/workflows/docs.yml    Pages workflow (workflow_dispatch only)
├── Makefile                      mkdoc-start / mkdoc-stop / mkdoc-restart / mkdoc-deploy
├── README.md, docs/              canonical operator documentation (root Markdown)
└── mkdocs-material/
    ├── mkdocs.yml                site configuration: site_name, site_url, theme, nav
    ├── requirements.txt          the one pinned dependency: mkdocs-material==9.7.7
    ├── docs/                     the site's pages (index.md + docs/*.md + docs/docker/*.md)
    ├── README.md                 what this folder is and how it mirrors the root Markdown
    ├── mkdocs-github-setup.md    this guide — outside docs/, so not part of the site
    ├── .venv/                    local virtual environment (ignored by Git)
    └── site/                     build output (ignored by Git; delete after checking)
```

`mkdocs-material/docs/` is a presentation copy of the root Markdown, kept in
step by hand — `docs/maintenance.md` at the repository root is the rule. A
documentation change is made in the root Markdown first and then mirrored
here; the site never edits itself.

---

## 2. Set up the local MkDocs environment

Everything installs into a virtual environment inside `mkdocs-material/`;
nothing goes system-wide. Virtual environments are per operating system —
never reuse a Windows `.venv` from WSL or the other way round.

1. Create the environment and install the pinned dependency:

   ```bash
   cd mkdocs-material
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

   On Ubuntu/WSL, if `python3 -m venv` stops with *ensurepip is not
   available*, install the venv module for your Python and run the command
   again:

   ```bash
   sudo apt update && sudo apt install python3-venv
   ```

2. Verify:

   ```bash
   python -m mkdocs --version
   ```

   **Expected:** `python -m mkdocs, version 1.6.1 from …/mkdocs-material/.venv/…`.
   Material 9.7.7 brings that mkdocs version with it.

Leave the environment with `deactivate`. The Makefile targets do not need it
activated — they call `mkdocs-material/.venv/bin/python` directly.

---

## 3. Build, check and preview locally

The strict build is the check the workflow runs, so run it before every
deployment. It turns every warning — a broken link, a missing anchor, a page
missing from `nav` — into a failed build.

```bash
cd mkdocs-material
source .venv/bin/activate
python -m mkdocs build --strict
deactivate
rm -rf site
cd ..
```

**Expected:** `INFO - Documentation built in …` and exit code 0. Material
prints its own red advisory banner about MkDocs 2.0 on every build; that is
not a fault. `site/` is the finished website; delete it after looking, it is
never committed.

For a live preview that reloads as you edit, use the root `Makefile`:

```bash
make mkdoc-start      # http://127.0.0.1:8000/, log in .mkdocs-run/
make mkdoc-restart
make mkdoc-stop
```

`make` alone prints the options, including `HOST=` / `PORT=` overrides. The
preview is entirely local and independent of GitHub Pages: starting or
stopping it publishes nothing, and deploying does not need it running.

---

## 4. `mkdocs.yml` and the site URL

`mkdocs-material/mkdocs.yml` is the whole site configuration. The one setting
that ties it to GitHub Pages:

```yaml
site_url: https://ryansandigan.github.io/DELTA-deployment/
```

It sets the canonical `<link>` on every page and the URLs in `sitemap.xml`.
Links between pages and to assets stay relative, so the same build works from
`mkdocs serve`, a file server and Pages alike; only `404.html` uses the
absolute `/DELTA-deployment/` base, because GitHub serves it from any path.

Change `site_url` only if the address changes — the repository is renamed or
transferred (the path is the repository name), or a custom domain is added
under Settings → Pages. Everything else in the file (`nav`, theme features,
Markdown extensions) is independent of where the site is hosted.

---

## 5. The GitHub Actions workflow

`.github/workflows/docs.yml` — *Deploy documentation* — has two jobs on
`ubuntu-latest`:

- **build**: `actions/checkout`, `actions/setup-python` (Python 3.12, pip
  cache keyed on `mkdocs-material/requirements.txt`),
  `pip install -r mkdocs-material/requirements.txt`, `actions/configure-pages`,
  `python -m mkdocs build --strict` in `mkdocs-material/`, then
  `actions/upload-pages-artifact` with `mkdocs-material/site`;
- **deploy**: `actions/deploy-pages` into the `github-pages` environment; the
  job's `url` is the published address.

It runs only on `workflow_dispatch`. There is no push trigger, so merging or
pushing to `main` changes nothing on the live site until someone deploys.
It declares the minimum permissions itself (`contents: read`, `pages: write`,
`id-token: write`) and uses the `pages` concurrency group, so two
deployments never overlap and a running one is never cancelled.

The intended trigger is `make mkdoc-deploy` ([step 9](#9-deploy--first-time-and-every-update)),
which checks the local state before dispatching. The **Run workflow** button
on the Actions page (branch `main`) starts exactly the same run without those
checks — it deploys whatever is on `origin/main`.

---

## 6. One-time GitHub Pages configuration

Do this once, after `.github/workflows/docs.yml` has been pushed to `main`.

1. Open the repository on GitHub → **Settings** → **Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.

That is the whole configuration. No release is created, no `gh-pages` branch
is needed, and nothing is selected under "Branch": the workflow publishes the
built site directly through the `github-pages` environment, which GitHub
creates on the first deployment.

---

## 7. Install GitHub CLI on Ubuntu / WSL

Use GitHub's own package repository — the official procedure from
<https://github.com/cli/cli/blob/trunk/docs/install_linux.md> — not the
`gh` package from the distribution or a community PPA.

```bash
(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y
```

Verify:

```bash
gh --version
```

**Expected:** a line such as `gh version 2.x.y (YYYY-MM-DD)`.

Later upgrades come with the normal `sudo apt update && sudo apt install gh`.

---

## 8. Authenticate GitHub CLI

`make mkdoc-deploy` calls `gh` to start the workflow, so `gh` must be signed
in to the account that can run workflows on the repository. Git itself keeps
using the SSH remote it already has.

1. Start the browser-based login:

   ```bash
   gh auth login --hostname github.com --git-protocol ssh --web
   ```

2. When asked whether to upload an SSH public key, choose **Skip** if
   `git fetch` / `git push` over SSH already work — nothing about Git access
   changes.
3. `gh` prints a one-time device code and tries to open a browser. In WSL the
   browser often does not open; open <https://github.com/login/device> yourself,
   on Windows or anywhere, and enter the code shown in the terminal. The code
   expires after a few minutes and is never needed again — do not write it
   down, and never paste tokens or codes into documentation or chat.
4. Verify:

   ```bash
   gh auth status
   ```

   **Expected:** `Logged in to github.com account <your-account>` with the
   `repo` and `workflow` scopes listed. Those are the defaults `gh auth login`
   requests, and the `workflow` scope is what `gh workflow run` needs.

### The plain-text credential warning

On a WSL / headless Ubuntu without a desktop keyring, `gh auth login` warns
that the token will be stored in plain text. It lands in
`~/.config/gh/hosts.yml`. That is normal there; keep the file private to your
user:

```bash
chmod 700 ~/.config/gh
chmod 600 ~/.config/gh/hosts.yml
stat -c '%a %n' ~/.config/gh ~/.config/gh/hosts.yml
```

**Expected:** `700 …/.config/gh` and `600 …/.config/gh/hosts.yml`. Never
commit or copy that file, and use `gh auth logout` on a machine you stop
using.

---

## 9. Deploy — first time and every update

The same procedure publishes the site the first time and every update after.
`make mkdoc-deploy` never commits, pushes, merges or tags: everything it
deploys must already be on `origin/main`.

1. Change the documentation (root Markdown first, then the copy under
   `mkdocs-material/docs/`), then run the strict build from
   [step 3](#3-build-check-and-preview-locally).

2. Commit and push `main`:

   ```bash
   git add -A
   git commit -m "docs: <what changed>"
   git push origin main
   ```

3. Confirm the tree is clean and in sync:

   ```bash
   git status --short
   git fetch origin main && git rev-parse HEAD FETCH_HEAD
   ```

   **Expected:** no output from `git status --short`, and the two commit ids
   are identical.

4. Dispatch the deployment:

   ```bash
   make mkdoc-deploy
   ```

   **Expected:** `Dispatching docs.yml on origin/main @ <commit>...` followed
   by `Deployment dispatched. Watch it at:` and the Actions URL.

Before it dispatches, the target checks — in this order — and stops with an
`ERROR:` line if any fails:

| Gate | What must be true |
|---|---|
| `gh` installed | `gh` is on `PATH` (or `make mkdoc-deploy GH=/path/to/gh`) |
| `gh` authenticated | `gh auth status` succeeds |
| Origin remote | `origin` is `git@github.com:ryansandigan/DELTA-deployment.git` (or the equivalent HTTPS URL) |
| Branch | the current branch is `main` |
| Clean worktree | `git status --porcelain` prints nothing — no modified **or untracked** files |
| Pushed | after `git fetch origin main`, local `HEAD` equals `origin/main` |

The only thing it then does is `gh workflow run docs.yml --ref main`. The
workflow checks out `main` as it is on GitHub, installs the pinned
`mkdocs-material/requirements.txt`, runs `python -m mkdocs build --strict`,
uploads `mkdocs-material/site` as the Pages artifact and deploys it to the
`github-pages` environment.

---

## 10. Monitor a deployment

The Actions URL lists every run of the workflow; the newest is at the top,
and opening it shows the `build` and `deploy` jobs with their logs. The same
from the terminal:

```bash
gh run list --workflow docs.yml
```

Take the run id from the list, then:

```bash
gh run watch <run-id> --exit-status
```

`--exit-status` makes the command exit non-zero if the run fails, so it works
in a script. For a finished run:

```bash
gh run view <run-id>
gh run view <run-id> --log-failed
```

Finally open <https://ryansandigan.github.io/DELTA-deployment/> and check
that the page reflects the change — the site title, or the section you
edited. The `deploy` job's summary also shows the URL it published.

---

## 11. Troubleshooting

**404 at the Pages URL.** In order of likelihood: the address is missing the
repository path — the site is at `…github.io/DELTA-deployment/`, not
`…github.io/`; no deployment has run yet, or the last one failed (check the
Actions URL); Pages is not enabled or its source is not GitHub Actions
([step 6](#6-one-time-github-pages-configuration)); the first deployment
can take a few minutes to appear after the `deploy` job reports success.

**"Pages" source is not GitHub Actions.** The `deploy` job fails at
`actions/deploy-pages` (typically *Not Found* or *Get Pages site failed*)
although `build` succeeded. Do [step 6](#6-one-time-github-pages-configuration)
and dispatch again.

**Pages permissions.** The workflow declares `pages: write` and
`id-token: write` itself, so the repository's *Workflow permissions* setting
does not have to be changed. A `deploy` job failing with *403* or *Resource
not accessible by integration* means Actions is restricted for the
repository or organisation, or the `github-pages` environment has a
protection rule that the `main` branch does not satisfy — Settings → Actions
and Settings → Environments.

**`ERROR: GitHub CLI (gh) is not installed`** — [step 7](#7-install-github-cli-on-ubuntu--wsl).
**`ERROR: GitHub CLI is not authenticated`** — [step 8](#8-authenticate-github-cli).
Either message comes from the Makefile before anything is dispatched.

**`ERROR: worktree is not clean`.** Something is modified or untracked. Run
`git status`; commit it, stash it, or delete it if it is a stray file. Ignored
files (`.venv/`, `site/`, `.mkdocs-run/`) do not count.

**`ERROR: HEAD (…) differs from origin/main (…) - push first`.** Local `main`
has commits GitHub does not, or the reverse. `git push origin main` (or
`git pull --ff-only` if the remote is ahead), then run the target again.

**`could not find any workflows named docs.yml`** from `gh`. The workflow file
is not yet on `origin/main` — GitHub only knows workflows that exist on the
default branch. Push the commit that adds `.github/workflows/docs.yml`, then
dispatch again.

**The `build` job fails on `python -m mkdocs build --strict`.** The log shows
the same warning-turned-error a local strict build shows: a broken link, a
missing anchor, a page not in `nav`. Reproduce it locally with the command in
[step 3](#3-build-check-and-preview-locally), fix the Markdown, commit, push,
dispatch again.

**Dependency problems.** Locally and in the workflow the only input is
`mkdocs-material/requirements.txt`, so both build with the same pinned
version. `pip install` failing on the runner usually means the pin was
raised to a version that does not exist or needs a newer Python; test a new
pin locally first, then commit it. Locally, *No module named mkdocs* means
the venv is not the one at `mkdocs-material/.venv` or was created without
installing the requirements — redo [step 2](#2-set-up-the-local-mkdocs-environment).
*ensurepip is not available* is the missing `python3-venv` package, also in
step 2.

**Pages loads but assets or links are broken.** Page and asset links are
relative, so a plain deployment cannot break them. If styles are missing or
links point at the wrong path, `site_url` no longer matches the address the
site is served from — the repository was renamed or moved, or a custom
domain was added. Set `site_url` to the real address
([step 4](#4-mkdocsyml-and-the-site-url)), rebuild strictly, commit, push,
deploy.

**The site is deployed but the page looks unchanged.** Browsers cache the
previous version. Reload with the cache bypassed (`Ctrl+F5`), or check the
run's published URL in a private window.
