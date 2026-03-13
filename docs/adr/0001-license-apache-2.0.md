# ADR 0001: Open Source License — Apache License 2.0

- Status: Accepted
- Date: 2026-03-13
- Decision Makers: Maintainer(s)

## Context

LemmingsOS is an open-source runtime for autonomous AI agent hierarchies.
The project is intended to be:

* practical for real self-hosted deployments
* a reference-quality portfolio project demonstrating staff-engineer-level standards
* extensible by third-party contributors and integrators

Because the runtime manages long-lived agent processes and may be embedded in
larger infrastructure, it is important that:

* the codebase is easy to adopt and self-host
* contributions are encouraged from the community
* legal/compliance overhead for users and contributors is minimized
* patent concerns for users of agent runtime infrastructure are addressed explicitly

## Decision Drivers

1. Maximize adoption and ease of integration (personal, research, commercial)
2. Encourage community contributions without complex license constraints
3. Provide explicit patent protection for users and contributors
4. Keep compliance simple for an early-stage project

## Considered Options

### Option A — Apache License 2.0 (Chosen)

A permissive license with an explicit contributor patent license grant.

### Option B — MIT License

Very permissive and short, but does not include an explicit patent license grant.
Patent coverage is often argued as implicit, but remains less explicit than Apache-2.0.

### Option C — MPL 2.0

Weak/file-level copyleft that requires sharing modifications to MPL-covered files
while allowing proprietary combinations. Adds more compliance overhead than permissive
licenses with minimal additional benefit for an infrastructure project.

### Option D — AGPLv3

Strong copyleft designed for network/server software. Would require users who modify
and run the software to release their modifications. This would materially reduce
adoption and complicate integration with proprietary AI systems.

## Decision

LemmingsOS will be licensed under the **Apache License 2.0**.

## Rationale

Apache-2.0 best satisfies the decision drivers:

* It is permissive, making it easy for individuals, researchers, and organizations to
  adopt, self-host, and build on top of LemmingsOS.
* It includes an explicit patent license grant from contributors, improving legal
  clarity for users deploying agent infrastructure in commercial contexts.
* It keeps compliance simple while providing clear attribution and licensing terms.

MIT was rejected due to less explicit patent clarity.
MPL-2.0 and AGPLv3 were rejected because copyleft obligations add friction for
users and contributors.

## Consequences

### Positive

* Lower barrier to adoption and community contribution
* Better patent clarity than MIT-style licenses
* Compatible with a wide range of dependency and deployment environments

### Negative / Trade-offs

* Does not prevent closed-source forks or hosted proprietary derivatives
* "SaaS enclosure" is not blocked by the license

### Mitigations / Follow-ups

* Build community and brand moats through strong documentation, clear governance,
  and a compelling contributor experience.
* If hosted proprietary enclosure becomes a real concern later, evaluate re-licensing
  (this would be a major change requiring explicit community communication).

## Implementation Notes

* `LICENSE` file contains the full Apache-2.0 text — already present.
* Add `NOTICE` file once third-party attributions accumulate.
* Ensure repository headers and README badges reflect Apache-2.0.
