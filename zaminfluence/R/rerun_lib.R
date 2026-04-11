#' Rerun the model at the AMIS for a set of signals.
#' @param signals A list of signal objects, "sign", "sig", "both",
#' as produced by [GetInferenceSignalsForParameter].
#' @param model_grads `r docs$model_grads`
#' @param RerunFun (Optional) A function taking as inputs
#' a vector of weights, and returning a ModelFit object.  If unspecified,
#' `model_grads$RerunFun` is used.
#' @param verbose (Optional) If TRUE, print status updates.
#'
#' @return A nested list of reruns matching the structure of `signals`.
#' @export
RerunForSignals <- function(signals, model_grads, RerunFun=NULL, verbose=FALSE) {
    stopifnot(inherits(model_grads, "ModelGrads"))
    stopifnot(setequal(names(signals), names(model_grads$param_infls)))
    for (param_name in names(signals)) {
        for (signal in signals[[param_name]]) {
            stopifnot(inherits(signal, "QOISignal"))
        }
    }

    if (is.null(RerunFun)) {
        RerunFun <- model_grads$RerunFun
    }

    verbosePrint <- function(...) {
        if (verbose) cat(..., sep="")
    }

    num_obs <- model_grads$model_fit$num_obs
    RerunSignal <- function(signal) {
      if (signal$apip$success) {
        verbosePrint("Rerunning ", signal$description, ".\n")
        weights <- GetWeightVector(
            drop_inds=signal$apip$inds,
            orig_weights=model_grads$model_fit$weights)
        return(RerunFun(weights))
      } else {
        verbosePrint(
          "The linear approximation cannot reverse the signal  ",
          signal$description, "; skipping rerun.\n")
      }
    }
    reruns <- purrr::map_depth(signals, 2, RerunSignal)
    return(reruns)
}


#' Predict the model at the AMIS for a set of signals.
#' @param signals A list of signal objects, "sign", "sig", "both",
#' as produced by [GetInferenceSignalsForParameter].
#' @param model_grads `r docs$model_grads`
#' @param verbose (Optional) If TRUE, print status updates.
#'
#' @return A nested list of predictions matching the structure of `signals`.
#' @export
PredictForSignals <- function(signals, model_grads, verbose=FALSE) {
  PredictFun <- function(weights) {
    PredictModelFit(model_grads, weights)
  }
  RerunForSignals(signals, model_grads, verbose=verbose, RerunFun=PredictFun)
}

