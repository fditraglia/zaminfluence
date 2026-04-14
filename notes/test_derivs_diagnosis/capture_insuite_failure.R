# Companion to capture_failing_fixture.R: run the same diagnostic *after*
# the full test suite has executed, to capture whatever in-suite state
# corrupts the comparison. The in-suite run is the only context we have
# seen test_derivs actually fail in, so we want a record of the "bad"
# state too.
#
# Usage (from repo root):
#   Rscript notes/test_derivs_diagnosis/capture_insuite_failure.R
#
# What it does:
# 1. Runs the subset of the test suite that executes BEFORE test_derivs in
#    alphabetical order (test_base_values, test_catchall). This warms up
#    the session the same way `devtools::test()` would by the time it
#    reached test_derivs.
# 2. Inlines the 24-config diagnostic in that now-warm session.
# 3. Writes report_insuite.md alongside report.md, and also dumps a fixture
#    for the first failing config.

suppressPackageStartupMessages({
  devtools::load_all("zaminfluence")
  library(ivreg)
})

message("Warming up with the tests that run before test_derivs...")
invisible(devtools::test(pkg="zaminfluence", filter="base_values", reporter="silent"))
invisible(devtools::test(pkg="zaminfluence", filter="catchall",    reporter="silent"))

message("Replaying the 24-config diagnostic in the warmed session...")

# Override the output path so the standalone report isn't clobbered
out_dir      <- "notes/test_derivs_diagnosis"
report_path  <- file.path(out_dir, "report_insuite.md")
fixture_path_tmpl <- file.path(out_dir, "fixture-insuite-%s.rds")

# Inline the diagnostic with local overrides for where it writes

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
    g <- as.integer(factor(se_group)); G <- max(g)
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

complex_step_jacobian <- function(f, w, h=1e-20) {
  n <- length(w); f0 <- f(w)
  out <- matrix(NA_real_, nrow=length(f0), ncol=n)
  for (i in seq_len(n)) {
    ww <- as.complex(w); ww[i] <- ww[i] + complex(imaginary=h)
    out[, i] <- Im(f(ww)) / h
  }
  out
}

set.seed(302)
num_obs <- 50
w_rand <- runif(num_obs) + 1
w_ones <- rep(1, num_obs)
test_configs <- expand.grid(
  num_groups=c(10, -1), random_weights=c(TRUE, FALSE),
  do_iv=c(TRUE, FALSE), keep_pars=c(1, 2, 3)
)

rows <- list()
first_saved <- FALSE
for (n_row in seq_len(nrow(test_configs))) {
  config <- test_configs[n_row, ]
  tag <- paste(as.character(config), collapse="_")
  weights <- if (config$random_weights) w_rand else w_ones
  keep_pars <-
    if (config$keep_pars == 1) c("x1")
    else if (config$keep_pars == 2) c("x2", "x1")
    else NULL
  num_groups <- if (config$num_groups == -1) NULL else config$num_groups

  if (config$do_iv) {
    df <- generate_iv_regression_data(num_obs, c(0.5, -0.5, 0.0), num_groups=num_groups)
    fit_object <- ivreg(y ~ x1 + x2 + x3 + 1 | z1 + z2 + z3 + 1,
                        data=df, x=TRUE, y=TRUE, weights=weights)
    x <- fit_object$x$regressors; z <- fit_object$x$instruments
  } else {
    df <- generate_regression_data(num_obs, c(0.5, -0.5, 0.0), num_groups=num_groups)
    fit_object <- lm(y ~ x1 + x2 + x3 + 1, df, x=TRUE, y=TRUE, weights=weights)
    x <- fit_object$x; z <- NULL
  }
  y <- as.numeric(fit_object$y)
  se_group <- df[["se_group"]]

  mg <- compute_model_influence(fit_object, se_group=se_group, keep_pars=keep_pars)
  w0 <- mg$model_fit$weights
  pure <- PureRComputeCoeffAndSE(x, y, w0, z, se_group)

  coeff_fun <- function(w) PureRComputeCoeffAndSE(x, y, w, z, se_group)$betahat
  se_fun    <- function(w) PureRComputeCoeffAndSE(x, y, w, z, se_group)$se
  param_jac <- complex_step_jacobian(coeff_fun, w0)
  se_jac    <- complex_step_jacobian(se_fun, w0)

  z_mat <- if (is.null(z)) x else z
  zw <- z_mat * as.vector(w0)
  kappa_ZWX <- kappa(t(zw) %*% x)
  kappa_ZWZ <- if (!is.null(z)) kappa(t(zw) %*% z) else NA_real_

  par_diffs <- list()
  for (par in mg$parameter_names) {
    fit_i  <- get_parameter_index(mg$model_fit, par)
    grad_i <- get_parameter_index(mg, par)
    pd <- max(abs(mg$param_grad[grad_i, ] - param_jac[fit_i, ]))
    sd <- max(abs(mg$se_grad[grad_i, ]    - se_jac[fit_i, ]))
    par_diffs[[par]] <- c(param_grad=pd, se_grad=sd)
  }
  worst <- max(unlist(par_diffs))

  rows[[tag]] <- list(
    tag=tag, kappa_ZWX=kappa_ZWX, kappa_ZWZ=kappa_ZWZ,
    coeff_diff=max(abs(mg$model_fit$param - pure$betahat)),
    se_diff=max(abs(mg$model_fit$se - pure$se)),
    worst=worst
  )

  if (!first_saved && worst > 1e-9) {
    saveRDS(
      list(config=as.list(config), x=x, y=y, z=z, weights=w0, se_group=se_group,
           torch=list(betahat=mg$model_fit$param, se=mg$model_fit$se,
                      param_grad=mg$param_grad, se_grad=mg$se_grad),
           pureR=list(betahat=pure$betahat, se=pure$se,
                      param_grad_csr=param_jac, se_grad_csr=se_jac)),
      file=sprintf(fixture_path_tmpl, tag)
    )
    cat(sprintf("Saved in-suite fixture for first failing config: %s\n", tag))
    first_saved <- TRUE
  }
}

con <- file(report_path, open="w")
writeLines(c(
  "# test_derivs diagnostic report (IN-SUITE run)",
  "",
  sprintf("_Generated %s_", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "Same 24-config diagnostic as `report.md`, but this run was preceded by",
  "`devtools::test(filter=\"base_values\")` and `devtools::test(filter=\"catchall\")`,",
  "to mimic the state that test_derivs would see when the whole suite runs.",
  "",
  "Compare the `worst_grad` column against `report.md`. If the numbers are",
  "much larger here, then the in-suite state is what destabilizes the test —",
  "not the data, not the math.",
  "",
  "| config | kappa_ZWX | kappa_ZWZ | coeff_diff | se_diff | worst_grad | over_tol |",
  "|---|---:|---:|---:|---:|---:|:---:|"
), con)
for (r in rows) {
  over <- if (r$worst > 1e-9) "**YES**" else "no"
  writeLines(sprintf("| %s | %.2e | %s | %.2e | %.2e | %.2e | %s |",
    gsub("_", ", ", r$tag),
    r$kappa_ZWX,
    if (is.na(r$kappa_ZWZ)) "—" else sprintf("%.2e", r$kappa_ZWZ),
    r$coeff_diff, r$se_diff, r$worst, over
  ), con)
}
close(con)
cat("Wrote:", report_path, "\n")
