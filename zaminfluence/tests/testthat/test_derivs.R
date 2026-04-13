#!/usr/bin/env Rscript

# Test analytical derivatives (torch autograd) against reference derivatives
# computed via the complex step method on a pure-R reimplementation.
#
# Why complex step instead of finite differences (numDeriv)?
# Finite differences compute f'(x) ≈ (f(x+h) - f(x-h)) / 2h, which suffers
# from cancellation error when h is small. For our SE computation (nested
# matrix inverses, sandwich estimators), the curvature is severe enough that
# no step size h gives reliable results — numDeriv fails on many configs.
#
# The complex step computes f'(x) = Im(f(x + ih)) / h. There is no
# subtraction of nearby reals, so h can be ~1e-20, yielding machine-precision
# derivatives. The requirement is that f can be evaluated with complex
# arithmetic (no conjugation, abs(), or branching on real/imaginary parts).
#
# Why a pure-R reimplementation instead of feeding complex weights through
# the existing torch computation?
# Torch supports complex tensors (torch_cdouble), so in principle we could
# use complex step directly on the torch code. But that would only test
# whether torch's autograd is internally consistent — it wouldn't catch bugs
# in our formulas (wrong sign, transposed matrix, etc.), since both autograd
# and complex step would traverse the same wrong graph. The pure-R version
# is an independent implementation: if it agrees with torch at real weights,
# and its complex step derivatives agree with torch's autograd, both the
# formulas and the gradients are validated.


test_that("derivatives work", {
  skip_if_not_installed("ivreg")
  set.seed(302)

  # Pure-R computation of betahat and SE, compatible with complex weights.
  # Uses t() throughout (not crossprod) to avoid conjugation, preserving
  # analyticity for complex step differentiation.
  PureRComputeCoeffAndSE <- function(x, y, w, z=NULL, se_group=NULL) {
    z_equals_x <- is.null(z)
    if (z_equals_x) z <- x
    n <- nrow(x)
    p <- ncol(x)

    zw <- z * as.vector(w)
    ZWX <- t(zw) %*% x
    ZWy <- t(zw) %*% matrix(y, ncol=1)
    betahat <- solve(ZWX, ZWy)
    eps <- matrix(y, ncol=1) - x %*% betahat

    if (is.null(se_group)) {
      sig2 <- sum(as.vector(w) * as.vector(eps)^2) / (n - p)
      if (z_equals_x) {
        se_cov <- as.vector(sig2) * solve(ZWX)
      } else {
        ZWZ <- t(zw) %*% z
        ZWX_inv <- solve(ZWX)
        se_cov <- as.vector(sig2) * ZWX_inv %*% ZWZ %*% t(ZWX_inv)
      }
    } else {
      # Clustered SEs (HC0, no small-sample adjustment).
      # Matches the torch implementation: group scores are demeaned before
      # forming the meat matrix, which is equivalent to the standard formula
      # because the score FOC ensures the group scores sum to zero.
      groups <- sort(unique(se_group))
      num_groups <- length(groups)
      score_sums <- matrix(0+0i, num_groups, p)
      for (gi in seq_along(groups)) {
        idx <- which(se_group == groups[gi])
        score_sums[gi, ] <-
          t(z[idx, , drop=FALSE]) %*%
          (as.vector(w)[idx] * as.vector(eps)[idx])
      }
      score_means <- matrix(
        colMeans(score_sums), nrow=num_groups, ncol=p, byrow=TRUE)
      s_mat <- score_sums - score_means
      v_mat <- t(s_mat) %*% s_mat / num_groups
      ZWX_inv <- solve(ZWX)
      se_cov <- ZWX_inv %*% v_mat %*% t(ZWX_inv) * num_groups
    }

    se <- sqrt(diag(se_cov))
    list(betahat=as.vector(betahat), se=as.vector(se))
  }


  # Complex step Jacobian: exact derivatives with no cancellation error.
  ComplexStepJacobian <- function(f, x, h=1e-20) {
    n <- length(x)
    f0 <- f(x)
    m <- length(f0)
    jac <- matrix(0, m, n)
    for (j in 1:n) {
      x_pert <- as.complex(x)
      x_pert[j] <- x_pert[j] + 1i * h
      jac[, j] <- Im(f(x_pert)) / h
    }
    jac
  }


  TestDerivs <- function(model_grads, x, y, z, se_group) {
    w0 <- model_grads$model_fit$weights

    # Verify pure-R computation matches torch at real weights
    pure_r <- PureRComputeCoeffAndSE(x, y, w0, z, se_group)
    assert_nearly_equal(
      Re(pure_r$betahat), model_grads$model_fit$param,
      desc="pure R betahat matches torch")
    assert_nearly_equal(
      Re(pure_r$se), model_grads$model_fit$se,
      desc="pure R se matches torch")

    # Complex step reference derivatives
    CoeffFun <- function(w) {
      PureRComputeCoeffAndSE(x, y, w, z, se_group)$betahat
    }
    SEFun <- function(w) {
      PureRComputeCoeffAndSE(x, y, w, z, se_group)$se
    }

    param_jac <- ComplexStepJacobian(CoeffFun, w0)
    se_jac <- ComplexStepJacobian(SEFun, w0)

    # Compare autograd derivatives against complex step reference
    for (par in model_grads$parameter_names) {
      fit_ind <- get_parameter_index(model_grads$model_fit, par)
      grad_ind <- get_parameter_index(model_grads, par)
      assert_nearly_equal(
        model_grads$param_grad[grad_ind, ], param_jac[fit_ind, ],
        desc=paste("param_grad", par))
      assert_nearly_equal(
        model_grads$se_grad[grad_ind, ], se_jac[fit_ind, ],
        desc=paste("se_grad", par))
    }
  }

  TestRegressionConfigurationDerivs <- function(
        num_groups, weights, keep_pars, do_iv) {
    if (do_iv) {
      df <- generate_iv_regression_data(
        num_obs, c(0.5, -0.5, 0.0), num_groups=num_groups)
      fit_object <- ivreg(y ~ x1 + x2 + x3 + 1 | z1 + z2 + z3 + 1,
                      data=df, x=TRUE, y=TRUE, weights=weights)
      x <- fit_object$x$regressors
      z <- fit_object$x$instruments
    } else {
      df <- generate_regression_data(
        num_obs, c(0.5, -0.5, 0.0), num_groups=num_groups)
      fit_object <-
        lm(y ~ x1 + x2 + x3 + 1, df, x=TRUE, y=TRUE, weights=weights)
      x <- fit_object$x
      z <- NULL
    }
    se_group <- df[["se_group"]]

    model_grads <-
      compute_model_influence(
        fit_object, se_group=se_group, keep_pars=keep_pars)
    TestDerivs(model_grads, x, as.numeric(fit_object$y), z, se_group)
  }

  test_configs <- expand.grid(
    num_groups=c(10, -1),
    random_weights=c(TRUE, FALSE),
    do_iv=c(TRUE, FALSE),
    keep_pars=c(1, 2, 3)
  )

  num_obs <- 50

  w_rand <- runif(num_obs) + 1
  w_ones <- rep(1, num_obs)

  for (n in 1:nrow(test_configs)) {
    config <- test_configs[n, ]
    cat(" Testing derivatives for config ",
        paste(as.character(config), collapse=", "), "\n")
    weights <- if (config$random_weights) w_rand else w_ones
    keep_pars <-
      if (config$keep_pars == 1) {
        c("x1")
      } else if (config$keep_pars == 2) {
        c("x2", "x1")
      } else {
        NULL
      }
    num_groups <- if (config$num_groups == -1) NULL else config$num_groups
    TestRegressionConfigurationDerivs(
      num_groups, weights, keep_pars, config$do_iv)
  }
})
