# Extending zaminfluence to New Models

This guide explains how to add a new model type to zaminfluence, using the
logistic regression implementation as a worked example.

## Architecture

zaminfluence has a clean separation between model-specific and model-agnostic
code. Everything above the `model_grads` layer is generic:

- `model_fit` / `model_grads` (model_grads_lib.R) -- data structures
- `append_target_regressor_influence` (inference_targets_lib.R) -- QOI sorting
- `get_inference_signals` (inference_targets_lib.R) -- APIP computation
- `rerun_for_signals` / `predict_for_signals` (rerun_lib.R) -- validation
- Plotting and reporting (reporting_lib.R)

To add a new model, you only need to produce a `model_grads` object. The rest
of the pipeline works automatically.

## The model_grads Contract

`model_grads()` requires four arguments:

1. **model_fit**: A `model_fit` object with fields: `fit_object`, `num_obs`,
   `param` (coefficient vector), `se` (standard error vector),
   `parameter_names`, `weights`, `se_group`.

2. **param_grad**: Matrix `[k x n]` where `k` = number of kept parameters and
   `n` = number of observations. Entry `[j, i]` = `d(param_j)/d(w_i)`.
   Rownames must be set to parameter names.

3. **se_grad**: Matrix `[k x n]`, same layout. Entry `[j, i]` =
   `d(se_j)/d(w_i)`. Rownames must match `param_grad`.

4. **rerun_fun**: A function `rerun_fun(weights)` that refits the model at new
   weights and returns a `model_fit`.

## What to Build

A new model backend needs five components:

### 1. Variable extraction
Extract `x`, `y`, `betahat`, `w0`, `parameter_names`, `num_obs` from the fit
object. Validate inputs (correct family, required components present, etc).
See: `get_regression_variables()`, `get_logit_variables()`.

### 2. Diagnostics (optional but recommended)
Check convergence, condition numbers, etc. For logit, this means checking for
separation. See: `check_logit_diagnostics()`.

### 3. Gradient computation
Compute `param_grad` and `se_grad`. This is the core technical work.
See: `get_iv_regression_se_derivs_torch()`, `get_logit_se_derivs_torch()`.

### 4. Refit function
A function that takes a weight vector, refits the model, and returns
coefficients and SEs. See: `compute_logit_results()`.

### 5. Entry point
Assemble everything into a `model_grads` object, and wire into
`compute_model_influence()` dispatch. See: `compute_logit_influence()`.

## Gradient Strategies

### Closed-form autograd (OLS/IV)

When `betahat(w)` has a closed-form expression in `w`, you can put the entire
computation -- coefficients AND standard errors -- into a single torch
computation graph and let autograd differentiate everything. This is what
`get_iv_regression_se_derivs_torch()` does.

### IFT + chain rule (logit and other MLEs)

When the estimator is defined implicitly (e.g. as the solution to score
equations), `betahat(w)` has no closed-form in `w`. You cannot put it into a
torch graph. Instead:

**param_grad via the Implicit Function Theorem (IFT):**
The score equations `sum_n w_n * s_n(beta) = 0` implicitly define beta(w).
Differentiating: `d(beta)/d(w_n) = H^{-1} s_n`, where `H` is the Hessian and
`s_n` is the per-observation score. This is computed in plain R (no autograd).

**se_grad via two-pass autograd + chain rule:**
`SE(w) = SE(w, beta(w))` depends on `w` both directly (through the Fisher
information formula) and indirectly (through `beta`). Build the SE formula in
torch with `w` and `beta` as two independent leaves, then:

```
d(SE)/d(w) = partial(SE)/partial(w) + partial(SE)/partial(beta) * d(beta)/d(w)
```

The two partial derivatives come from `autograd_grad`; `d(beta)/d(w)` comes
from the IFT step above. See `get_logit_se_derivs_torch()`.

**The indirect-path trap:** If you only differentiate `SE(w, beta_fixed)` with
respect to `w` (treating `beta` as constant), you miss the indirect effect of
weight changes on SE through the changing coefficient. This gives wrong
gradients. You must include both paths.

## Separation and Convergence (Logit-Specific)

Separation is the main failure mode for logistic regression. zaminfluence
handles it at three levels:

1. **Original fit** (`check_logit_diagnostics`): hard stop on non-convergence or
   near-singular Hessian; warning on near-separation.
2. **Refit** (`compute_logit_results`): warning on non-convergence; NA standard
   errors if Hessian is singular.
3. **Validation**: Always run `rerun_for_signals()` to verify that the linear
   approximation is accurate at the identified influential set.

## Testing Checklist

1. **Base values**: Verify that `model_grads$model_fit$param` and `$se` match
   the output of the original fitting function (e.g. `coef()`, `vcov()`).

2. **Numerical derivatives**: Use `numDeriv::jacobian()` on `rerun_fun` to get
   numerical `param_grad` and `se_grad`. Compare against analytical gradients.
   Test multiple configurations (with/without weights, different numbers of
   parameters, subsets via `keep_pars`).

3. **End-to-end pipeline**: Run the full pipeline through
   `compute_model_influence -> append_target_regressor_influence ->
   get_inference_signals -> rerun_for_signals`. Verify it completes without error.

4. **Input validation**: Verify that unsupported inputs (wrong family, missing
   components, etc.) produce clear error messages.
