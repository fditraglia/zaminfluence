# test_derivs diagnostic report (IN-SUITE run)

_Generated 2026-04-13 17:26:43 BST_

Same 24-config diagnostic as `report.md`, but this run was preceded by
`devtools::test(filter="base_values")` and `devtools::test(filter="catchall")`,
to mimic the state that test_derivs would see when the whole suite runs.

Compare the `worst_grad` column against `report.md`. If the numbers are
much larger here, then the in-suite state is what destabilizes the test —
not the data, not the math.

| config | kappa_ZWX | kappa_ZWZ | coeff_diff | se_diff | worst_grad | over_tol |
|---|---:|---:|---:|---:|---:|:---:|
| 10, TRUE, TRUE, 1 | 2.58e+00 | 4.23e+00 | 4.44e-16 | 1.11e-16 | 2.78e-17 | no |
| -1, TRUE, TRUE, 1 | 3.17e+00 | 3.62e+00 | 3.89e-16 | 2.22e-16 | 8.33e-17 | no |
| 10, FALSE, TRUE, 1 | 5.80e+00 | 3.74e+00 | 9.99e-16 | 2.22e-16 | 1.04e-16 | no |
| -1, FALSE, TRUE, 1 | 4.59e+00 | 5.36e+00 | 2.78e-16 | 5.00e-16 | 3.89e-16 | no |
| 10, TRUE, FALSE, 1 | 1.77e+01 | — | 3.41e-15 | 4.44e-16 | 1.39e-16 | no |
| -1, TRUE, FALSE, 1 | 1.52e+01 | — | 6.66e-16 | 1.11e-16 | 1.11e-16 | no |
| 10, FALSE, FALSE, 1 | 1.31e+01 | — | 8.88e-16 | 3.33e-16 | 5.55e-17 | no |
| -1, FALSE, FALSE, 1 | 1.13e+01 | — | 2.22e-16 | 2.22e-16 | 1.11e-16 | no |
| 10, TRUE, TRUE, 2 | 5.80e+00 | 6.88e+00 | 4.10e-16 | 4.44e-16 | 9.71e-17 | no |
| -1, TRUE, TRUE, 2 | 2.85e+00 | 3.45e+00 | 2.22e-16 | 3.33e-16 | 2.78e-17 | no |
| 10, FALSE, TRUE, 2 | 4.63e+00 | 3.99e+00 | 1.17e-15 | 1.11e-16 | 1.39e-16 | no |
| -1, FALSE, TRUE, 2 | 3.88e+00 | 4.55e+00 | 7.01e-16 | 2.22e-16 | 2.22e-16 | no |
| 10, TRUE, FALSE, 2 | 1.55e+01 | — | 4.44e-16 | 1.11e-16 | 5.55e-17 | no |
| -1, TRUE, FALSE, 2 | 1.73e+01 | — | 6.66e-16 | 1.11e-16 | 5.55e-17 | no |
| 10, FALSE, FALSE, 2 | 1.70e+01 | — | 4.44e-16 | 3.33e-16 | 1.11e-16 | no |
| -1, FALSE, FALSE, 2 | 1.63e+01 | — | 3.89e-16 | 1.11e-16 | 1.11e-16 | no |
| 10, TRUE, TRUE, 3 | 4.03e+00 | 5.16e+00 | 1.39e-15 | 2.78e-16 | 1.25e-16 | no |
| -1, TRUE, TRUE, 3 | 2.33e+00 | 2.67e+00 | 2.22e-16 | 1.11e-16 | 6.94e-17 | no |
| 10, FALSE, TRUE, 3 | 3.47e+00 | 4.52e+00 | 5.00e-16 | 4.44e-16 | 1.94e-16 | no |
| -1, FALSE, TRUE, 3 | 2.44e+00 | 4.22e+00 | 8.47e-16 | 1.11e-16 | 1.11e-16 | no |
| 10, TRUE, FALSE, 3 | 1.73e+01 | — | 3.33e-16 | 4.44e-16 | 1.39e-16 | no |
| -1, TRUE, FALSE, 3 | 1.68e+01 | — | 2.50e-16 | 1.67e-16 | 4.16e-17 | no |
| 10, FALSE, FALSE, 3 | 1.68e+01 | — | 1.11e-15 | 5.55e-16 | 3.33e-16 | no |
| -1, FALSE, FALSE, 3 | 1.57e+01 | — | 3.33e-16 | 1.11e-16 | 1.39e-16 | no |
