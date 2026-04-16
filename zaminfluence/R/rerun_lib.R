#' Rerun the model at the AMIS for a set of signals.
#' @param signals A list of signal objects, "sign", "sig", "both",
#' as produced by [get_inference_signals_for_parameter].
#' @param model_grads `r docs$model_grads`
#' @param rerun_fun (Optional) A function taking as inputs
#' a vector of weights, and returning a model_fit object.  If unspecified,
#' `model_grads$rerun_fun` is used.
#' @param verbose (Optional) If TRUE, print status updates.
#'
#' @return A nested list of reruns matching the structure of `signals`.
#' @export
rerun_for_signals <- function(signals, model_grads, rerun_fun=NULL, verbose=FALSE) {
    stopifnot(inherits(model_grads, "model_grads"))
    stopifnot(setequal(names(signals), names(model_grads$param_infls)))
    for (param_name in names(signals)) {
        for (signal in signals[[param_name]]) {
            stopifnot(inherits(signal, "qoi_signal"))
        }
    }

    if (is.null(rerun_fun)) {
        rerun_fun <- model_grads$rerun_fun
    }

    verbose_print <- function(...) {
        if (verbose) cat(..., sep="")
    }

    num_obs <- model_grads$model_fit$num_obs
    rerun_signal <- function(signal) {
      if (signal$apip$success) {
        verbose_print("Rerunning ", signal$description, ".\n")
        weights <- get_weight_vector(
            drop_inds=signal$apip$inds,
            orig_weights=model_grads$model_fit$weights)
        return(rerun_fun(weights))
      } else {
        verbose_print(
          "The linear approximation cannot reverse the signal  ",
          signal$description, "; skipping rerun.\n")
      }
    }
    reruns <- purrr::map_depth(signals, 2, rerun_signal)
    return(reruns)
}


#' Predict the model at the AMIS for a set of signals.
#' @param signals A list of signal objects, "sign", "sig", "both",
#' as produced by [get_inference_signals_for_parameter].
#' @param model_grads `r docs$model_grads`
#' @param verbose (Optional) If TRUE, print status updates.
#'
#' @return A nested list of predictions matching the structure of `signals`.
#' @export
predict_for_signals <- function(signals, model_grads, verbose=FALSE) {
  predict_fun <- function(weights) {
    predict_model_fit(model_grads, weights)
  }
  rerun_for_signals(signals, model_grads, verbose=verbose, rerun_fun=predict_fun)
}

