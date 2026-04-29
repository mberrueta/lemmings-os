# Accessibility Audit: Secret Bank LiveView Surfaces

## Summary

- Reviewed shared Secret Bank UI and callers in world, city, department, and lemming LiveView surfaces.
- Implemented focused fixes for form descriptions, error associations, focus visibility/restoration, semantic activity/list regions, and accessible action state.
- Preserved write-only security behavior: no reveal, copy, export, or masked saved-value preview was added.

## Files Reviewed

- `lib/lemmings_os_web/components/secret_bank_components.ex`
- `lib/lemmings_os_web/components/world_components.ex`
- `lib/lemmings_os_web/components/lemming_components.ex`
- `lib/lemmings_os_web/components/core_components.ex`
- `lib/lemmings_os_web/live/world_live.ex`
- `lib/lemmings_os_web/live/cities_live.ex`
- `lib/lemmings_os_web/live/departments_live.ex`
- `lib/lemmings_os_web/live/lemmings_live.ex`
- `assets/js/app.js`

## Issues

### BLOCKER

- None found.

### MAJOR

- Secret form inputs had visible labels, but shared input errors were not programmatically associated with their fields. Fixed by adding `aria-invalid`, deterministic error IDs, and composed `aria-describedby` support in the shared input component.
- Secret create/edit/delete flows could leave keyboard focus in an unclear location after reset, validation failure, edit selection, or delete. Fixed with existing LiveView push events and a small browser handler that restores focus to the relevant Secret Bank form field.

### MINOR

- Secret activity updates lacked clear live-region/list semantics. Fixed empty and populated activity states with polite status semantics, a labelled region, and timestamp `<time>` elements.
- Effective secret rows were visually list-like but not marked up as a list. Fixed by rendering rows in a `<ul>/<li>` structure.
- Icon-only edit/delete actions had accessible names, but clearer key-specific labels and action-state descriptions help screen-reader users distinguish repeated controls. Fixed without exposing secret values.
- Secret tab/current state was primarily visual. Fixed world tab buttons with `aria-pressed`, department/lemming secret links with `aria-current`, and focus-visible rings on shared buttons and tab links.

## Fixes Applied

- Added Secret Bank form help text, required field semantics, safe helper text, polite activity status regions, semantic lists, key-specific action labels, and explicit local/inherited action state text.
- Added focus-visible ring styles to shared buttons and Secret Bank/navigation controls.
- Added focus restoration for successful save/delete, validation failures, and edit actions.
- Added LiveView coverage for Secret Bank accessibility attributes and value non-disclosure.

## Follow-ups

- Consider a broader design-token contrast pass for low-emphasis uppercase metadata text (`text-zinc-500`) across the application.
- Consider standardizing tab semantics across all app sections if keyboard arrow-key tab behavior becomes a product requirement.
