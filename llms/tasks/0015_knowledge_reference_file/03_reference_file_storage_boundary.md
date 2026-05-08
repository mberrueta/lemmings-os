# Task 03: Reference File Storage Boundary

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix contexts, storage boundaries, and safe domain APIs.

## Agent Invocation

Act as `dev-backend-elixir-engineer`. Implement the managed storage boundary for reference files.

## Objective

Provide Knowledge-managed storage for reference-file bytes with opaque internal storage refs and safe public descriptors.

## Implementation Scope

- Model the storage safety approach on `LemmingsOs.Knowledge.SourceFileStorageService`.
- Prefer a reference-file-specific storage boundary, such as `LemmingsOs.Knowledge.ReferenceFileStorageService`, unless a shared abstraction keeps semantics clear.
- Store original bytes outside the database.
- Return internal `storage_ref`, checksum, and size only to trusted context code.
- Generate stable public `reference_ref` values that do not encode filesystem paths or storage roots.
- Provide trusted internal read/stream/temp-file helpers only where needed for `knowledge.read` or safe extraction reuse.
- Add config/runtime handling only if a new storage root is required.

## Constraints

- UI, tool outputs, events, logs, and descriptors must not expose raw `storage_ref`, absolute paths, temp upload paths, storage roots, or workspace paths.
- Reject unsafe filenames, traversal, null bytes, absolute paths, and symlink traversal.
- Do not add public download routes for reference files in this task.
- Do not add new dependencies.

## Expected Outputs

- Managed storage service or equivalent safe boundary.
- Unit tests or test support for storage ref parsing, path safety, size/checksum, and no-path-leak expectations.
- Documentation in module docs for private vs public storage metadata.

## Suggested Checks

- `mix format`
- Storage-specific tests
- Existing source-file storage tests as regression reference

## Human Approval Gate

Human reviewer validates storage safety and descriptor separation, then approves Task 04.
