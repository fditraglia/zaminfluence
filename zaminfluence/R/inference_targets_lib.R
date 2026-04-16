
# Define an parameter_inference_influence S3 object.
new_parameter_inference_influence <- function(
    target_parameter, sig_num_ses,
    se_qoi, param_qoi, param_mzse_qoi, param_pzse_qoi) {
  return(structure(
    list(
        target_parameter=as.character(target_parameter),
        se=se_qoi,
        param=param_qoi,
        param_mzse=param_mzse_qoi,
        param_pzse=param_pzse_qoi,
        sig_num_ses=sig_num_ses,
        qoi_names=c("param", "param_mzse", "param_pzse", "se")),
    class="parameter_inference_influence"))
}



validate_parameter_inference_influence <- function(param_infl) {
  stopifnot(inherits(param_infl, "parameter_inference_influence"))
  stopifnot(setequal(
    param_infl$qoi_names,
    c("param", "param_mzse", "param_pzse", "se")))

  for (qoi_name in param_infl$qoi_names) {
    stopifnot(inherits(param_infl[[qoi_name]], "qoi_influence"))
  }

  sig_num_ses <- param_infl$sig_num_ses
  stopifnot(is.numeric(sig_num_ses))
  stopifnot(length(sig_num_ses) == 1)
  stopifnot(sig_num_ses >= 0)

  return(invisible(param_infl))
}


#' Compute the inference quantities of interest for a single parameter.
#'
#' Returns the four scalar quantities on which `zaminfluence` operates:
#' the point estimate `param`, its standard error `se`, and the two
#' confidence-interval endpoints `param_mzse` / `param_pzse`.
#'
#' @param model_fit `r docs$model_fit`
#' @param target_parameter Character name of a parameter in
#'   `model_fit$parameter_names`.
#' @param sig_num_ses `r docs$sig_num_ses`
#'
#' @return A list with entries `param`, `se`, `param_mzse`, `param_pzse`,
#'   and `target_parameter`.
#'
#' @export
get_parameter_inference_qois <- function(model_fit, target_parameter,
                                      sig_num_ses=qnorm(0.975)) {
  stopifnot(inherits(model_fit, "model_fit"))
  target_index <- get_parameter_index(model_fit, target_parameter)

  param <- model_fit$param[target_index]
  se <- model_fit$se[target_index]

  values <- get_inference_qois(param=param, se=se, sig_num_ses=sig_num_ses)
  values$target_parameter <- target_parameter
  return(values)
}


get_inference_qois <- function(param, se, sig_num_ses) {
  # Remove names so we can use unlist() and get expected names.
  param <- unname(param)
  se <- unname(se)
  sig_num_ses <- unname(sig_num_ses)
  return(list(
    param=param,
    se=se,
    param_mzse=param - sig_num_ses * se,
    param_pzse=param + sig_num_ses * se
  ))
}


parameter_inference_influence <- function(model_grads, target_parameter,
                                        sig_num_ses=qnorm(0.975)) {
    stopifnot(inherits(model_grads, "model_grads"))

    weights <- model_grads$model_fit$weights

    qoi_base_values <- get_parameter_inference_qois(
      model_grads$model_fit, target_parameter=target_parameter,
      sig_num_ses=sig_num_ses)

    # se_grad and param_grad are the gradients for a parameter along the path
    # taking a weight
    # from its current value to zero.  That way the "gradient" measures the
    # effect of removing a datapoint (taking its value from the current weight
    # to zero.) So we multiply the raw weight
    # derivatives by the actual base weights.
    target_index <- get_parameter_index(model_grads, target_parameter)
    se_grad <- weights * model_grads$se_grad[target_index,]
    param_grad <- weights * model_grads$param_grad[target_index, ]
    num_obs <- model_grads$model_fit$num_obs
    qoi_gradients <- get_inference_qois(
      param=param_grad,
      se=se_grad,
      sig_num_ses=sig_num_ses)

    param_infl <- new_parameter_inference_influence(
          target_parameter=target_parameter,
          sig_num_ses=sig_num_ses,
          se_qoi=qoi_influence(
              name="se",
              infl=qoi_gradients$se,
              base_value=qoi_base_values$se,
              num_obs=num_obs),
          param_qoi=qoi_influence(
              name="param",
              infl=qoi_gradients$param,
              base_value=qoi_base_values$param,
              num_obs=num_obs),
          param_mzse_qoi=qoi_influence(
              name="param_mzse",
              infl=qoi_gradients$param_mzse,
              base_value=qoi_base_values$param_mzse,
              num_obs=num_obs),
          param_pzse_qoi=qoi_influence(
              name="param_pzse",
              infl=qoi_gradients$param_pzse,
              base_value=qoi_base_values$param_pzse,
              num_obs=num_obs))

    validate_parameter_inference_influence(param_infl)

    return(param_infl)
}


#' Compute the influence scores for a particular parameter.
#' @param model_grads `r docs$model_grads`
#' @param target_parameter The string naming a regressor (must be an
#' entry in `model_grads$parameter_names`).
#' @param sig_num_ses `r docs$sig_num_ses`
#'
#' @return The original `model_grads`, with an entry
#' `model_grads$param_infls[[target_parameter]]` containing a
#' parameter influence object.
#'
#'@export
append_target_regressor_influence <- function(model_grads, target_parameter,
                                           sig_num_ses=qnorm(0.975)) {
    stopifnot(inherits(model_grads, "model_grads"))
    if (is.null(model_grads[["param_infls"]])) {
        model_grads$param_infls <- list()
    }

    param_infl <- parameter_inference_influence(
      model_grads, target_parameter, sig_num_ses=sig_num_ses)

    model_grads$param_infls[[target_parameter]] <- param_infl
    return(invisible(model_grads))
}


#' Extract the base values of each QOI from a parameter influence object.
#'
#' @param param_infl `r docs$param_infl`
#'
#' @return A named numeric vector with entries `param`, `se`, `param_mzse`,
#'   `param_pzse` giving the QOIs at the original fit.
#'
#' @export
get_base_values <- function(param_infl) {
  stopifnot(inherits(param_infl, "parameter_inference_influence"))
  return(purrr::map_dbl(param_infl[param_infl$qoi_names], ~ .$base_value))
}


# Define an qoi_signal S3 object.
new_qoi_signal <- function(qoi, signal, description, apip) {
  return(structure(
    list(qoi=qoi, signal=signal, description=description, apip=apip),
    class="qoi_signal"
  ))
}


validate_qoi_signal <- function(signal) {
  stopifnot(inherits(signal, "qoi_signal"))
  stopifnot(inherits(signal$qoi, "qoi_influence"))
  stopifnot(inherits(signal$apip, "apip"))
  stop_if_not_numeric_scalar(signal$signal)
  return(invisible(signal))
}


qoi_signal <- function(qoi, signal, description) {
  # Note that the qoi data is not copied.
  return(validate_qoi_signal(new_qoi_signal(
    qoi=qoi,
    signal=signal,
    description=description,
    apip=get_apip_for_qoi(qoi=qoi, signal=signal)
  )))
}


#' Compute the signals for changes to sign, significance, and both.
#' @param model_grads `r docs$model_grads`
#'
#' @return A list lists of of signals, one for each parameter in
#' named model_grads$param_infls.  See the output of
#' `get_inference_signals_for_parameter`.
#'
#' @export
get_inference_signals <- function(model_grads) {
  stopifnot(inherits(model_grads, "model_grads"))
  signals <- list()
  for (param_name in names(model_grads$param_infls)) {
    signals[[param_name]] <- get_inference_signals_for_parameter(
      model_grads$param_infls[[param_name]]
    )
  }
  return(signals)
}


#' Compute the signals for changes to sign, significance, and both.
#' @param param_infl `r docs$param_infl`
#'
#' @return A list of signals, named "sign", "sig", and "both".  Each
#' entry is a `qoi_signal` object.
#' @export
get_inference_signals_for_parameter <- function(param_infl) {
    stopifnot(inherits(param_infl, "parameter_inference_influence"))
    base_values <- get_base_values(param_infl)
    param <- base_values["param"]
    param_mzse <- base_values["param_mzse"]
    param_pzse <- base_values["param_pzse"]

    sign_label <- "sign"
    sig_label <- "significance"
    both_label <- "sign and significance"

    signals <- list()
    signals$sign <- qoi_signal(
      qoi=param_infl[["param"]],
      signal=-1 * param,
      description=sign_label)

    is_significant <- sign(param_mzse) == sign(param_pzse)
    if (is_significant) {
        if (param_mzse >= 0) { # then param_pzse > 0 too because significant
            signals$sig <- qoi_signal(
              qoi=param_infl[["param_mzse"]],
              signal=-1 * param_mzse,
              description=sig_label)
            signals$both  <- qoi_signal(
              qoi=param_infl[["param_pzse"]],
              signal=-1 * param_pzse,
              description=both_label)
        } else if (param_pzse < 0) { # then param_mzse < 0 too because significant
            signals$sig <- qoi_signal(
              qoi=param_infl[["param_pzse"]],
              signal=-1 * param_pzse,
              description=sig_label)
            signals$both <- qoi_signal(
                qoi=param_infl[["param_mzse"]],
                signal=-1 * param_mzse,
                description=both_label)
        } else {
            stop("Impossible for a significant result")
        }
    } else { # Not significant.  Choose to change the interval endpoint which
             # is closer.
        if (abs(param_mzse) >= abs(param_pzse)) {
            signals$sig <- qoi_signal(
              qoi=param_infl[["param_pzse"]],
              signal=-1 * param_pzse,
              description=sig_label)
        } else  {
            signals$sig <- qoi_signal(
              qoi=param_infl[["param_mzse"]],
              signal=-1 * param_mzse,
              description=sig_label)
        }

        # If positive, taking the upper CI limit to zero will change both
        # sign and make it significant.
        if (param >= 0) {
            signals$both <- qoi_signal(
                qoi=param_infl[["param_pzse"]],
                signal=-1 * param_pzse,
                description=both_label)
        } else {
            signals$both <- qoi_signal(
                qoi=param_infl[["param_mzse"]],
                signal=-1 * param_mzse,
                description=both_label)
        }
    }

    return(signals)
}


#' Produce a tidy dataframe summarizing a signal.
#' @param x `r docs$signal`
#' @param row.names Unused; accepted for `as.data.frame()` generic consistency.
#' @param optional Unused; accepted for `as.data.frame()` generic consistency.
#' @param ... Unused; accepted for `as.data.frame()` generic consistency.
#'
#' @export
as.data.frame.qoi_signal <- function(x, row.names=NULL, optional=FALSE, ...) {
  data.frame(
      qoi_name=x$qoi$name,
      description=x$description,
      signal=x$signal,
      num_removed=x$apip$n,
      prop_removed=x$apip$prop)
}
