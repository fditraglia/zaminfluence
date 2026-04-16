# Packages needed by tests but not by the package itself.
# dplyr is a hard package Import (always available). ivreg is a Suggests-only
# dep: load it opportunistically here so bare `ivreg()` calls in tests resolve,
# but individual IV tests must still call skip_if_not_installed("ivreg") so
# the suite remains runnable when ivreg is absent.
library(dplyr)
if (requireNamespace("ivreg", quietly=TRUE)) {
  library(ivreg)
}

assert_nearly_equal <- function(x, y, tol=1e-9, desc=NULL) {
  diff_norm <- max(abs(x - y))
  if (is.null(desc)) {
    info_str <- sprintf("%e > %e", diff_norm, tol)
  } else {
    info_str <- sprintf("%s: %e > %e", desc, diff_norm, tol)
  }
  testthat::expect_true(diff_norm < tol, info=info_str)
}


assert_nearly_zero <- function(x, tol=1e-15, desc=NULL) {
  x_norm <- max(abs(x))
  if (is.null(desc)) {
    info_str <- sprintf("%e > %e", x_norm, tol)
  } else {
    info_str <- sprintf("%s: %e > %e", desc, x_norm, tol)
  }
  testthat::expect_true(x_norm < tol, info=info_str)
}


# Compute the sandwich covariance, allowing se_group to be null.
get_fit_covariance <- function(fit, se_group=NULL) {
  if (is.null(se_group)) {
    return(vcov(fit))
  } else {
    return(sandwich::vcovCL(fit, cluster=se_group, type="HC0", cadjust=FALSE))
  }
}
