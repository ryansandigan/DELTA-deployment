# Documentation maintenance

`README.md` and `docs/**/*.md` are the canonical documentation.

For every substantive documentation change:

1. Update the canonical root Markdown.
2. Apply the equivalent change to the corresponding file under `mkdocs-material/docs/`.
3. Compare commands and technical content for unintended differences.
4. Run the strict MkDocs build and link validation.

Presentation may differ, but technical meaning and behavior must remain the same.