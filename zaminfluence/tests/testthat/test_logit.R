#!/usr/bin/env Rscript

# Tests for logistic regression influence functions.

library(zaminfluence)
library(testthat)
library(numDeriv)

context("logit")


test_that("logit base values match glm", {
  set.seed(123)
  df <- GenerateLogitData(200, c(0.5, -0.3))
  glm_res <- glm(y ~ x1 + x2 + 1, data=df, family=binomial, x=TRUE, y=TRUE)

  model_grads <-
    ComputeModelInfluence(glm_res) |>
    AppendTargetRegressorInfluence("x1")

  # Coefficients match
  AssertNearlyEqual(
    model_grads$model_fit$param, coef(glm_res), desc="param equal")

  # Model-based SEs match vcov(glm_res) for binomial (dispersion=1)
  # Use tol=1e-6 because our SE is computed from scratch while vcov(glm_res)
  # uses the IRLS-derived quantities, leading to small numerical differences.
  se_r <- sqrt(diag(vcov(glm_res)))
  AssertNearlyEqual(
    model_grads$model_fit$se, se_r, tol=1e-6, desc="std error equal")

  # Number of observations
  expect_equal(model_grads$model_fit$num_obs, nrow(df))

  # Parameter names
  expect_equal(
    model_grads$model_fit$parameter_names, names(coef(glm_res)))

  # RerunFun reproduces original values
  rerun <- model_grads$RerunFun(glm_res$prior.weights)
  AssertNearlyEqual(
    rerun$param, coef(glm_res), tol=1e-6, desc="rerun param equal")
  AssertNearlyEqual(
    rerun$se, se_r, tol=1e-6, desc="rerun se equal")
})


test_that("logit derivatives match numerical derivatives", {
  TestLogitDerivs <- function(model_grads) {
    RerunCoeff <- function(w) {
      rerun_fit <- model_grads$RerunFun(w)
      return(rerun_fit$param)
    }

    RerunSe <- function(w) {
      rerun_fit <- model_grads$RerunFun(w)
      return(rerun_fit$se)
    }

    # Suppress "non-integer #successes" warnings from numDeriv weight perturbations
    betahat_grad <- suppressWarnings(numDeriv::jacobian(
      RerunCoeff, model_grads$model_fit$weights))
    se_grad <- suppressWarnings(numDeriv::jacobian(
      RerunSe, model_grads$model_fit$weights))

    for (par in model_grads$parameter_names) {
      fit_ind <- GetParameterIndex(model_grads$model_fit, par)
      grad_ind <- GetParameterIndex(model_grads, par)
      AssertNearlyEqual(
        model_grads$param_grad[grad_ind, ], betahat_grad[fit_ind, ],
        tol=1e-6, desc=paste("param_grad", par))
      AssertNearlyEqual(
        model_grads$se_grad[grad_ind, ], se_grad[fit_ind, ],
        tol=1e-6, desc=paste("se_grad", par))
    }
  }

  set.seed(42)
  num_obs <- 30

  # Some configs use non-integer prior weights (runif + 1). This triggers R's

  # "non-integer #successes in a binomial glm!" warning, which is harmless here.
  # We need to test at non-integer weights because zaminfluence computes
  # derivatives dβ/dw and dSE/dw with respect to a continuous weight vector.
  # When the pipeline drops observations it sets weights toward zero, so the
  # gradients must be correct at arbitrary (non-integer) weight vectors.
  configs <- list(
    list(param=c(0.5), weights=rep(1, num_obs), keep_pars=NULL),
    list(param=c(0.5), weights=runif(num_obs) + 1, keep_pars=NULL),
    list(param=c(0.5, -0.3), weights=rep(1, num_obs), keep_pars=c("x1")),
    list(param=c(0.5, -0.3, 0.2), weights=runif(num_obs) + 1, keep_pars=NULL)
  )

  for (cfg in configs) {
    df <- GenerateLogitData(num_obs, cfg$param)
    x_names <- paste0("x", seq_along(cfg$param))
    form <- formula(paste("y ~", paste(x_names, collapse=" + "), "+ 1"))
    glm_res <- glm(form, data=df, family=binomial, x=TRUE, y=TRUE,
                   weights=cfg$weights)

    model_grads <- ComputeModelInfluence(glm_res, keep_pars=cfg$keep_pars)
    cat(" Testing logit derivatives: p =", length(cfg$param),
        ", weighted =", !all(cfg$weights == 1),
        ", keep_pars =", paste(cfg$keep_pars %||% "all", collapse=","), "\n")
    TestLogitDerivs(model_grads)
  }
})


test_that("logit end-to-end pipeline works", {
  set.seed(42)
  df <- GenerateLogitData(500, c(0.5))
  glm_res <- glm(y ~ x1 + 1, data=df, family=binomial, x=TRUE, y=TRUE)

  model_grads <-
    ComputeModelInfluence(glm_res) |>
    AppendTargetRegressorInfluence("x1")

  signals <- GetInferenceSignals(model_grads)
  reruns <- RerunForSignals(signals, model_grads)
  preds <- PredictForSignals(signals, model_grads)

  # Verify the pipeline ran and produced expected structure
  expect_true("x1" %in% names(signals))
  expect_true(all(c("sign", "sig", "both") %in% names(signals[["x1"]])))
  expect_true("x1" %in% names(reruns))
  expect_true("x1" %in% names(preds))

  # Verify predictions and reruns are both produced for successful signals
  for (signal_name in c("sign", "sig", "both")) {
    signal <- signals[["x1"]][[signal_name]]
    if (!signal$apip$success) next
    expect_true(!is.null(reruns[["x1"]][[signal_name]]))
    expect_true(!is.null(preds[["x1"]][[signal_name]]))
  }
})


test_that("logit unsupported inputs error", {
  set.seed(99)
  df <- GenerateLogitData(100, c(0.5))

  # Clustered SEs not supported
  glm_res <- glm(y ~ x1 + 1, data=df, family=binomial, x=TRUE, y=TRUE)
  expect_error(
    ComputeLogitInfluence(glm_res, se_group=rep(1:10, each=10)),
    "Clustered SEs for logit not yet implemented")

  # quasibinomial not supported
  glm_quasi <- glm(y ~ x1 + 1, data=df, family=quasibinomial, x=TRUE, y=TRUE)
  expect_error(
    ComputeLogitInfluence(glm_quasi),
    "Only binomial")

  # Missing x=TRUE: both ComputeLogitInfluence and CheckLogitDiagnostics
  glm_nox <- glm(y ~ x1 + 1, data=df, family=binomial, y=TRUE)
  expect_error(
    ComputeLogitInfluence(glm_nox),
    "x=TRUE")
  expect_error(
    CheckLogitDiagnostics(glm_nox),
    "x=TRUE")

  # Non-binary response: construct a glm object that bypasses glm()'s own check
  # by directly modifying the y vector after fitting
  glm_good <- glm(y ~ x1 + 1, data=df, family=binomial, x=TRUE, y=TRUE)
  glm_good$y <- df$y + 0.5
  expect_error(
    ComputeLogitInfluence(glm_good),
    "binary")
})


test_that("logit with offset works", {
  set.seed(77)
  num_obs <- 200
  df <- GenerateLogitData(num_obs, c(0.5, -0.3))
  df$off <- rnorm(num_obs, sd=0.5)

  glm_res <- glm(y ~ x1 + x2 + 1, data=df, family=binomial,
                 offset=off, x=TRUE, y=TRUE)

  model_grads <-
    ComputeModelInfluence(glm_res) |>
    AppendTargetRegressorInfluence("x1")

  # Coefficients match
  AssertNearlyEqual(
    model_grads$model_fit$param, coef(glm_res), desc="offset param equal")

  # SEs match vcov(glm_res)
  se_r <- sqrt(diag(vcov(glm_res)))
  AssertNearlyEqual(
    model_grads$model_fit$se, se_r, tol=1e-6, desc="offset se equal")

  # RerunFun at original weights reproduces the original fit
  rerun <- model_grads$RerunFun(glm_res$prior.weights)
  AssertNearlyEqual(
    rerun$param, coef(glm_res), tol=1e-6, desc="offset rerun param equal")
  AssertNearlyEqual(
    rerun$se, se_r, tol=1e-6, desc="offset rerun se equal")

  # Numerical derivative check for offset model
  RerunCoeff <- function(w) model_grads$RerunFun(w)$param
  RerunSe <- function(w) model_grads$RerunFun(w)$se
  betahat_grad <- suppressWarnings(numDeriv::jacobian(
    RerunCoeff, model_grads$model_fit$weights))
  se_grad <- suppressWarnings(numDeriv::jacobian(
    RerunSe, model_grads$model_fit$weights))

  for (par in model_grads$parameter_names) {
    fit_ind <- GetParameterIndex(model_grads$model_fit, par)
    grad_ind <- GetParameterIndex(model_grads, par)
    AssertNearlyEqual(
      model_grads$param_grad[grad_ind, ], betahat_grad[fit_ind, ],
      tol=1e-6, desc=paste("offset param_grad", par))
    AssertNearlyEqual(
      model_grads$se_grad[grad_ind, ], se_grad[fit_ind, ],
      tol=1e-6, desc=paste("offset se_grad", par))
  }
})
