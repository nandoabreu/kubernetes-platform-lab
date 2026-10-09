# AGENTS.md

**Note:** This file contains concise, model-directed instructions for AI agents. Human-readable documentation is in `README.md` and `docs/`.

## Project context

This repository is a practical learning lab for Kubernetes platform infrastructure, starting with a three-server K3s cluster on local libvirt VMs. Keep increments small, observable, and reproducible for learners following the project one release at a time.

## Read before changing

- Read `docs/architecture.md` for topology, scope, and failure boundaries.
- Read `docs/roadmap.md` for checkpoints and release expectations.
- Read the relevant runbook before changing its procedure.

## Working agreements

- Keep each change within the active roadmap checkpoint and state what the change enables, what it owns, and what remains outside its scope.
- Prefer a tested, opinionated path over broad configurability when abstraction would obscure the lesson. Keep host-specific values local unless a concrete example helps readers adapt the lab.
- Commit one logical group at a time. Before committing, present a concise summary, affected files, validation, and proposed commit message, then wait for owner approval.
- Use a pull request for changes prepared for a release. Small documentation corrections may go directly to `main` after review.
- Use `.github/pull_request_template.md` for every pull request and complete each section.
- Give each completed roadmap checkpoint a descriptive tag. Ask before pushing tags or creating GitHub releases.
- Do not add implementation files or boilerplate before the relevant roadmap checkpoint.
- State clearly that three VMs on one physical host demonstrate node-level control-plane resilience, not host-level high availability.
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

For documentation-only changes, review Markdown structure and links, inspect the complete diff, and report checks performed. For infrastructure changes, run the configured static checks and report which operational checks were or were not exercised on a libvirt host. Scope validation to the changed files and current checkpoint.
