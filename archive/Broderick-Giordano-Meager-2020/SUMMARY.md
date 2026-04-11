# Broderick, Giordano, and Meager (2020): Dropping a Little Data

**Full citation**: Broderick, Tamara, Ryan Giordano, and Rachael Meager. "An Automatic Finite-Sample Robustness Metric: When Can Dropping a Little Data Make a Big Difference?" arXiv preprint arXiv:2011.14999.
**Type**: Methods + application

## Overview

This paper proposes the Approximate Maximum Influence Perturbation (AMIP), a fast, automatic metric that measures how much an empirical result can change when a small fraction of the data is dropped. Using a first-order Taylor expansion (the empirical influence function), the method avoids the combinatorial explosion of checking all possible subsets and reduces the problem to computing per-observation influence scores and sorting them. The key theoretical insight is a signal-to-noise decomposition: AMIP non-robustness arises when the strength of the empirical claim is small relative to the noise in the influence scores -- a condition that does not vanish with sample size, is not captured by standard errors, and is not due to misspecification. Applied to several high-profile economics papers, the authors find that some results can be reversed by removing less than 1% of the sample even when t-statistics are large.

## Results and Assumptions

### Core Definitions (Section 2)

- **Maximum Influence Perturbation (MIP)**: the largest change in a quantity of interest from dropping at most $100\alpha$% of data. Computing it exactly requires enumerating $\binom{N}{\lfloor \alpha N \rfloor}$ subsets -- infeasible.
- **AMIP**: approximates the MIP via a first-order Taylor expansion in data weights $\vec{w}$ around $\vec{w} = \vec{1}$. The influence score of observation $n$ is $\psi_n = \partial \phi(\hat\theta(\vec{w}), \vec{w}) / \partial w_n |_{\vec{w}=\vec{1}}$. The approximate most influential set is found by sorting the $\psi_n$ and dropping the $\lfloor \alpha N \rfloor$ most negative -- requiring only one model fit, $N$ fast derivative computations, and a sort.
- **Exact lower bound**: re-running the analysis once without the approximate most influential set provides a lower bound on the true MIP at no approximation cost.

**Core assumptions**: (1) The estimator $\hat\theta$ is a Z-estimator, i.e., solves $\sum_n G(\hat\theta, d_n) = 0$ with $G$ twice continuously differentiable; (2) the quantity of interest $\phi(\theta)$ is continuously differentiable. These cover OLS, IV, GMM, MLE, and variational Bayes.

### Signal-Noise-Shape Decomposition (Section 3)

The AMIP decomposes as $\hat\Psi_\alpha = \hat\sigma_\psi \cdot \hat{\mathscr{T}}_\alpha$, where the noise $\hat\sigma_\psi^2 = (1/N) \sum_n (N\psi_n)^2$ consistently estimates the variance of $\sqrt{N}\phi(\hat\theta)$, and the shape $\hat{\mathscr{T}}_\alpha$ depends on the distribution of influence scores. An analysis is AMIP non-robust iff:

$$\Delta / \hat\sigma_\psi \leq \hat{\mathscr{T}}_\alpha$$

where $\Delta$ is the signal (e.g., $|\hat\theta_p|$ for sign change). Key consequences:

- **AMIP sensitivity does not vanish as $N \to \infty$**: both noise and shape converge to nonzero constants, unlike standard errors which shrink at rate $1/\sqrt{N}$. (Section 3.2.2, point b)
- **Not driven by misspecification**: even in a correctly specified model with no outliers, sensitivity arises when signal-to-noise is low. (Section 3.2.2, point c)
- **Distinct from standard errors**: standard errors allow that $\phi$ may differ by $\Delta$ when $\Delta/\hat\sigma_\psi \leq 1.96/\sqrt{N}$; AMIP allows it when $\Delta/\hat\sigma_\psi \leq \hat{\mathscr{T}}_\alpha$. Since $\hat{\mathscr{T}}_\alpha$ converges to a nonzero constant, AMIP sensitivity is generically larger. (Section 3.2.2, point d)
- **Statistical non-significance is always AMIP-non-robust as $N \to \infty$**: the signal for a non-significant result shrinks with $N$ while the AMIP capacity does not. (Section 3.2.2, point e)
- **Outliers affect noise, not shape**: heavy tails actually reduce $\hat{\mathscr{T}}_\alpha$ but increase $\hat\sigma_\psi$. (Section 3.2.2, point f)

### OLS Special Case (Section 3.1)

For univariate OLS with $y_n = \theta_0 x_n + \varepsilon_n$: the influence score is $\psi_n = N^{-1} S_X^{-1} x_n \hat\varepsilon_n$, and the noise converges to $\sigma_\varepsilon / \sigma_x$ -- the ratio of residual to regressor standard deviation. Influential points have both a large residual and a large regressor value.

### Theorem 1: Approximation Accuracy (Section 3.3)

Under regularity conditions (Assumptions 3-4: bounded operator norms, Lipschitz derivatives), the approximation error is $O(\alpha)$ while the actual effect is $O(\sqrt\alpha)$. Since $\alpha \ll \sqrt\alpha$ for small $\alpha$, the linear approximation becomes relatively more accurate as the removal fraction shrinks. This is a finite-sample result; the constants may be loose in practice but are shown to be tight in rate (Appendix B constructs a matching lower bound).

## Simulations and Applications

### Simulation: OLS with Known DGP (Section 3.1)

DGP: $y_n = 0.5 x_n + \varepsilon_n$ with $x_n \sim N(0, \sigma_x^2)$, $\varepsilon_n \sim N(0, \sigma_\varepsilon^2)$, $N = 5{,}000$. Varying $\sigma_x$ and $\sigma_\varepsilon$ confirms that the signal-to-noise ratio drives robustness: datasets with high $\sigma_\varepsilon / \sigma_x$ are AMIP non-robust despite correct specification and large samples. The linear approximation is accurate for $\alpha < 2.5\%$ and breaks down for larger removal fractions.

### Oregon Medicaid Experiment (Finkelstein et al. 2012) (Section 4.1)

$N \approx 23{,}700$. For most health outcomes (ITT and LATE), the sign can be flipped by removing ~0.5% of data, and significance can be changed by removing as few as 10-20 observations (0.05%). Refitting validates the approximation. This demonstrates that precise inference (large t-statistics) does not imply AMIP robustness.

### Progresa Cash Transfers (Angelucci and De Giorgi 2009) (Section 4.2)

Direct effects on the poor are relatively robust (3-7% removal needed). Spillover effects on the non-poor are highly sensitive (3 observations, ~0.07%, can change significance). The original authors' outlier trimming did not resolve AMIP sensitivity -- demonstrating that AMIP robustness is distinct from gross-error robustness.

### Microcredit RCTs -- OLS (Section 4.3)

Seven studies, simple OLS of profit on treatment. Mexico ($N \approx 16{,}500$): a single observation determines the sign of the ATE; removing 15 observations (< 0.1%) produces a significant result of the opposite sign. All seven studies can have sign or significance reversed by removing < 1%.

### Microcredit RCTs -- Bayesian Hierarchical Model (Section 4.4)

Same data, Bayesian hierarchical tailored mixture model estimated via variational Bayes. AMIP applies because VB is a Z-estimator. Average treatment effect parameters ($\tau_+$, $\tau_-$) remain AMIP non-robust (sign changes with 0.09-0.21% removal). **Important caveat**: the approximation fails for hypervariance parameters near the boundary of their admissible space, producing large errors upon refitting. The authors flag this as a concrete limitation of the first-order approximation.

## Literature Context

**True precursors:**

- Hampel (1974) and Hampel et al. (1986): the classical influence function -- the core technical tool. The entire AMIP approximation is the empirical influence function applied to data-dropping.
- Giordano, Stephenson, Liu, Jordan, and Broderick (2019): the "Swiss Army Infinitesimal Jackknife," co-authored by two of the present authors. Theorem 1 of the present paper follows from applying Theorem 1 of this earlier work. The regularity conditions are identical.
- Huber (1964, 1981) and the breakdown point tradition: the paper defines its contribution by contrast -- same tools, different question (data deletion vs. arbitrary contamination; finite decision-relevant changes vs. unbounded breakdown).
- Cook (1977) and Belsley, Kuh, and Welsch (1980): leave-one-out diagnostics. The present paper scales this from individual observations to non-vanishing proportions and reframes the goal from outlier detection to decision-relevant sensitivity.
- Masten and Poirier (2020): the most directly comparable contemporary econometrics work on "breakdown frontiers." Positioned as complementary (global vs. local sensitivity).

**Gaps worth noting:** No engagement with Koh and Liang (2017) beyond a brief mention (close overlap in using influence functions to identify influential training points); no discussion of the delete-$d$ jackknife literature; Andrews, Gentzkow, and Shapiro (2017) on sensitivity of empirical results not cited.

## Index

- Introduction and motivation: Section 1
- Definition of MIP and AMIP: Section 2 (Definitions 1-2)
- Taylor expansion derivation: Section 2.1
- Computing influence scores: Section 2.2.2
- Example functions (sign change, significance change): Section 2.3
- OLS regression example (Mexico microcredit): Section 2.4
- OLS theory and signal-to-noise: Section 3.1
- General Z-estimator theory: Section 3.2
- Signal-noise-shape decomposition: Section 3.2.2
- Theorem 1 (approximation accuracy): Section 3.3
- Related work discussion: Section 3.4
- Oregon Medicaid application: Section 4.1
- Cash transfers application: Section 4.2
- Microcredit OLS application: Section 4.3
- Microcredit Bayesian hierarchical application: Section 4.4
- Conclusion: Section 5
- Detailed proofs: Appendix A
- Tightness of approximation bounds: Appendix B
