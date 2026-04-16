# Note on Two Ways to Differentiate Logit Standard Errors with Respect to Data Weights

This note clarifies a subtle point that came up while thinking about extending
`zaminfluence` to logistic regression.

The issue is this:

- There is a true weighted logit coefficient map `w -> beta(w)`.
- A quantity like a model-based standard error can be written as
  `SE(beta(w), w)`.
- For influence calculations, we only need the derivative at the baseline
  weights `w = 1`, not a globally correct formula for all `w`.

The main question is whether one may replace the true function `beta(w)` by its
first-order linearization and still get the correct derivative of the standard
error at `w = 1`.

The answer is yes.

## Setup

Let

```text
U(beta, w) = sum_i w_i x_i (y_i - Lambda(x_i' beta))
```

be the weighted logit score, where `Lambda(t) = exp(t) / (1 + exp(t))`.

Assume:

- `beta(w)` is defined in a neighborhood of `w = 1`,
- `beta(w)` is differentiable there,
- the weighted Hessian is nonsingular at `w = 1`.

Define the baseline coefficient

```text
beta_hat := beta(1).
```

Let `B` denote the Jacobian of `beta(w)` with respect to `w`, evaluated at
`w = 1`:

```text
B := d beta(w) / d w' |_{w=1}.
```

For logit, the implicit function theorem gives the columns of `B` as

```text
d beta / d w_i = H^{-1} x_i (y_i - p_i),
```

where

```text
p_i = Lambda(x_i' beta_hat),
H = sum_i x_i x_i' p_i (1 - p_i).
```

Up to sign conventions, this is the standard influence derivative.

## The True Function and the Linearized Surrogate

Let `g(beta, w)` denote any smooth scalar quantity built from the fitted logit
model. For the present discussion, `g` can be a coefficient standard error.

The true weight-dependent target is

```text
F(w) := g(beta(w), w).
```

Now define the linearized coefficient map

```text
beta_lin(w) := beta_hat + B (w - 1),
```

and the corresponding surrogate target

```text
F_lin(w) := g(beta_lin(w), w).
```

This surrogate is not globally equal to `F(w)` unless `beta(w)` itself is
affine in `w`, which it is not for logit.

So if the question is whether `F_lin(w)` is the true weighted standard-error
function, the answer is no.

## Why the Derivatives Agree at the Baseline

The key point is that `beta_lin(w)` matches `beta(w)` to first order at
`w = 1`:

```text
beta_lin(1) = beta_hat = beta(1),
d beta_lin / d w' |_{w=1} = B = d beta / d w' |_{w=1}.
```

Apply the chain rule to the true target:

```text
dF/dw' = (partial g / partial beta') (d beta / dw') + partial g / partial w'.
```

Evaluating at `w = 1` gives

```text
dF/dw' |_{w=1}
  = (partial g / partial beta' |_{(beta_hat, 1)}) B
    + partial g / partial w' |_{(beta_hat, 1)}.
```

Now apply the same chain rule to the surrogate:

```text
dF_lin/dw' = (partial g / partial beta') (d beta_lin / dw')
             + partial g / partial w'.
```

At `w = 1`, since `beta_lin(1) = beta(1)` and
`d beta_lin / dw' |_{w=1} = d beta / dw' |_{w=1}`, we obtain

```text
dF_lin/dw' |_{w=1} = dF/dw' |_{w=1}.
```

Therefore:

- `F_lin` is not the true function globally,
- but `F_lin` has the correct first derivative at the baseline.

This is exactly enough for first-order influence calculations.

## Interpretation for Implementation

There are two implementation strategies.

### 1. Exact local chain rule

Compute

```text
dF/dw' |_{w=1}
  = (partial g / partial beta' |_{(beta_hat, 1)}) B
    + partial g / partial w' |_{(beta_hat, 1)}.
```

For a standard error `g = SE`, this means:

- compute `B = d beta / dw'` from the implicit function theorem,
- compute `partial SE / partial beta`,
- compute `partial SE / partial w` holding `beta` fixed,
- combine the terms by the chain rule.

This is mathematically explicit and globally honest.

### 2. Linearized-in-graph surrogate

Build

```text
beta_lin(w) = beta_hat + B (w - 1)
```

inside the autodiff graph, define

```text
F_lin(w) = g(beta_lin(w), w),
```

and differentiate `F_lin` with respect to `w`.

This does not recover the true function away from `w = 1`, but it does recover
the correct derivative at `w = 1`.

So it is valid if the only goal is to compute first-order influence scores.

## What This Is Not

This is not an application of the envelope theorem.

The envelope theorem typically says that when differentiating an optimized value
function, the term involving the derivative of the optimizer drops out because
the first-order condition kills it.

That is not what happens here. For standard errors, the indirect path through
`beta(w)` generally does matter:

```text
(partial SE / partial beta') (d beta / dw').
```

The point here is different:

- we can replace `beta(w)` by any surrogate with the same value and the same
  first derivative at the base point,
- and the resulting composed function will have the same first derivative at
  that point.

This is a first-order Taylor / chain-rule argument, not an envelope result.

## Bottom Line

For first-order AMIP-style influence calculations:

- using the exact local chain rule is correct,
- using the linearized surrogate `beta_hat + B (w - 1)` is also correct for the
  derivative at `w = 1`,
- but only the first approach is globally exact as a description of the true
  weighted standard-error function.

So the two approaches differ in global honesty, not in the first derivative at
the expansion point.
