# Task 02: Reference File Schema And Migration

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent

`dev-db-performance-architect` - Database architect for schema design, indexes, migrations, and Postgres performance.

## Agent Invocation

Act as `dev-db-performance-architect`. Add the persistence contract for Knowledge reference files without implementing higher-level runtime or UI flows.

## Objective

Extend the Knowledge data model so reference files are first-class Knowledge items with optional Artifact provenance, managed-file metadata, active/archived lifecycle, flexible type values, and safe descriptor identifiers.

## Implementation Scope

- Add `reference_file` to the Knowledge item discriminator contract.
- Add statuses needed for reference files, expected v1 values: `active` and `archived`.
- Add a reference-file-specific table, likely `knowledge_reference_files`.
- Include fields for `knowledge_item_id`, stable `reference_ref`, flexible `reference_file_type`, original filename, content type, size, checksum, and storage ref.
- Add indexes for scope/status listing and lookup by type/tags/status.
- Preserve `artifact_id` as nullable optional provenance on `knowledge_items`; do not make it required.
- Add or update schema modules and changesets needed for this persistence contract.
- Add or update factories for reference-file rows.

## Constraints

- Do not enforce a closed enum for reference file type. Validate it as bounded non-empty text.
- Keep DB constraints minimal. Prefer Ecto schema/changeset validation for business rules.
- Allowed DB constraints: foreign keys/references, unique constraints, and indexes required for lookup/performance.
- Do not add DB `CHECK` constraints for reference file type, status, content type, or lifecycle rules.
- Do not enforce closed enums at the DB level.
- Do not create multiple migration files for this PR. If later tasks require DB changes, update the same PR migration before merge rather than adding task-specific migrations.
- Do not add source-file chunk tables, embeddings, pgvector indexes, or background indexing for reference files.
- Do not weaken existing memory and source-file validations.
- Follow the schema convention of `@required` and `@optional` lists.
- Validation messages must use `dgettext("errors", ...)`.

## Expected Outputs

- [x] A single PR migration for reference-file persistence, allowed references/unique guarantees, and indexes.
- [x] Schema/changeset support for reference-file rows.
- [x] Knowledge item kind/status support for reference files.
- [x] Factory support for later tests.

## Suggested Checks

- [x] `mix format`
- [x] `mix test test/lemmings_os/knowledge/knowledge_item_test.exs test/lemmings_os/knowledge/reference_file_test.exs test/lemmings_os/knowledge/source_file_test.exs`
- [x] `mix precommit`

## Completion Notes

- Added `reference_file` to the Knowledge item discriminator contract.
- Added reference-file `active` and `archived` status validation in schema/changeset logic.
- Added `knowledge_reference_files` persistence with one migration file.
- Kept DB constraints limited to references, unique constraints, and indexes.
- Did not add DB CHECK constraints, DB enums, chunks, embeddings, pgvector indexes, or background indexing.
- Added public API docs and doctests for the new/updated schema APIs.

## Human Approval Gate

Human reviewer validates the persistence contract, migration shape, and no-RAG boundary, then approves Task 03.
