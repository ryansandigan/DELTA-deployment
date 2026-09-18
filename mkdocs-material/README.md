# DELTA deployment documentation — MkDocs Material prototype

A self-contained [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/)
version of the DELTA deployment documentation: the same procedures and the same
operator-focused wording, rendered as a website that can be previewed locally
and later published to GitHub Pages.

**This folder is a parallel prototype.** The documentation that ships with the
deployment is still the Markdown at the repository root — `README.md` and
`docs/`. Nothing here replaces it, and **the two do not synchronize**: editing a
page under `mkdocs-material/docs/` does not change the root Markdown, and
editing the root Markdown does not change this copy. Until one of the two is
chosen as the single source, a correction has to be made in both.

Everything in this folder is documentation and configuration only. It installs
nothing, deploys nothing, and touches no deployment.

---

## Preview it locally

Python 3.9 or newer with `pip` is the only prerequisite. Work in a virtual
environment so nothing is installed system-wide.

### Windows PowerShell

```powershell
cd mkdocs-material
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
mkdocs serve
```

If activation is blocked by execution policy, allow it for this session only:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`.

### Linux / macOS

```bash
cd mkdocs-material
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve
```

Then open <http://127.0.0.1:8000>. `mkdocs serve` rebuilds and reloads the page
as you edit. Stop it with `Ctrl+C`, and leave the environment with
`deactivate`.

## Build and check it

```
mkdocs build --strict
```

`--strict` turns warnings — a broken internal link, a page missing from the
navigation — into a failed build, so it is the check to run before publishing.
Output goes to `site/`, which is ignored by `.gitignore` along with `.venv/`.

The site uses relative links only, and `site_url` is deliberately unset, so
`site/` can be served from any path: a local file server, a static host, or
GitHub Pages under `/<repo>/`. No GitHub Actions workflow is included yet, and
nothing here publishes anything.

---

## Validation status

**`mkdocs build --strict` passes.** Validated on Windows with Python 3.13.15
and the pinned `mkdocs-material==9.7.7` (which brings mkdocs 1.6.1,
pymdown-extensions 12.0.1 and Markdown 3.10.3). The build is clean: no
warnings, no errors, exit code 0. The only console output besides `INFO` lines
is Material's own upstream advisory banner about the future MkDocs 2.0 release,
which is printed by the theme on every build and is not a fault in this site.

Also checked, statically: the file tree, every `nav:` target, every relative
link between pages, and every heading anchor those links point at — resolved
against Python-Markdown's `toc` slug rules rather than GitHub's, which differ
for headings containing a spaced hyphen or punctuation.

`requirements.txt` carries the **tested pin** that build used. Raise it
deliberately, and re-run `python -m mkdocs build --strict` when you do.

---

## What was changed from the root Markdown

Presentation, navigation and links only. No command, flag, value or step order
was altered.

- **`README.md` became `docs/index.md`**; `docs/<name>.md` and
  `docs/docker/<os>.md` became the matching pages here.
- **Hand-written "Contents" lists were removed.** Material renders a
  per-page table of contents in the right-hand sidebar and the section
  navigation on the left.
- **Links were repointed and relabelled** — `../README.md#install-delta`
  became `index.md#install-delta`, and link text now names the page
  ("Deployment Options") rather than its filename ("deployment-options.md").
- **Anchors were corrected for Python-Markdown's slug rules.** GitHub renders
  `## A - Standalone` as `#a---standalone`; MkDocs renders it as
  `#a-standalone`. Affected: the four pattern headings and
  "Choosing the published address…" in *Deployment Options*, and
  "Volume identity…" in *Troubleshooting*.
- **Content tabs** replace the paired PowerShell / Bash-zsh blocks, and the
  paired bundled / external-database queries. Commands identical on every
  platform are left as single blocks, not duplicated into tabs.
- **Admonitions** were used for the operationally critical items only:
  HTTPS at a real hostname, do-not-publish-before-the-password-is-changed, the
  migration/schema check, back up before updating, `docker compose down -v`,
  and the rollback capture in *Backup and Restore*. Every other note stays an
  ordinary blockquote.
- **One inconsistency in the source was corrected here**: *Deployment
  Options* → "Bootstrap - do not skip this" said the gateway route stays
  disabled "until step 10", but the installation guide has eight steps and the
  exposure step is 7. This copy says step 7, and the root Markdown
  (`docs/deployment-options.md`) has since been corrected to match.
