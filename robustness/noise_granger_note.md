# Measurement noise and the direction of Granger causality

Code: `robustness/noise_granger.R` (run from the repo root, about 1 minute).
Notation follows `speaker_fe_note.md`.

## 1. The problem

Each weekly series is a mean over a handful of documents. Presidential weeks have a median of
2 documents; MFA weeks have 5. Few documents means a noisy weekly mean. Section 3 shows that
when two series share a common driver, **unequal noise alone produces Granger causality**,
running *from the cleaner series to the noisier one*, even if neither country responds to the
other. That is the direction of the headline result (MFA → Presidential), so this alternative
has to be ruled out.

## 2. Setup

From `speaker_fe_note.md`, the period mean is

$$
\bar y_{c,t} = \theta_{c,t} + \sum_k w_{k,t}\,\alpha_k + \bar\varepsilon_{c,t},
\qquad \operatorname{Var}(\bar\varepsilon_{c,t}) = \sigma_c^2 / n_{c,t}.
$$

Composition is handled in that note, so set it aside here: $\bar y_{c,t} = \theta_{c,t} + \bar\varepsilon_{c,t}$.
The noise variance changes with $n_{c,t}$. Its average over the sample is

$$
\tau_c^2 \equiv \sigma_c^2 \cdot \mathbb E\!\left[1/n_{c,t}\right].
$$

**The null world: a common driver and no reaction.** Both countries' postures follow one latent
state, the "temperature" of the relationship, driven by world events:

$$
\theta_{\text{US},t} = \theta_{\text{CN},t} = \theta_t, \qquad
\theta_t = \rho\,\theta_{t-1} + \eta_t, \qquad
V \equiv \operatorname{Var}(\theta_t) = \frac{\sigma_\eta^2}{1-\rho^2}.
$$

Noise is independent across countries and over time, and independent of $\theta$. Neither
country's posture depends on the other's past. Any Granger causality in this world is spurious
as a claim about reaction.

(Allowing $\theta_{c,t} = \beta_c \theta_t$, so the two countries can differ in scale, changes
nothing below once $\pi_c$ is defined as $\beta_c^2 V / \tau_c^2$.)

Two quantities summarize how informative each series is about $\theta$:

$$
\pi_c \equiv \frac{V}{\tau_c^2} \quad\text{(signal-to-noise ratio)}, \qquad
\lambda(\pi) \equiv \frac{\pi}{1+\pi} \quad\text{(reliability: signal share of } \operatorname{Var}(\bar y_{c,t})\text{)}.
$$

## 3. How RSS changes (one lag)

Take US as the response, with one lag ($q = 1$) for a closed form. For $T$ periods,
$\mathrm{RSS}/T \to \mathrm{MSE}$, the population mean squared prediction error, so it is
enough to compare MSEs.

**Restricted model.** Regress $\bar y_{\text{US},t}$ on $\bar y_{\text{US},t-1}$. The noise is serially
independent, so

$$
\operatorname{Cov}(\bar y_{\text{US},t}, \bar y_{\text{US},t-1}) = \rho V, \qquad
\operatorname{Var}(\bar y_{\text{US},t-1}) = V + \tau_{\text{US}}^2 .
$$

The OLS slope is attenuated, $b = \rho V/(V+\tau_{\text{US}}^2) = \rho\,\lambda(\pi_{\text{US}})$. The residual variance is

$$
\mathrm{MSE}_R = \underbrace{V + \tau_{\text{US}}^2}_{\operatorname{Var}(\bar y_{\text{US},t})}
\;-\; \rho^2 V\,\lambda(\pi_{\text{US}}).
$$

If $\theta_{t-1}$ were observed, the predictable part would be $\rho^2 V$. The restricted model
captures only the fraction $\lambda(\pi_{\text{US}})$ of it. The rest,
$\rho^2 V\,[1-\lambda(\pi_{\text{US}})]$, is persistence that a noisy own lag cannot reach, and it
sits in the residuals.

**Unrestricted model.** Add $\bar y_{\text{CN},t-1}$. The best linear predictor of $\bar y_{\text{US},t}$
is $\rho\,\hat\theta_{t-1}$, where $\hat\theta_{t-1}$ is the best linear estimate of $\theta_{t-1}$
from the two lagged readings. The readings have independent noise, so their precisions add:

$$
\operatorname{Var}(\theta_{t-1} - \hat\theta_{t-1})
= \left(\frac{1}{V} + \frac{1}{\tau_{\text{US}}^2} + \frac{1}{\tau_{\text{CN}}^2}\right)^{-1}
= \frac{V}{1+\pi_{\text{US}}+\pi_{\text{CN}}},
\qquad\text{so}\qquad
\operatorname{Var}(\hat\theta_{t-1}) = V\,\lambda(\pi_{\text{US}}+\pi_{\text{CN}}).
$$

Hence

$$
\mathrm{MSE}_U = V + \tau_{\text{US}}^2 - \rho^2 V\,\lambda(\pi_{\text{US}}+\pi_{\text{CN}}).
$$

**The reduction in RSS.**

$$
\boxed{\;
\Delta_{\text{US}} \equiv \mathrm{MSE}_R - \mathrm{MSE}_U
= \rho^2 V\left[\lambda(\pi_{\text{US}}+\pi_{\text{CN}}) - \lambda(\pi_{\text{US}})\right]
= \frac{\rho^2 V\,\pi_{\text{CN}}}{(1+\pi_{\text{US}})(1+\pi_{\text{US}}+\pi_{\text{CN}})}
\;}
$$

By symmetry, with China as the response:

$$
\Delta_{\text{CN}} = \frac{\rho^2 V\,\pi_{\text{US}}}{(1+\pi_{\text{CN}})(1+\pi_{\text{US}}+\pi_{\text{CN}})},
\qquad
\frac{\Delta_{\text{US}}}{\Delta_{\text{CN}}} = \frac{\pi_{\text{CN}}(1+\pi_{\text{CN}})}{\pi_{\text{US}}(1+\pi_{\text{US}})} .
$$

Three things follow.

1. **$\Delta > 0$ whenever $\rho \ne 0$ and the other series has any signal.** In population,
   the Granger null $c_1 = 0$ is false even though neither country reacts to the other.
   The test is right that the other series' past adds predictive content. It is wrong to read
   that as reaction.
2. **The response with the noisier own past gains more.** If $\pi_{\text{CN}} > \pi_{\text{US}}$,
   then $\Delta_{\text{US}} > \Delta_{\text{CN}}$, so the noisier series looks like the follower.
3. **Raw variance does not enter, only signal-to-noise.** Rescaling a series multiplies $V$ and
   $\tau_c^2$ by the same constant, which leaves $\pi_c$, and so the test, unchanged.

A unit-free version of the gain, which drives the test statistic:

$$
\frac{\Delta_c}{\mathrm{MSE}_{U,c}}
= \frac{\rho^2\left[\lambda(\pi_{\text{US}}+\pi_{\text{CN}}) - \lambda(\pi_c)\right]}
       {1 + 1/\pi_c - \rho^2\,\lambda(\pi_{\text{US}}+\pi_{\text{CN}})} .
$$

## 4. From RSS to the F-test

$$
F = \frac{(\mathrm{RSS}_R - \mathrm{RSS}_U)/q}{\mathrm{RSS}_U/(T-k)},
\qquad
\text{noncentrality} \;\approx\; T\cdot\frac{\Delta_c}{\mathrm{MSE}_{U,c}} .
$$

Here $k$ is the number of parameters in the unrestricted model. The noncentrality grows
linearly in $T$. Any fixed $\Delta_c > 0$ is detected with probability approaching 1 as the
sample grows. A spurious lead–lag is not a small-sample accident: more data makes it *more*
significant.

**With $q = 3$ lags** (the exhibits): $\bar y_{c,t}$ is now an ARMA(1,1) process, so a longer own
past averages out part of the noise. $\Delta_c$ shrinks but stays positive unless $\pi_{\text{other}} = 0$.
There is no simple closed form, so Sections 4–5 use simulation for three lags.

**Example** (`noise_granger.R`, Part 1): $\rho = 0.8$, $\sigma_\eta = 1$ ($V = 2.78$),
$\tau_{\text{US}} = 3$, $\tau_{\text{CN}} = 0.5$, so $\pi_{\text{US}} = 0.31$ and $\pi_{\text{CN}} = 11.1$.

| | $\mathrm{MSE}_R$ | $\mathrm{MSE}_U$ | $\Delta/\mathrm{MSE}_U$ | Noncentrality, $T = 600$ | Power, 1 lag | Rejection rate, 3 lags (sim.) |
|---|---|---|---|---|---|---|
| US as response | 11.358 (sim. 11.349) | 10.143 (10.126) | 12.0% | 71.9 | 1.00 | 1.00 |
| China as response | 1.397 (1.397) | 1.393 (1.394) | 0.26% | 1.6 | 0.24 | 0.15 |

The closed-form MSEs match a 2-million-period simulation. The two series share a driver and
neither reacts to the other, yet the test finds "China → US" every time.

## 5. Calibration to MFA vs Presidential (Fig 13 sample)

The two parameters that matter can be estimated from the data:

- **Noise variance:** $\sigma_c^2$ is the pooled within-week variance of document scores, and
  $\tau_c^2 = \sigma_c^2\,\overline{1/n_{c,t}}$. This counts the topic of the day and speaker mix
  as noise, which is what they are from the weekly series' point of view.
- **Signal variance:** $\hat V_c = \operatorname{Var}(\bar y_{c,t}) - \tau_c^2$.

| Series (648 overlap weeks) | $\sigma_c$ | $\overline{1/n}$ | $\tau_c^2$ | $\operatorname{Var}(\bar y)$ | $\hat V_c$ | $\hat\pi_c$ | Reliability $\lambda$ | Lag-1 autocorrelation |
|---|---|---|---|---|---|---|---|---|
| Presidential | 0.559 | 0.533 | 0.167 | 0.217 | 0.051 | 0.30 | 0.23 | 0.17 |
| MFA | 0.700 | 0.285 | 0.139 | 0.262 | 0.123 | 0.88 | 0.47 | 0.48 |

**Both series are mostly noise, and the US series is noisier.** About 77% of the week-to-week
variance in Presidential sentiment is sampling noise, against 53% for MFA. At $\rho = 0.8$,
the formula in Section 3 gives a one-lag RSS reduction of 5.0% for US as response and 2.6% for
China as response. The asymmetry runs in the direction of the headline result.

**But noise alone predicts a two-way result, not a one-way one.** Simulating the common-driver
null at the calibrated $\hat\pi_c$, with 3 lags and $T = 648$ (Part 3):

| $\rho$ | US as response: rejection rate | China as response: rejection rate |
|---|---|---|
| 0.50 | 0.82 | 0.49 |
| 0.80 | 1.00 | 0.90 |
| 0.95 | 1.00 | 0.98 |

In the data, China as response has $p = 0.128$ over the full sample and is significant in only
1 of 19 windows. A purely spurious, noise-driven result at these noise levels would usually
show *both* directions as significant. So noise asymmetry can tilt the result toward
"US responds," and can't be dismissed, but it does not by itself reproduce the one-way pattern.

**Caveats on the calibration.**
- It assumes the two postures share one $\theta_t$ exactly. If they are only partly
  correlated, both rejection rates fall, and the noise story could then produce a weaker,
  one-way pattern.
- Under the model, lag-1 autocorrelation $= \rho\,\lambda$. This implies $\rho \approx 0.74$ for
  Presidential but $\rho \approx 1.0$ for MFA. The two series do not fit one shared AR(1) well,
  and the MFA series looks close to a unit root. That ties back to the stationarity concern in
  `speaker_fe_note.md` §5.
- $\sigma_c$ counts within-week topic variation as noise. If some of it is real within-week
  movement in posture, $\tau_c^2$ is overstated.

## 6. What would address it (methods branch)

- **Equalize noise:** each week, randomly downsample MFA documents to the Presidential count,
  then rerun Fig 13. If US as response survives while $\pi_{\text{US}} \approx \pi_{\text{CN}}$,
  noise asymmetry is not driving it.
- **Thin weeks:** drop weeks with fewer than 3–5 Presidential documents, or move to months,
  where $\overline{1/n}$ is much smaller.
- **Model the noise directly:** a state-space model with
  $\bar y_{c,t} = \theta_{c,t} + \bar\varepsilon_{c,t}$, $\operatorname{Var}(\bar\varepsilon_{c,t}) = \sigma_c^2/n_{c,t}$,
  and a VAR on $(\theta_{\text{US},t}, \theta_{\text{CN},t})$. This tests Granger causality on the
  latent postures rather than on their noisy readings.

Suggested footnote: *"Because weekly means are averages over few documents, a common driver
measured with unequal noise could produce spurious Granger causality from the less noisy
series to the noisier one. Calibrating within-week sampling noise, the Presidential series is
the noisier of the two (reliability 0.23 vs 0.47), but a common-driver model at these noise
levels predicts significant feedback in both directions, which the data do not show
(Appendix X)."*
