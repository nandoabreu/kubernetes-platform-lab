# Roadmap

## Delivery principles

- Add one major operational concept at a time.
- Every checkpoint ends in a working, verified state that can be replayed.
- Keep the process practical and resource-aware; measure before increasing allocations or adding components.
- Exercise failure and recovery, not only successful deployment.
- Review all changes before committing. Documentation-only changes may go directly to `main` after review; functional changes use a pull request.
- Converge each completed checkpoint on a versioned GitHub release with the matching source and replay instructions.

## Checkpoints

| Checkpoint | Capability | Exit evidence | Release outcome |
|---|---|---|---|
| 0 | Record host capacity, libvirt pool, VM sizing, network constraints, and lab limits | Baseline and prerequisites are documented; three 2 GiB VMs fit the measured host budget with operational headroom | Baseline release |
| 1 | Form a three-server K3s cluster with embedded etcd | All servers are Ready; etcd quorum is healthy; stable API endpoint works | First cluster release |
| 2 | Deploy a multi-replica HTTP demo behind a Kubernetes Service | Requests succeed and responses expose which replica served them | Workload-routing release |
| 3 | Exercise control-plane and workload failures | One server can be stopped while API access and quorum remain; a failed Pod is recreated and traffic reaches ready replicas | Failure-exercise release |
| 4 | Rebuild the lab reproducibly | A documented clean replay recreates the checkpoint from versioned inputs without relying on undocumented state | Rebuild release |
| 5 | Automate the proven lifecycle | Provisioning and cluster configuration are repeatable, reviewed, and have a tested rollback/cleanup path | Automation release |

Checkpoint order may be refined as practical work reveals dependencies. Do not add a future tool or directory before its checkpoint needs it.

## Release and replay convention

- Use one GitHub release for each completed checkpoint.
- Tag the exact reviewed commit that satisfies the checkpoint's exit evidence.
- Include the checkpoint name, validation summary, and replay entry point in the release notes.
- Keep replay instructions in the repository; a release must not depend on undocumented manual state.
- Release creation and tagging require explicit owner authorisation.

## Current focus

Start with Checkpoint 0. Confirm actual host and pool capacity, guest OS/image, networking, the stable API endpoint design, and the available memory budget before building the cluster. The host has three VMs planned at 2 GiB each, but host-level resource pressure must be measured during the lab.
