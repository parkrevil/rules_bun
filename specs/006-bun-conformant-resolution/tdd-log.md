# TDD Log: Feature 006

Test-first (plan Constraints, SC-003): every Behavior Change is first recorded here as a
conformance difference on `main`'s resolver, every canary and every new Starlark module's unit test
is seen failing before the code it checks is written, and each is then recorded passing. A red that
fails for a reason other than the one under test (a typo, a missing load) does not count.

| Task | Target | Command | Platform | Result | Excerpt |
|---|---|---|---|---|---|
