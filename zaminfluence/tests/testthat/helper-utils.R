AssertNearlyEqual <- function(x, y, tol=1e-9, desc=NULL) {
  diff_norm <- max(abs(x - y))
  if (is.null(desc)) {
    info_str <- sprintf("%e > %e", diff_norm, tol)
  } else {
    info_str <- sprintf("%s: %e > %e", desc, diff_norm, tol)
  }
  testthat::expect_true(diff_norm < tol, info=info_str)
}


AssertNearlyZero <- function(x, tol=1e-15, desc=NULL) {
  x_norm <- max(abs(x))
  if (is.null(desc)) {
    info_str <- sprintf("%e > %e", x_norm, tol)
  } else {
    info_str <- sprintf("%s: %e > %e", desc, x_norm, tol)
  }
  testthat::expect_true(x_norm < tol, info=info_str)
}


# Compute the sandwich covariance, allowing se_group to be null.
GetFitCovariance <- function(fit, se_group=NULL) {
  if (is.null(se_group)) {
    return(vcov(fit))
  } else {
    return(sandwich::vcovCL(fit, cluster=se_group, type="HC0", cadjust=FALSE))
  }
}
