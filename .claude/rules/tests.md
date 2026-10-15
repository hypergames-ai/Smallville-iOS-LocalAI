---
paths:
  - "Tests/**"
---

# Rules for tests

- Swift Testing only (`import Testing`, `@Test`, `#expect`, `#require`). No XCTest.
- Tests never touch the real model. Use `StubBrain` for behavior and a small scripted brain (a struct that returns canned responses) when a test needs a specific answer.
- Every simulation test asserts on `events`, `discoveries()`, or `budget.summary()`; never on log output.
- A test that depends on the seed states the seed in its name or a comment.
- When a bug is fixed in the core, the fix comes with a test that fails before and passes after. Say which test in the report.
