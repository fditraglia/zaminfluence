# Test the manually computed OLS and IV solutions in ols_iv_grads_lib.R

# Test that compute_model_influence, append_target_regressor_influence, and
# rerun_fun give the same answers as R on the original data.
TestConfiguration <- function(fit_object, se_group) {
  model_grads <-
    compute_model_influence(fit_object, se_group=se_group) |>
    append_target_regressor_influence("x1")

  # Test that the coefficient estimates and standard errors in model_grads
  # match what we expect from R.
  assert_nearly_equal(
    model_grads$model_fit$param, coefficients(fit_object), desc="param equal")
  se_r <- get_fit_covariance(fit_object, se_group) |> diag() |> sqrt()
  assert_nearly_equal(
    model_grads$model_fit$se, se_r, desc="std error equal")
  testthat::expect_equivalent(
    model_grads$model_fit$num_obs, length(fit_object$y), info="num obs")
  # testthat::expect_equivalent(
  #   model_grads$weights, model_fit$weights, info="weights")
  testthat::expect_equivalent(
    model_grads$model_fit$parameter_names, names(coefficients(fit_object)),
    info="column names")

  # Test that the base values in param_infl are correct.
  param_infl <- model_grads$param_infls[["x1"]]
  target_index <- get_parameter_index(model_grads$model_fit, "x1")
  testthat::expect_equivalent(
    "x1", names(coefficients(fit_object))[target_index], info="target index")
  testthat::expect_equivalent(
    param_infl$param$base_value,
    coefficients(fit_object)[target_index],
    info="param base value")
  testthat::expect_equivalent(
    param_infl$param_pzse$base_value,
    coefficients(fit_object)[target_index] +
      param_infl$sig_num_ses * se_r[target_index],
    info="param_pzse base value")
  testthat::expect_equivalent(
    param_infl$param_mzse$base_value,
    coefficients(fit_object)[target_index] -
      param_infl$sig_num_ses * se_r[target_index],
    info="param_mzse base value")

  # Test that if we re-run we get the same answer.
  rerun <- model_grads$rerun_fun(fit_object$weights)
  assert_nearly_equal(
    rerun$param, coefficients(fit_object), desc="rerun param equal")
  assert_nearly_equal(
    rerun$se, se_r, desc="rerun std error equal")
}


test_that("regression works", {
  # Grouped configs (num_groups=10) route through get_fit_covariance ->
  # sandwich::vcovCL; sandwich is Suggests-only.
  have_sandwich <- requireNamespace("sandwich", quietly=TRUE)
  TestRegressionConfiguration <- function(num_groups, weights) {
    df <- generate_regression_data(100, 0.5, num_groups=num_groups)
    fit_object <- lm(y ~ x1 + 1, df, x=TRUE, y=TRUE, weights=weights)
    TestConfiguration(fit_object, se_group=df[["se_group"]])
  }

  TestRegressionConfiguration(num_groups=NULL, weights=NULL)
  TestRegressionConfiguration(num_groups=NULL, weights=runif(100))
  if (have_sandwich) {
    TestRegressionConfiguration(num_groups=10, weights=NULL)
    TestRegressionConfiguration(num_groups=10, weights=runif(100))
  }

  if (requireNamespace("ivreg", quietly=TRUE)) {
    TestIVRegressionConfiguration <- function(num_groups, weights) {
      df <- generate_iv_regression_data(100, 0.5, num_groups=num_groups)
      iv_res <- ivreg(y ~ x1 + 1 | z1 + 1,
                      data=df, x=TRUE, y=TRUE, weights=weights)
      TestConfiguration(iv_res, se_group=df[["se_group"]])
    }

    TestIVRegressionConfiguration(num_groups=NULL, weights=NULL)
    TestIVRegressionConfiguration(num_groups=NULL, weights=runif(100))
    if (have_sandwich) {
      TestIVRegressionConfiguration(num_groups=10, weights=NULL)
      TestIVRegressionConfiguration(num_groups=10, weights=runif(100))
    }
  }
})


##########################################################################
##########################################################################


test_that("se groups can be non-ordered", {
  # Entire test is about grouped-SE handling, which goes through
  # sandwich::vcovCL via get_fit_covariance.
  skip_if_not_installed("sandwich")
  num_obs <- 100
  df <- generate_iv_regression_data(num_obs, 0.5, num_groups=10)
  reg_res <- lm(y ~ x1 + 1, data=df, x=TRUE, y=TRUE)
  iv_res <- if (requireNamespace("ivreg", quietly=TRUE)) {
    ivreg(y ~ x1 + 1 | z1 + 1, data=df, x=TRUE, y=TRUE)
  } else {
    NULL
  }

  TestSEGroup <- function(se_group) {
    reg_zam <- compute_regression_results(reg_res, se_group=se_group)
    # The coefficients shouldn't depend on se_group, but test for good measure
    assert_nearly_equal(reg_zam$betahat, reg_res$coefficients)
    assert_nearly_equal(
      as.numeric(reg_zam$se_mat), get_fit_covariance(reg_res, se_group=se_group))

    if (!is.null(iv_res)) {
      iv_zam <- compute_iv_regression_results(iv_res, se_group=se_group)
      assert_nearly_equal(iv_zam$betahat, iv_res$coefficients)
      assert_nearly_equal(
        as.numeric(iv_zam$se_mat), get_fit_covariance(iv_res, se_group=se_group))
    }
  }

  TestSEGroup(NULL)
  ordered_groups <- rep(1:20, each=5)
  TestSEGroup(ordered_groups)
  TestSEGroup(ordered_groups + 50)
  TestSEGroup((ordered_groups + 2) * 2)
  TestSEGroup(ordered_groups[sample(num_obs, replace=TRUE)])
  TestSEGroup(ordered_groups[sample(num_obs)])
})


# Check that rerun matches R with left-out observations.
test_that("rerun works", {
  have_ivreg <- requireNamespace("ivreg", quietly=TRUE)
  # Grouped-SE paths (use_se_group=TRUE below) exercise sandwich::vcovCL.
  have_sandwich <- requireNamespace("sandwich", quietly=TRUE)
  # Generate base data.
  num_obs <- 100
  df <- generate_iv_regression_data(num_obs, 0.5, num_groups=10)
  df$w <- runif(num_obs) + 0.5

  reg_fit <- lm(y ~ x1 + 1, data=df, x=TRUE, y=TRUE, weights=df$w)
  iv_fit <- if (have_ivreg) {
    ivreg(y ~ x1 + 1 | z1 + 1, data=df, x=TRUE, y=TRUE, weights=df$w)
  } else NULL

  # Use Rerun to get fits using our code.  Check that our results
  # match R's results.  (Note that this is only an extra sanity check
  # here --- this is principally tested above in TestConfiguration)
  if (have_sandwich) {
    zam_reg_fit <- compute_regression_results(
      reg_fit, weights=df$w, se_group=df$se_group)
    reg_vcov <- get_fit_covariance(reg_fit, se_group=df$se_group)
    assert_nearly_equal(reg_fit$coefficients, zam_reg_fit$betahat)
    assert_nearly_equal(reg_vcov, as.numeric(zam_reg_fit$se_mat))

    if (have_ivreg) {
      zam_iv_fit <- compute_iv_regression_results(
        iv_fit, weights=df$w, se_group=df$se_group)
      iv_vcov <- get_fit_covariance(iv_fit, se_group=df$se_group)
      assert_nearly_equal(iv_fit$coefficients, zam_iv_fit$betahat)
      assert_nearly_equal(iv_vcov, as.numeric(zam_iv_fit$se_mat))
    }
  }

  # Test that rerun works with left-out observations.  Generate a weight
  # vector with randomly left-out observations.
  w_bool <- rep(TRUE, num_obs)
  w_bool[sample(100, 10)] <- FALSE
  new_w <- df$w

  # Note that this test will fail if the weights are exactly zero,
  # since vcovCL is actually discontinuous when weights are set
  # to exactly zero.  To avoid this, make the weights very small instead.
  new_w[!w_bool] <- 1e-6

  # Make sure all the groups are still present
  stopifnot(length(unique(df$se_group[w_bool])) == length(unique(df$se_group)))

  # Re-run using OLS or IV, and grouped standard errors or not, and check
  # that our results match R.
  for (use_iv in c(TRUE, FALSE)) {
    if (use_iv && !have_ivreg) next
    for (use_se_group in c(TRUE, FALSE)) {
      if (use_se_group && !have_sandwich) next
      if (use_se_group) {
        se_group <- df$se_group
      } else {
        se_group <- NULL
      }
      if (use_iv) {
        new_fit <-
          ivreg(y ~ x1 + 1 | z1 + 1, data=df |>
            mutate(w=!!new_w), x=TRUE, y=TRUE, weights=w)
        zam_fit <- compute_iv_regression_results(iv_fit, new_w, se_group=se_group)
      } else {
        new_fit <-
          lm(y ~ x1 + 1, data=df |>
            mutate(w=!!new_w), x=TRUE, y=TRUE, weights=w)
        zam_fit <- compute_regression_results(reg_fit, new_w, se_group=se_group)
      }
      new_vcov <- get_fit_covariance(new_fit, se_group=se_group)

      assert_nearly_equal(new_fit$coefficients, zam_fit$betahat)
      assert_nearly_equal(new_vcov, as.numeric(zam_fit$se_mat))
    }
  }
})
