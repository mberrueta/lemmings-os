# Task 05: Connection Runtime Facade Without Secret Resolution

## Status
- **Status**: REVISED

## Objective
Expose runtime-safe Connection resolution by `type`, with no Secret Bank resolution.

## Requirements
- Resolve nearest visible usable Connection (`enabled` only).
- Return safe descriptor (id/type/status/source/local/inherited/config refs).
- Emit safe resolve events.
- Never call Secret Bank from runtime facade.

## Acceptance
- Runtime facade tests prove it does not resolve secrets.
- Disabled/invalid/missing/inaccessible are handled deterministically.
