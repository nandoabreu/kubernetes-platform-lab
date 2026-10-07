# AGENTS.md

**Note:** This file contains concise, model-directed instructions for AI agents. Human-readable documentation is in `README.md` and `docs/`.

## Project context

This repository is a practical learning lab for Kubernetes platform infrastructure, starting with a highly available three-server K3s cluster on local libvirt VMs. Keep increments small, observable, and reproducible.

## Read before changing

- Read `docs/architecture.md` for topology, scope, and failure boundaries.
- Read `docs/roadmap.md` for checkpoints and release expectations.
- Read the relevant runbook before changing its procedure.

## Working agreements

- The owner reviews every change in Patched's side-by-side diff. After review, present a concise summary, explanation, affected files, validation, and proposed commit message; do not paste a unified diff into chat unless requested. Wait for explicit approval or requested changes before committing.
- Commit one logical group at a time. After each commit, report its hash and summary, then wait for the owner's direction before preparing the next group.
- Documentation-only changes may go directly to `main` after review; all other changes go through a pull request.
- Use `.github/pull_request_template.md` for every pull request and complete each section.
- Give each completed roadmap checkpoint a descriptive tag. Ask before pushing tags or creating GitHub releases.
- Do not add implementation files or boilerplate before the relevant roadmap checkpoint.
- State clearly that three VMs on one physical host do not provide host-level high availability.
- Keep secrets, local state, VM images, and generated credentials out of Git.
- Use ASCII for simple diagrams and Mermaid for complex ones. Keep runbooks ordered, actionable, and explicit about validation and cleanup.
- When adding Makefiles, put frequent commands first, group targets by workflow, and order sequential targets to match the runbooks. Add only targets needed by the active checkpoint.
- Keep Markdown paragraphs and list items on single physical lines; do not wrap them to a fixed width.

## Code languages and style

- Use Terraform and Ansible for infrastructure configuration. Write custom scripts in Python 3 or Bash.
- For Python, follow PEP 8 and use appropriate formatting, linting, and tests.

## Python code quality

- Give each function one clear responsibility and a descriptive name; add abstractions only when useful.
- Validate preconditions early and keep the happy path linear.
- Keep functions focused; split work when a function's purpose needs “and” to describe it.
- Close every resource on all exit paths, including errors.
- Never swallow errors silently; bare `except: pass` is unacceptable.
- Keep state local and avoid unnecessary module-level globals.

## Validation

For documentation-only changes, review Markdown structure and links, inspect the complete diff, and report checks performed. Scope other validation to the changed files and current checkpoint.
