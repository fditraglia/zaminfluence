# test_derivs diagnosis

This directory holds the diagnostic artifacts for an unresolved instability in
`zaminfluence/tests/testthat/test_derivs.R`. See the corresponding GitHub issue
for the tracking discussion; the files here are the inputs and reports from the
diagnosis described in those threads.

## What we know so far

`test_derivs.R` validates `compute_model_influence()`'s torch-autograd
gradients against a pure-R reference defined inside the test
(`PureRComputeCoeffAndSE` + a complex-step Jacobian). It checks 24
configurations (IV/OLS × grouped/ungrouped × weighted/unweighted ×
three `keep_pars` orderings) and asserts agreement to within `1e-9`.

We have observed three distinct contexts and they give different answers:

| Context | What was run | # configs over 1e-9 | Worst grad disagreement |
|---|---|---:|---:|
| Standalone script | `Rscript notes/test_derivs_diagnosis/capture_failing_fixture.R` | 0 | ~1e-16 |
| Standalone after warmup | run `devtools::test(filter=...)` for prior files, then the diagnostic | 0 | ~1e-16 |
| Inside `devtools::test()` | injected as a test_zzz_diagnostic.R, run via the normal testthat harness | 1+ | up to 8.8e-02 |

The full `devtools::test()` of the real `test_derivs.R` itself shows 12-14
failing assertions (out of 160) per run, fluctuating across runs.

## What we have ruled out

- **Ill-conditioning.** All 24 configs have `kappa(ZWX) < 20`,
  `kappa(ZWZ) < 10`. Numbers are healthy.
- **Base-value disagreement.** Coefficients and SEs agree between the torch
  path and the pure-R reference to machine precision in every config we
  measured. The disagreement is purely in the *gradient* path.
- **A simple package-loading effect.** Loading the package via
  `devtools::load_all()` and running the diagnostic does not reproduce.
  Even running prior tests via `devtools::test(filter=...)` and then the
  diagnostic does not reproduce.

## What we have NOT ruled out

- Some interaction internal to testthat / `devtools::test` — possibly tied
  to how it sets up sandboxed namespaces, `withr` cleanup, or
  evaluation environments — that perturbs torch's autograd output by an
  amount large enough to fail the comparison.
- An actual bug in either the torch path or the pure-R reference, exposed
  only in that specific context. The base-value agreement makes a "math
  bug" less likely but does not exclude one in the differentiation
  step specifically.

## Files in this directory

- `capture_failing_fixture.R` — standalone diagnostic that walks through
  all 24 configs and emits `report.md` plus a per-config fixture if
  anything exceeds 1e-9. (Currently emits no fixtures because nothing
  fails standalone.)
- `capture_insuite_failure.R` — runs `devtools::test()` for the test
  files that precede `test_derivs` alphabetically, then runs the same
  diagnostic in the warmed session. Writes `report_insuite.md`.
  (Also currently emits no fixtures.)
- `capture_via_devtools_test.R` — last-resort capture: writes a
  temporary `test_zzz_diagnostic.R` into the package, runs the full
  `devtools::test()`, and removes the temporary test on exit. This is
  the only context in which we have actually reproduced a failure.
  Writes `report_devtools.md` and `fixture-devtools-<config>.rds`.
- `report.md` — standalone results.
- `report_insuite.md` — warmed-session results.
- `report_devtools.md` — `devtools::test()` results. Contains the only
  observed over-tolerance row.
- `fixture-devtools-*.rds` — saved inputs (x, y, z, weights, se_group)
  and outputs from both the torch path and the pure-R reference for
  the first failing config observed in the `devtools::test()` context.
  Load with `readRDS()`; structure is documented in
  `capture_via_devtools_test.R`.

## Suggested next steps (not done in this PR)

1. Pin down the over-tolerance config from `fixture-devtools-*.rds` and
   replay it in a fresh R session against both implementations to see
   which side moves between contexts.
2. Compare against a third reference on a tiny (n=4 or 5) hand-checkable
   problem to triangulate which implementation is closer to truth.
3. Stratify the test's tolerance by regime (tight for OLS ungrouped,
   moderate for grouped, looser for IV grouped) or replace the random
   draws with deterministic well-conditioned fixtures.
4. Only after the above, dig into the math — the symptoms so far point
   at a test-design / harness-environment problem, not a math bug.
