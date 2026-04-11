
StopIfNotNumericScalar <- function(x) {
  stopifnot(is.numeric(x))
  stopifnot(length(x) == 1)
}


GenerateRandomEffects <- function(num_obs, num_groups=NULL) {
  if (!is.null(num_groups)) {
    # Add random effects.  se_group must be zero-indexed.
    se_group <- floor(num_groups * runif(num_obs))
    se_group[se_group == num_groups] <- 0  # Better safe than sorry

    re <- rnorm(num_groups)[se_group + 1]
    return(data.frame(se_group=se_group, re=re))
  } else {
    return(data.frame(re=rep(0, num_obs)))
  }
}


GenerateRegressionData <- function(num_obs, param_true, x=NULL, num_groups=NULL) {
  x_dim <- length(param_true)
  if (is.null(x)) {
    x <- matrix(runif(num_obs * x_dim), num_obs, x_dim)
    x <- x - rep(colMeans(x), each=num_obs)
  } else {
    if (!(nrow(x) == num_obs)) {
      stop("Wrong number of x rows.")
    }
  }
  eps <- rnorm(num_obs)
  re_df <- GenerateRandomEffects(num_obs, num_groups)
  y <- x %*% param_true + eps + re_df$re
  df <- data.frame(x)
  names(df)  <- paste0("x", 1:x_dim)
  df$y <- y
  df$eps <- eps
  df$re <- re_df$re
  if (!is.null(num_groups)) {
    df$se_group <- re_df$se_group
  }
  return(df)
}


GenerateLogitData <- function(num_obs, param_true, x=NULL) {
  x_dim <- length(param_true)
  if (is.null(x)) {
    x <- matrix(rnorm(num_obs * x_dim), num_obs, x_dim)
    x <- x - rep(colMeans(x), each=num_obs)
  }
  p <- plogis(x %*% param_true)
  y <- rbinom(num_obs, 1, p)
  df <- data.frame(x)
  names(df) <- paste0("x", 1:x_dim)
  df$y <- y
  return(df)
}


GenerateIVRegressionData <- function(num_obs, param_true, num_groups=NULL) {
  # Simulate some IV data

  x_dim <- length(param_true)
  x <- rnorm(num_obs * x_dim) |> matrix(nrow=num_obs)
  x_rot <- diag(x_dim) + rep(0.2, x_dim ^ 2) |> matrix(nrow=x_dim)
  x <- x %*% x_rot
  x <- x - rep(colMeans(x), each=num_obs)

  z <- rnorm(num_obs * x_dim) |> matrix(nrow=num_obs)
  z_rot <- diag(x_dim) + rep(0.2, x_dim ^ 2) |> matrix(nrow=x_dim)
  z <- z %*% z_rot + x
  z <- z - rep(colMeans(z), each=num_obs)

  Project <- function(z, vec) {
      num_obs <- nrow(z)
      ztz <- t(z) %*% z / num_obs
      ztv <- t(z) %*% vec / num_obs
      return(z %*% solve(ztz, ztv))
  }

  ProjectPerp <- function(z, vec) {
      return(vec - Project(z, vec))
  }

  re_df <- GenerateRandomEffects(num_obs, num_groups)

  sigma_true <- 2.0
  eps_base <- rnorm(num_obs) + rowSums(x) + re_df$re
  eps_true <- ProjectPerp(z, eps_base)
  y <- x %*% param_true + eps_true


  x_df <- data.frame(x)
  x_names <- sprintf("x%d", 1:x_dim)
  names(x_df) <- x_names

  z_df <- data.frame(z)
  z_names <- sprintf("z%d", 1:x_dim)
  names(z_df) <- z_names

  df <- dplyr::bind_cols(x_df, z_df)
  df$y <- as.vector(y)

  if (!is.null(num_groups)) {
    df$se_group <- re_df$se_group
  }
  return(df)
}
