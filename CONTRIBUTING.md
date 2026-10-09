# Contributing

This repository grows one tested learning checkpoint at a time. Before proposing a change, read the [architecture](docs/architecture.md), [roadmap](docs/roadmap.md), and the runbook affected by the change.

## Scope

- State which checkpoint the change belongs to, what it enables, and what remains outside its scope.
- Prefer a clear, tested path over broad configurability that makes the lesson harder to follow.
- Do not commit credentials, kubeconfigs, Terraform state, plans, VM images, private keys, or host-specific local configuration.
- Keep the distinction between node-level resilience and host-level high availability explicit.

## Validation

Run the checks relevant to the changed files. For infrastructure changes, report both static validation and any operational checks exercised on a libvirt host. If a check could not be run, explain why in the pull request.

Use the pull request template and keep each pull request focused on one coherent change.
