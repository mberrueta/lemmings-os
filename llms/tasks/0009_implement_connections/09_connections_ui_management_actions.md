# Task 09: Connections UI Management Actions

## Status
- **Status**: REVISED

## Objective
Implement create/edit/delete-local/enable/disable/test flows for simplified Connections.

## Requirements
- Create/edit forms are scope-local inside World/City/Department tabs (scope is implied by page context).
- No standalone `/connections` management page.
- Forms ask for type and config payload only.
- Type dropdown comes from registry.
- Type change repopulates config textarea with default example.
- Config supports YAML/JSON parse to map.
- Delete available only for local rows.

## Acceptance
- UI workflows do not reference slug/name/provider/secret_refs fields.
