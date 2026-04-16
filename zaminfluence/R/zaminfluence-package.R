#' zaminfluence: Z-estimator approximate maximal influence
#'
#' Compute and analyze influence functions for Z-estimators (OLS, IV, and
#' logistic regression). See [compute_model_influence()] for the main entry
#' point and `inst/architecture.md` for the data-structure overview.
#'
#' @importFrom stats approx binomial coef coefficients family fitted glm.fit
#'   plogis qnorm rbinom rnorm runif setNames vcov
#' @keywords internal
"_PACKAGE"

# Column names referenced inside dplyr/ggplot2 NSE expressions; declared here
# so R CMD check doesn't flag them as undefined global variables.
utils::globalVariables(c("num_dropped", "param", "param_mzse", "param_pzse"))
