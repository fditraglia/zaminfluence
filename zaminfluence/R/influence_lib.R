
# Define a qoi_influence S3 class

new_qoi_influence <- function(
    name,
    infl, base_value, num_obs,
    ordered_inds_neg, infl_cumsum_neg,
    ordered_inds_pos, infl_cumsum_pos) {

    return(structure(
      list(
        name=name,
        neg=list(infl_inds=ordered_inds_neg,
                 infl_cumsum=infl_cumsum_neg,
                 num_obs=num_obs),
        pos=list(infl_inds=ordered_inds_pos,
                 infl_cumsum=infl_cumsum_pos,
                 num_obs=num_obs),
        base_value=base_value,
        infl=infl  # In the original order
      ),
      class="qoi_influence"))
}


validate_qoi_influence <- function(qoi) {
    stopifnot(inherits(qoi, "qoi_influence"))
    check_sorted_influence <- function(signed_infl, sign) {
      stopifnot(all(signed_infl$infl_cumsum * sign > 0))
      stopifnot(length(signed_infl$infl_inds) ==
                length(signed_infl$infl_cumsum))
      # Check that the sorted influence scores are consistent with the
      # cumulative sum: infl_cumsum[k] == sum(infl[infl_inds[1:k]]).
      sorted_infl <- qoi$infl[signed_infl$infl_inds]
      stopifnot(all(cumsum(sorted_infl) == signed_infl$infl_cumsum))
      # Check that the influence scores are sorted in the expected direction
      # (most-extreme first, so diffs move toward zero = opposite of `sign`).
      stopifnot(all(diff(sorted_infl * sign) <= 0))
    }
    check_sorted_influence(qoi$pos, 1)
    check_sorted_influence(qoi$neg, -1)
    stopifnot(qoi$neg$num_obs == qoi$pos$num_obs)
}


#' Process a vector of influence scores to produce sorted influence scores.
#' @param infl A vector of influence scores for a quantity of interest,
#' in the same order as the original data.
#' @param base_value The value of the quantity of interest at the original fit.
#'
#' @return See "Quantity of Interest" in README.md
#' @export
qoi_influence <- function(infl, base_value, name, num_obs=NULL) {
    if (is.null(num_obs)) {
        num_obs <- length(infl)
    }
    infl_pos <- infl > 0
    infl_neg <- infl < 0

    inds_pos <- (1:length(infl))[infl_pos]
    inds_neg <- (1:length(infl))[infl_neg]

    ordered_inds_pos <- inds_pos[order(-1 * infl[infl_pos])]
    ordered_inds_neg <- inds_neg[order(infl[infl_neg])]

    infl_pos <- infl[ordered_inds_pos]
    infl_cumsum_pos <- cumsum(infl_pos)

    infl_neg <- infl[ordered_inds_neg]
    infl_cumsum_neg <- cumsum(infl_neg)

    return(new_qoi_influence(
      name=name,
      infl=infl, base_value=base_value, num_obs=num_obs,
      ordered_inds_neg=ordered_inds_neg, infl_cumsum_neg=infl_cumsum_neg,
      ordered_inds_pos=ordered_inds_pos, infl_cumsum_pos=infl_cumsum_pos))
}


# Define an apip S3 class

new_apip <- function(n, prop, inds, success) {
  return(structure(
    list(n=n, prop=prop, inds=as.integer(inds), success=as.logical(success)),
    class="apip"))
}


validate_apip <- function(apip) {
  stopifnot(inherits(apip, "apip"))
  stop_if_not_numeric_scalar(apip$n)
  stop_if_not_numeric_scalar(apip$prop)
  if (any(is.na(apip$inds))) {
    stopifnot(length(apip$inds) == 1)
    stopifnot(!apip$success)
  } else {
    stopifnot(all(apip$inds > 0))
    stopifnot(apip$success)
  }
  return(invisible(apip))
}


make_apip <- function(n_drop, num_obs, inds_drop) {
  if (any(is.na(inds_drop))) {
    success <- FALSE
  } else {
    success <- TRUE
  }
  return(validate_apip(new_apip(
    n=n_drop,
    prop=n_drop / num_obs,
    inds=inds_drop,
    success=success
  )))
}


#' Compute the approximate perturbation-inducing proportion (APIP).
#' @param qoi ``r docs$qoi``
#' @param signal The desired difference.
#'
#' @return A list containing
#' `n`: The number of points to drop
#' `prop`: The proportion of points to drop
#' `inds`: `r docs$drop_inds`
#' @export
get_apip_for_qoi <- function(qoi, signal) {
    stopifnot(inherits(qoi, "qoi_influence"))
    stopifnot(is.numeric(signal))
    stopifnot(length(signal) == 1)

    qoi_sign <- if (signal < 0) qoi$pos else qoi$neg
    num_obs <- qoi_sign$num_obs
    # To produce a negative change, drop observations with positive influence
    # scores, and vice-versa.
    if (signal == 0) {
      return(make_apip(n_drop=0, num_obs=num_obs, inds_drop=c()))
    }
    n_vec <- 1:length(qoi_sign$infl_cumsum)
    # TODO: do this more efficiently using your own routine, since
    # we know that infl_cumsum is increasing?
    n_drop <- approx(x=-1 * c(0, qoi_sign$infl_cumsum),
                     y=c(0, n_vec),
                     xout=signal)$y |> ceiling()
    if (is.na(n_drop)) {
        drop_inds <- NA
    } else if (n_drop == 0) {
        drop_inds <- c()
    } else {
        drop_inds <- qoi_sign$infl_inds[1:n_drop]
    }
    return(make_apip(n_drop=n_drop, num_obs=num_obs, inds_drop=drop_inds))
}


#' Compute a weight vector for a set of dropped indices.
#'
#' @param drop_inds ``r docs$drop_inds``
#' @param num_obs The number of observations in the original data.
#' @param bool (Optional)  If true, return a boolean vector.  Otherwise,
#' return a numeric vector (with ones and zeros).
#' @param invert (Optional) If TRUE, return a vector that retains the
#' observations in `drop_inds`.  Default is FALSE.
#'
#' @return A vector of weights in the order of the original data.
#' @export
get_weight_vector <- function(drop_inds, num_obs=NULL,
                            orig_weights=NULL, bool=FALSE, invert=FALSE) {
  if (is.null(num_obs)) {
    if (is.null(orig_weights)) {
      stop("Either `num_obs` or `orig_weights` must be specified")
    }
    num_obs <- length(orig_weights)
  } else {
    if (is.null(orig_weights)) {
      orig_weights <- rep(1, num_obs)
    } else {
      stopifnot(num_obs == length(orig_weights))
    }
  }

  if (any(is.na(drop_inds))) {
    stop("Non-numeric drop_inds specfied.")
  }

  if (length(drop_inds) > 0) {
    if (max(drop_inds) > num_obs) {
      stop(sprintf(paste0(
        "The maximum index to drop must be no greater than `num_obs1.  ",
        "max(drop_inds) = %d > %d = num_obs", max(drop_inds, num_obs))))
    }
    if (min(drop_inds) < 1) {
      stop("All drop_inds must be positive.")
    }
  }

  if (bool) {
    w <- orig_weights != 0
    w[drop_inds] <- FALSE
    if (invert) {
      return(!w)
    } else {
      return(w)
    }
  } else { # Integers, not boolean weights
    if (invert) {
      w <- rep(0, num_obs)
      w[drop_inds] <- orig_weights[drop_inds]
    } else {
      w <- orig_weights
      w[drop_inds] <- 0
    }
    return(w)
  }
}


#' Compute the approximate maximally-influential set (AMIS).
#' @param qoi ``r docs$qoi``
#' @param n_drop The number of points to drop (we will round up).
#'
#' @return `r docs$drop_inds`
#' @export
get_amis <- function(qoi, sign, n_drop) {
  stopifnot(inherits(qoi, "qoi_influence"))
  if (!(sign %in% c("pos", "neg"))) {
    stop("Sign must be either `pos` or `neg`.")
  }
  if (n_drop < 0) {
    stop("`n_drop` must be non-negative.")
  }
  n_drop <- ceiling(n_drop)
  n_scores <- length(qoi[[sign]]$infl_inds)
  if (n_drop > n_scores) {
    warning(sprintf(paste0(
      "More dropped observations were requested than influence scores",
      "present (%d > %d).  Returning all influence scores ",
      "of the specified sign."), n_drop, n_scores))
      return(qoi[[sign]]$infl_inds)
  }
  if (n_drop > 0) {
    return(qoi[[sign]]$infl_inds[1:n_drop])
  } else {
    return(c())
  }
}


#' Compute the approximate maximum influence perturbation (AMIP).
#' @param qoi ``r docs$qoi``
#' @param n_drop The number of points to drop (we will round up).
#'
#' @return The approximate largest change that can be produced by dropping
#' the specified number of points.
#' @export
get_amip <- function(qoi, sign, n_drop) {
  stopifnot(inherits(qoi, "qoi_influence"))
  if (n_drop == 0) {
    return(0)
  }
  amis <- get_amis(qoi, sign, n_drop)
  return(predict_change(qoi, amis))
}

#' Predict the effect of dropping points.
#' @param qoi ``r docs$qoi``
#' @param drop_inds ``r docs$drop_inds``
#'
#' @return A linear approximation to the effect of dropping the specified
#' observations.
#'@export
predict_change <- function(qoi, drop_inds) {
    stopifnot(inherits(qoi, "qoi_influence"))
    return(-1 * sum(qoi$infl[drop_inds]))
}
