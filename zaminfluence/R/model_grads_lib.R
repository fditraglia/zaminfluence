
new_model_fit <- function(
  fit_object, num_obs, parameter_names, param, se, weights, se_group) {
  return(structure(
    list(fit_object=fit_object,
         num_obs=num_obs,
         parameter_names=as.character(parameter_names),
         param=param,
         se=se,
         weights=weights,
         parameter_dim=length(param),
         se_group=se_group),
    class="model_fit"
    ))
}


validate_model_fit <- function(model_fit) {
  stopifnot(inherits(model_fit, "model_fit"))
  stop_if_not_numeric_scalar(model_fit$num_obs)
  stop_if_not_numeric_scalar(model_fit$parameter_dim)

  num_obs <- model_fit$num_obs
  stopifnot(length(model_fit$weights) == num_obs)
  if (!is.null(model_fit$se_group)) {
    stopifnot(length(model_fit$se_group) == num_obs)
  }

  parameter_dim <- model_fit$parameter_dim
  stopifnot(length(model_fit$parameter_names) == parameter_dim)
  stopifnot(length(model_fit$param) == parameter_dim)
  stopifnot(length(model_fit$se) == parameter_dim)
  return(invisible(model_fit))
}



#' Construct a model_fit S3 object.
#'
#' A `model_fit` bundles the outputs of a single model fit in a form that the
#' rest of `zaminfluence` can consume. Instances are normally produced by
#' [compute_model_influence()] and its dispatchers; call this constructor
#' directly only when wiring up a new model backend.
#'
#' @param fit_object The underlying fit object (e.g. the return value of
#'   [lm()], [ivreg::ivreg()], or [glm()]).
#' @param num_obs Integer. The number of observations used in the fit.
#' @param param Numeric vector of point estimates.
#' @param se Numeric vector of standard errors, one per entry of `param`.
#' @param parameter_names Character vector of parameter names. If `NULL`,
#'   defaults to `theta1`, `theta2`, ....
#' @param weights Numeric vector of length `num_obs`. If `NULL`, defaults
#'   to all 1s.
#' @param se_group Optional grouping vector of length `num_obs` used for
#'   grouped (clustered) standard errors.
#'
#' @return A validated `model_fit` object.
#'
#' @export
model_fit <- function(fit_object, num_obs, param, se,
                     parameter_names=NULL, weights=NULL, se_group=NULL) {
    if (is.null(weights)) {
        weights <- rep(1.0, num_obs)
    }
    if (is.null(parameter_names)) {
        parameter_names <- sprintf("theta%d", 1:length(param))
    }
    return(validate_model_fit(new_model_fit(
      fit_object=fit_object,
      num_obs=num_obs,
      parameter_names=parameter_names,
      param=param,
      se=se,
      weights=weights,
      se_group=se_group
    )))
}


# Define S3 class for model_grads

new_model_grads <- function(
    model_fit,
    parameter_names,
    param_grad,
    se_grad,
    param_infls,
    rerun_fun) {
  return(structure(
    list(model_fit=model_fit,

         parameter_names=parameter_names,
         param_grad=param_grad,
         se_grad=se_grad,

         param_infls=param_infls,

         rerun_fun=rerun_fun),
    class="model_grads"
  ))
}


validate_model_grads <- function(model_grads) {
  stopifnot(inherits(model_grads, "model_grads"))
  validate_model_fit(model_grads$model_fit)
  model_fit <- model_grads$model_fit

  grad_pars <- model_grads$parameter_names
  stopifnot(all(grad_pars %in% model_fit$parameter_names))

  CheckGradDim <- function(grad_mat) {
    stopifnot(length(dim(grad_mat)) == 2)
    stopifnot(ncol(grad_mat) == model_fit$num_obs)
    stopifnot(nrow(grad_mat) == length(grad_pars))
  }

  CheckGradDim(model_grads$param_grad)
  CheckGradDim(model_grads$se_grad)

  stopifnot(is.list(model_grads$param_infls))
  stopifnot(all(names(model_grads$param_infls) %in% grad_pars))
  for (param_infl in model_grads$param_infls) {
    stopifnot(inherits(param_infl, "parameter_inference_influence"))
  }

  return(invisible(model_grads))
}


#' Predict a refit using the linear approximation in `model_grads`.
#'
#' Uses the parameter and SE gradients stored in `model_grads` to approximate
#' what the fit would look like at a new weight vector, without actually
#' refitting the model.
#'
#' @param model_grads `r docs$model_grads`
#' @param weights Numeric vector of new weights of length
#'   `model_grads$model_fit$num_obs`.
#'
#' @return A `model_fit` object containing the predicted `param` and `se`.
#'
#' @export
predict_model_fit <- function(model_grads, weights) {
    stopifnot(inherits(model_grads, "model_grads"))
    stopifnot(is.numeric(weights))

    model_fit <- model_grads$model_fit
    stopifnot(length(weights) == model_fit$num_obs)

    weight_diff <- weights - model_fit$weights
    kept_indices <- get_parameter_index(model_fit, model_grads$parameter_names)
    param_pred <- model_fit$param[kept_indices] + model_grads$param_grad %*% weight_diff
    se_pred <- model_fit$se[kept_indices] + model_grads$se_grad %*% weight_diff
    pred_fit <-
        model_fit(
            fit_object="prediction",
            num_obs=model_grads$model_fit$num_obs,
            param=param_pred,
            se=se_pred,
            parameter_names=model_grads$parameter_names,
            weights=weights,
            se_group=model_fit$se_group)
    return(pred_fit)
}



#' Construct a model_grads S3 object.
#'
#' A `model_grads` packages a fitted model together with the gradients of its
#' parameters and standard errors with respect to the observation weights.
#' Instances are normally produced by [compute_model_influence()]; call this
#' constructor directly only when wiring up a new model backend.
#'
#' @param model_fit A `model_fit` object at the original weights.
#' @param param_grad Numeric matrix of parameter gradients.
#'   Dimensions are `k x num_obs`, where `k` is the number of kept parameters
#'   and `num_obs` is the number of observations. Rownames must be the kept
#'   parameter names (a subset of `model_fit$parameter_names`).
#' @param se_grad Numeric matrix of standard-error gradients, same shape as
#'   `param_grad`. Rownames must match `param_grad`.
#' @param rerun_fun Function taking a weight vector and returning a
#'   `model_fit` at those weights.
#'
#' @return A validated `model_grads` object.
#'
#' @export
model_grads <- function(
    model_fit,
    param_grad,
    se_grad,
    rerun_fun) {

  parameter_names <- rownames(param_grad)
  if (any(rownames(se_grad) != parameter_names)) {
    stop(paste0(
      "The rownames of se_grad and param_grad must match.",
      "rownames(param_grad) = (",
      paste(rownames(param_grad), collapse=","), ")\n",
      "rownames(se_grad) = (",
      paste(rownames(se_grad), collapse=","), ")\n",
    ))
  }
  return(validate_model_grads(new_model_grads(
      model_fit=model_fit,
      parameter_names=parameter_names,
      param_grad=param_grad,
      se_grad=se_grad,
      rerun_fun=rerun_fun,
      param_infls=list())))
}



#' Look up the positional indices of named parameters.
#'
#' @param x A `model_fit` or `model_grads` object.
#' @param par_names Character vector of parameter names to look up.
#'
#' @return A named integer vector giving the index of each requested
#'   parameter in `x$parameter_names`.
#'
#' @export
get_parameter_index <- function(x, par_names) {
  UseMethod("get_parameter_index")
}


#' @rdname get_parameter_index
#' @export
get_parameter_index.model_grads <- function(x, par_names) {
  return(get_parameter_index_local(
    x$parameter_names, par_names, object_class="model_grads"))
}


#' @rdname get_parameter_index
#' @export
get_parameter_index.model_fit <- function(x, par_names) {
  return(get_parameter_index_local(
    x$parameter_names, par_names, object_class="model_fit"))
}


get_parameter_index_local <- function(all_par_names, par_names, object_class) {
  missing_names <- setdiff(par_names, all_par_names)
  if (length(missing_names) > 0) {
    stop(paste0(
      "Parameter names ",
      paste(missing_names, collapse=", "), " not found in ",
      object_class, "."))
  }
  target_indices <- setNames(1:length(all_par_names), all_par_names)[par_names]
  return(target_indices)
}
