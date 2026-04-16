# Diagnose one failing config of zaminfluence/tests/testthat/test_derivs.R.
#
# See notes/test_derivs_diagnosis/README.md for the background. This script
# replays the RNG-advance pattern used by the test, runs each config against
# both the torch-autograd path (via compute_model_influence) and the pure-R
# complex-step reference defined inside the test, and dumps:
#
# 1. The generated fixture (x, y, z, weights, se_group) to an .rds.
# 2. Condition numbers for the key matrices (X'WX, Z'WX, and the grouped-SE
#    meat matrix when applicable).
# 3. A side-by-side comparison of coefficients and standard errors from the
#    two implementations.
# 4. A side-by-side comparison of param_grad and se_grad from the two
#    implementations for each kept parameter.
#
# Output is written to notes/test_derivs_diagnosis/fixture-<CONFIG>.rds and
# notes/test_derivs_diagnosis/report.md. Run from the repo root via:
#
#   Rscript notes/test_derivs_diagnosis/capture_failing_fixture.R
#
# This script does NOT mutate the test suite and does NOT assert anything;
# it's purely diagnostic.

# --- Setup ----------------------------------------------------------------

suppressPackageStartupMessages({
  devtools::load_all("zaminfluence")
  library(ivreg)
})

out_dir <- "notes/test_derivs_diagnosis"
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

# --- Pure-R reference implementation (copied verbatim from test_derivs.R) -
# Kept identical in behavior to the reference used by the failing test, so
# the comparison here is faithful to what the test does.

PureRComputeCoeffAndSE <- function(x, y, w, z=NULL, se_group=NULL) {
  z_equals_x <- is.null(z)
  if (z_equals_x) z <- x
  n <- nrow(x); p <- ncol(x)

  zw <- z * as.vector(w)
  ZWX <- t(zw) %*% x
  ZWy <- t(zw) %*% matrix(y, ncol=1)
  betahat <- solve(ZWX, ZWy)
  eps <- y - as.vector(x %*% betahat)

  if (!is.null(se_group)) {
    g <- as.integer(factor(se_group))
    G <- max(g)
    score_mat <- z * as.vector(eps) * as.vector(w)
    score_sum <- matrix(0, nrow=G, ncol=p)
    for (i in seq_len(n)) score_sum[g[i], ] <- score_sum[g[i], ] + score_mat[i, ]
    s_mat <- score_sum - matrix(colMeans(score_sum), nrow=G, ncol=p, byrow=TRUE)
    V <- t(s_mat) %*% s_mat / G
    SE_cov <- solve(ZWX, t(solve(ZWX, V))) * G
  } else {
    sig2 <- sum(w * eps^2) / (n - p)
    if (z_equals_x) {
      SE_cov <- sig2 * solve(ZWX)
    } else {
      ZWZ <- t(zw) %*% z
      SE_cov <- sig2 * solve(ZWX, t(solve(ZWX, ZWZ)))
    }
  }
  se <- sqrt(diag(SE_cov))
  list(betahat=as.vector(betahat), se=as.vector(se), SE_cov=SE_cov, ZWX=ZWX)
}

# Complex-step jacobian: columnwise d f(w) / d w_i evaluated at w.
complex_step_jacobian <- function(f, w, h=1e-20) {
  n <- length(w)
  f0 <- f(w)
  out <- matrix(NA_real_, nrow=length(f0), ncol=n)
  for (i in seq_len(n)) {
    ww <- as.complex(w)
    ww[i] <- ww[i] + complex(imaginary=h)
    out[, i] <- Im(f(ww)) / h
  }
  out
}

# --- Replay test_derivs.R config loop --------------------------------------

set.seed(302)
num_obs <- 50
w_rand <- runif(num_obs) + 1
w_ones <- rep(1, num_obs)

test_configs <- expand.grid(
  num_groups=c(10, -1),
  random_weights=c(TRUE, FALSE),
  do_iv=c(TRUE, FALSE),
  keep_pars=c(1, 2, 3)
)

failing_report <- list()
first_fixture_saved <- FALSE

for (n_row in seq_len(nrow(test_configs))) {
  config <- test_configs[n_row, ]
  tag <- paste(as.character(config), collapse="_")
  weights <- if (config$random_weights) w_rand else w_ones
  keep_pars <-
    if (config$keep_pars == 1) c("x1")
    else if (config$keep_pars == 2) c("x2", "x1")
    else NULL
  num_groups <- if (config$num_groups == -1) NULL else config$num_groups

  # Data generation (this advances the RNG exactly the way test_derivs does)
  if (config$do_iv) {
    df <- generate_iv_regression_data(num_obs, c(0.5, -0.5, 0.0), num_groups=num_groups)
    fit_object <- ivreg(y ~ x1 + x2 + x3 + 1 | z1 + z2 + z3 + 1,
                        data=df, x=TRUE, y=TRUE, weights=weights)
    x <- fit_object$x$regressors
    z <- fit_object$x$instruments
  } else {
    df <- generate_regression_data(num_obs, c(0.5, -0.5, 0.0), num_groups=num_groups)
    fit_object <- lm(y ~ x1 + x2 + x3 + 1, df, x=TRUE, y=TRUE, weights=weights)
    x <- fit_object$x
    z <- NULL
  }
  y <- as.numeric(fit_object$y)
  se_group <- df[["se_group"]]

  # Run both implementations
  mg <- compute_model_influence(fit_object, se_group=se_group, keep_pars=keep_pars)
  w0 <- mg$model_fit$weights
  pure <- PureRComputeCoeffAndSE(x, y, w0, z, se_group)

  # Complex-step reference gradients
  coeff_fun <- function(w) PureRComputeCoeffAndSE(x, y, w, z, se_group)$betahat
  se_fun    <- function(w) PureRComputeCoeffAndSE(x, y, w, z, se_group)$se
  param_jac <- complex_step_jacobian(coeff_fun, w0)
  se_jac    <- complex_step_jacobian(se_fun, w0)

  # Condition numbers
  z_mat <- if (is.null(z)) x else z
  zw <- z_mat * as.vector(w0)
  ZWX <- t(zw) %*% x
  kappa_ZWX <- kappa(ZWX)
  kappa_ZWZ <- if (!is.null(z)) kappa(t(zw) %*% z) else NA_real_

  # Per-parameter gradient comparison
  par_diffs <- list()
  for (par in mg$parameter_names) {
    fit_i  <- get_parameter_index(mg$model_fit, par)
    grad_i <- get_parameter_index(mg, par)
    pd <- max(abs(mg$param_grad[grad_i, ] - param_jac[fit_i, ]))
    sd <- max(abs(mg$se_grad[grad_i, ]    - se_jac[fit_i, ]))
    par_diffs[[par]] <- c(param_grad=pd, se_grad=sd)
  }
  worst <- max(unlist(par_diffs))

  failing_report[[tag]] <- list(
    config=as.list(config),
    kappa_ZWX=kappa_ZWX,
    kappa_ZWZ=kappa_ZWZ,
    coeff_agree_torch_vs_pureR=max(abs(mg$model_fit$param - pure$betahat)),
    se_agree_torch_vs_pureR=max(abs(mg$model_fit$se - pure$se)),
    grad_max_discrepancy=worst,
    per_param_max_diff=par_diffs
  )

  # Save the first over-tolerance fixture we find (for reproducibility)
  if (!first_fixture_saved && worst > 1e-9) {
    saveRDS(
      list(config=as.list(config), x=x, y=y, z=z, weights=w0, se_group=se_group,
           torch=list(betahat=mg$model_fit$param, se=mg$model_fit$se,
                      param_grad=mg$param_grad, se_grad=mg$se_grad),
           pureR=list(betahat=pure$betahat, se=pure$se,
                      param_grad_csr=param_jac, se_grad_csr=se_jac)),
      file=file.path(out_dir, sprintf("fixture-%s.rds", tag))
    )
    cat(sprintf("Saved fixture for first failing config: %s\n", tag))
    first_fixture_saved <- TRUE
  }
}

# --- Write markdown report -------------------------------------------------

con <- file(file.path(out_dir, "report.md"), open="w")
on.exit(close(con))
writeLines(c(
  "# test_derivs diagnostic report",
  "",
  sprintf("_Generated %s_", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "Ran each of the 24 configurations from `test_derivs.R` in isolation.",
  "Columns:",
  "",
  "- `kappa_ZWX`, `kappa_ZWZ`: condition numbers of the relevant IV/OLS matrices.",
  "- `coeff_diff`, `se_diff`: max absolute disagreement between the package's",
  "  torch path and the pure-R reference implementation on the base values (before",
  "  differentiation).",
  "- `worst_grad`: max absolute disagreement on any gradient entry across all",
  "  kept parameters.",
  "- Threshold used by the test: `1e-9`.",
  "",
  "| config (num_groups, rand_w, do_iv, keep_pars) | kappa_ZWX | kappa_ZWZ | coeff_diff | se_diff | worst_grad | over_tol |",
  "|---|---:|---:|---:|---:|---:|:---:|"
), con)
for (tag in names(failing_report)) {
  r <- failing_report[[tag]]
  over <- if (r$grad_max_discrepancy > 1e-9) "**YES**" else "no"
  writeLines(sprintf(
    "| %s | %.2e | %s | %.2e | %.2e | %.2e | %s |",
    gsub("_", ", ", tag),
    r$kappa_ZWX,
    if (is.na(r$kappa_ZWZ)) "—" else sprintf("%.2e", r$kappa_ZWZ),
    r$coeff_agree_torch_vs_pureR,
    r$se_agree_torch_vs_pureR,
    r$grad_max_discrepancy,
    over
  ), con)
}
cat("Wrote report:", file.path(out_dir, "report.md"), "\n")
