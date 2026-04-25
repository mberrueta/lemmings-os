# Test rules

- Prefer isolated tests over broad integration tests.
- Use deterministic data.
- Avoid sleeps unless testing process timing explicitly.
- For LiveView tests, use stable selectors with `element/2` and `has_element?/2`.
- Test behavior and outcomes, not private implementation details.
