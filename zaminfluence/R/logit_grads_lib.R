######################################################
# Logistic regression influence functions
library(torch)


# Extract the relevant variables from the output of glm() with family=binomial
GetLogitVariables <- function(glm_res) {
  if (!(("x" %in% names(glm_res)) &
        ("y" %in% names(glm_res)))) {
    stop("You must run glm with the arguments x=TRUE and y=TRUE.")
  }

  fam <- family(glm_res)
  if (fam$family != "binomial" || fam$link != "logit") {
    stop(paste0(
      "Only binomial(logit) is supported. ",
      "Got family='", fam$family, "', link='", fam$link, "'."))
  }

  x <- glm_res$x
  y <- as.numeric(glm_res$y)
  if (!all(y %in% c(0, 1))) {
    stop("Only binary (0/1) responses are supported. Grouped-binomial (cbind) responses are not.")
  }

  num_obs <- nrow(x)
  betahat <- as.numeric(coef(glm_res))
  if (is.null(glm_res$prior.weights)) {
    w0 <- rep(1.0, num_obs)
  } else {
    w0 <- glm_res$prior.weights
  }
  parameter_names <- colnames(x)

  offset <- glm_res$offset
  if (is.null(offset)) {
    offset <- rep(0.0, num_obs)
  }

  return(list(x=x, y=y, num_obs=num_obs, w0=w0,
              betahat=betahat, parameter_names=parameter_names,
              offset=offset))
}


#' Check diagnostics for a logistic regression fit.
#'
#' @param glm_res The result of glm() with family=binomial.
#'
#' @return A list with fitted probabilities, Hessian, reciprocal condition
#'   number, and minimum of p and 1-p.
#'
#' @export
CheckLogitDiagnostics <- function(glm_res) {
  if (!("x" %in% names(glm_res))) {
    stop("You must run glm with the argument x=TRUE.")
  }
  if (!glm_res$converged) {
    stop("glm did not converge. Cannot compute influence functions.")
  }

  p_vec <- fitted(glm_res)
  x <- glm_res$x
  w0 <- if (is.null(glm_res$prior.weights)) rep(1.0, nrow(x)) else glm_res$prior.weights
  pq_vec <- as.vector(p_vec * (1 - p_vec))
  H <- crossprod(x * sqrt(pq_vec * w0))

  rcond_val <- rcond(H)
  if (rcond_val < 1e-10) {
    stop(sprintf(
      "Hessian is near-singular (rcond = %.2e). This may indicate separation.",
      rcond_val))
  }

  min_pq <- min(pmin(p_vec, 1 - p_vec))
  if (min_pq < 1e-4) {
    warning(sprintf(
      "Some fitted probabilities are near 0 or 1 (min(p, 1-p) = %.2e). This may indicate near-separation.",
      min_pq))
  }

  return(list(p=p_vec, H=H, rcond_val=rcond_val, min_pq=min_pq))
}


# Compute logit SE derivatives using IFT for param_grad and
# two-pass autograd for se_grad.
GetLogitSEDerivsTorch <- function(logit_vars, keep_inds=NULL, compute_derivs=TRUE) {

  keep_inds <- ValidateKeepInds(keep_inds, logit_vars$x)

  x <- logit_vars$x
  y <- logit_vars$y
  betahat <- logit_vars$betahat
  w0 <- logit_vars$w0
  offset <- logit_vars$offset
  num_obs <- logit_vars$num_obs
  num_cols <- ncol(x)

  # Compute base values: model-based SE from Fisher information
  # Linear predictor is eta = x %*% beta + offset
  eta <- as.vector(x %*% betahat + offset)
  p_vec <- plogis(eta)
  pq_vec <- p_vec * (1 - p_vec)
  H_mat <- crossprod(x * sqrt(pq_vec * w0))
  H_inv <- solve(H_mat)
  betahat_se <- sqrt(diag(H_inv))

  return_list <- list(
    betahat=betahat,
    betahat_se=betahat_se
  )

  if (compute_derivs) {
    # Step 1: param_grad via IFT (plain R)
    # dβ/dw_n = H^{-1} s_n where s_n = x_n (y_n - p_n)
    score_matrix <- t(x * as.vector(y - p_vec))  # [p x n]
    param_grad_full <- H_inv %*% score_matrix     # [p x n]

    # Step 2: SE torch graph with two independent leaves
    w_t <- torch_tensor(matrix(w0, ncol=1),
                        requires_grad=TRUE, dtype=torch_double())
    beta_t <- torch_tensor(matrix(betahat, ncol=1),
                           requires_grad=TRUE, dtype=torch_double())
    x_t <- torch_tensor(x, requires_grad=FALSE, dtype=torch_double())
    offset_t <- torch_tensor(matrix(offset, ncol=1),
                             requires_grad=FALSE, dtype=torch_double())

    # Linear predictor: eta = x %*% beta + offset
    eta_t <- torch_matmul(x_t, beta_t) + offset_t
    p_t <- torch_sigmoid(eta_t)                         # [n, 1]
    pq_t <- p_t * (1 - p_t)                            # [n, 1]
    x_weighted <- x_t * torch_sqrt(pq_t * w_t)         # [n, p]
    H_t <- torch_matmul(x_weighted$transpose(2, 1), x_weighted)  # [p, p]
    se_cov_t <- torch_inverse(H_t)
    SE_t <- torch_sqrt(torch_diag(se_cov_t))            # [p]

    # Step 3: Two-pass autograd + chain rule
    betahat_infl_mat <- param_grad_full[keep_inds, , drop=FALSE]
    se_infl_mat <- matrix(NA, nrow=length(keep_inds), ncol=num_obs)

    for (di in seq_along(keep_inds)) {
      d <- keep_inds[di]
      dSE_dw <- torch::autograd_grad(
        SE_t[d], w_t, retain_graph=TRUE)[[1]] |> as.numeric()
      dSE_dbeta <- torch::autograd_grad(
        SE_t[d], beta_t, retain_graph=TRUE)[[1]] |> as.numeric()
      se_infl_mat[di, ] <- dSE_dw + dSE_dbeta %*% param_grad_full
    }

    return_list$betahat_infl_mat <- betahat_infl_mat
    return_list$betahat_se_infl_mat <- se_infl_mat
  }

  return(return_list)
}


#' Refit a logistic regression at new weights.
#'
#' @param x The design matrix.
#' @param y The binary response vector.
#' @param weights The observation weights.
#' @param parameter_names The names of the parameters.
#' @param offset Optional offset vector (default: no offset).
#'
#' @return A list with betahat, se, parameter_names, and converged.
#'
#' @export
ComputeLogitResults <- function(x, y, weights, parameter_names, offset=NULL) {
  refit <- glm.fit(x=x, y=y, weights=weights, offset=offset, family=binomial())

  betahat <- as.numeric(refit$coefficients)
  converged <- refit$converged

  if (!converged) {
    warning("glm.fit did not converge during refit.")
  }

  p_vec <- as.vector(refit$fitted.values)
  pq_vec <- p_vec * (1 - p_vec)
  H_new <- crossprod(x * sqrt(pq_vec * weights))

  se <- tryCatch({
    sqrt(diag(solve(H_new)))
  }, error=function(e) {
    warning("Hessian is singular during refit. Returning NA standard errors.")
    rep(NA_real_, length(betahat))
  })

  return(list(betahat=betahat, se=se,
              parameter_names=parameter_names, converged=converged))
}


#' Compute all influence scores for a logistic regression.
#'
#' @param glm_res `r docs$glm_result`
#' @param se_group `r docs$se_group`
#' @param keep_pars `r docs$keep_pars`
#'
#' @return `r docs$grad_return`
#'
#' @export
ComputeLogitInfluence <- function(glm_res, se_group=NULL, keep_pars=NULL) {

  if (!is.null(se_group)) {
    stop("Clustered SEs for logit not yet implemented.")
  }

  logit_vars <- GetLogitVariables(glm_res)
  CheckLogitDiagnostics(glm_res)

  all_par_names <- logit_vars$parameter_names
  if (is.null(keep_pars)) {
    keep_pars <- all_par_names
  }
  keep_inds <- GetKeepInds(all_par_names, keep_pars)

  grad_list <- GetLogitSEDerivsTorch(
    logit_vars=logit_vars,
    keep_inds=keep_inds,
    compute_derivs=TRUE)

  # Capture variables for the rerun closure
  x <- logit_vars$x
  y <- logit_vars$y
  num_obs <- logit_vars$num_obs
  parameter_names <- logit_vars$parameter_names
  offset <- logit_vars$offset

  RerunFun <- function(weights) {
    ret_list <- ComputeLogitResults(x, y, weights, parameter_names, offset=offset)
    return(ModelFit(
      fit_object=ret_list,
      num_obs=num_obs,
      param=ret_list$betahat,
      se=ret_list$se,
      parameter_names=parameter_names,
      weights=weights,
      se_group=NULL))
  }

  model_fit <- ModelFit(
    fit_object=glm_res,
    num_obs=num_obs,
    parameter_names=parameter_names,
    param=logit_vars$betahat,
    se=grad_list$betahat_se,
    weights=logit_vars$w0,
    se_group=NULL)

  rownames(grad_list$betahat_infl_mat) <- keep_pars
  rownames(grad_list$betahat_se_infl_mat) <- keep_pars

  return(ModelGrads(model_fit=model_fit,
                    param_grad=grad_list$betahat_infl_mat,
                    se_grad=grad_list$betahat_se_infl_mat,
                    RerunFun=RerunFun))
}
