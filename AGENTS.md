# AGENTS.md

## Project context

This repository is a practical learning lab for Kubernetes platform
infrastructure, beginning with high availability in a three-server K3s cluster
on local libvirt VMs. Keep the first increments small, observable, and
reproducible.

## Read before changing

- `docs/architecture.md` for topology, scope, and failure boundaries.
- `docs/roadmap.md` for current checkpoints and release expectations.
- The relevant runbook before changing its procedure.

## Working agreements

- Communicate with the owner in Brazilian Portuguese. Write repository files,
  code, comments, and shared project communications in English (UK preferred over US).
- The owner reviews all changes before they are committed. Show the complete
  diff and wait for explicit review/commit instructions; do not commit
  automatically.
- Documentation, comments, and log-message-only changes may be committed
  directly to `main`, after review. All other changes must be delivered through
  a pull request.
- An instruction such as "commit and open a PR" authorises both actions; do not
  ask for a second confirmation after the owner has reviewed the changes and authorised both.
- Each roadmap checkpoint must have a replayable GitHub release. Do not create
  releases or tags without explicit authorisation.
- Do not introduce implementation files or boilerplate ahead of the agreed
  roadmap checkpoint.
- Keep the lab's limits explicit: three VMs on one physical host do not provide
  physical-host high availability.
- Keep secrets, local state, VM images, and generated credentials out of Git.
- Use ASCII diagrams for simple topologies. Keep runbooks ordered, actionable,
  and clear about validation and cleanup.

## Validation

For documentation-only changes, inspect the rendered Markdown structure and
links, review the complete diff, and report any checks performed. Scope other
validation to the files and checkpoint being changed.
