# Project Documentation

This `doc/` folder contains project‑level documentation generated from
`APP_BASE/config/doc` during provisioning. Files here are **safe to edit**:
your changes will be preserved unless the template in `APP_BASE` is newer.

## Purpose
- Provide a consistent documentation baseline for all projects.
- Ensure contributors always have up‑to‑date workflow references.
- Avoid overwriting local edits by using `copy_if_newer`.

## Structure
- `environment.md` — How environments and dev sources work.
- `workflow.md` — Provisioning flow, repo hierarchy, and contributor steps.
- Additional docs may be added over time.

## Updating
If you want to customize documentation for your project, edit files here in
`PROJECT_BASE/doc`. Your changes will not be overwritten unless the template
is updated upstream.