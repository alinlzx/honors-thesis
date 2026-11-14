# Speaker effects in the US and China series

Code: `robustness/speaker_fe.R` (run from the repo root, about 4 minutes).
Outputs: `robustness/output/speaker_fe_*.csv`, `speaker_fe_series.pdf`.

## 1. The problem

The exhibits treat each country's series as the period mean of document scores. Each
document has a speaker: an MFA spokesperson, People's Daily, or a US archive. Speakers
differ in register (a Public Papers speech is not a Congressional Daily Digest entry),
and the mix of speakers changes over time. Part of the movement in the series can
therefore come from *who is talking*, not from *how the country is talking*.

## 2. A decomposition

For document $d$ in country $c$, spoken by speaker $k(d)$ in period $t(d)$:

$$
y_d = \theta_{c,t(d)} + \alpha_{k(d)} + \varepsilon_d ,
$$

- $\theta_{c,t}$: the country's underlying posture toward the other country in period $t$ (the quantity of interest);
- $\alpha_k$: a time-invariant speaker effect (house style, document type, scorer bias toward that genre);
- $\varepsilon_d$: document noise (topic of the day, classifier error), mean zero.

The series used in the thesis is the period mean over the $n_{c,t}$ documents:

$$
\bar y_{c,t} = \theta_{c,t} + \underbrace{\sum_k w_{k,t}\,\alpha_k}_{\text{composition}} + \underbrace{\bar\varepsilon_{c,t}}_{\text{noise, var} \,\approx\, \sigma^2/n_{c,t}} ,
\qquad w_{k,t} = n_{k,t}/n_{c,t}.
$$

Two things in this equation matter for the Granger tests:

1. **Composition.** If $w_{k,t}$ shifts (Zhao Lijian takes more briefings; Congress
   enters the US series more heavily in some years), $\bar y$ moves with $\theta$ fixed. If composition shifts in the two countries happen to line up in time, they can produce a lead–lag pattern even though neither country's posture changed.
2. **Noise.** $\bar\varepsilon$ is heteroskedastic in $n_{c,t}$ (sparse weeks are noisy). Weighting or
   state-space smoothing would address this; it is not addressed here (methods branch).

The speaker-adjusted series removes the composition term:
$\tilde y_{c,t} = \frac{1}{n_{c,t}}\sum_{d \in (c,t)} (y_d - \hat\alpha_{k(d)}) = \bar y_{c,t} - \sum_k w_{k,t}\hat\alpha_k$.

### Identification

$\alpha_k$ and $\theta_t$ can be told apart only where speakers overlap in time.
Estimate $y_d = \mu_t + \alpha_k + \varepsilon_d$ with **month fixed effects** (main specification).
Each $\alpha_k$ then comes from comparing speakers *within the same month*.
- **MFA.** Spokespeople rotate day to day: 143 of the 217 MFA months have two or more spokespeople, including nearly every month from 2014 on.
- **US.** The archives run in parallel.
- The adjusted monthly series is then exactly $\hat\mu_t$ (the OLS first-order condition for $\mu_t$).

Anything with no within-period overlap is not identified separately from $\theta$. That includes administration effects, and a spokesperson's style apart from the era they served in. By construction, all of it stays in $\theta$.

Two contrasts, both run:
- **Week FE.** The same model with week effects. Only 58 of 795 MFA weeks have more than one spokesperson. The pre-2012 spokesperson effects have SEs of about 0.9, so this variant is noise. It is reported only for completeness.
- **No time FE** ($y_d = \alpha_k + \varepsilon_d$). MFA tenures are staggered, so this attributes era-level shifts in tone to whoever was spokesperson at the time. It is an upper bound on what speaker adjustment could remove, not a credible estimate of $\alpha$.

### Speakers

| Corpus | Speaker levels |
|---|---|
| MFA | Spokesperson from the raw `spokesperson` field (13 people; 24 rows coded "missing" kept as their own level) |
| People's Daily | One level |
| Presidential Library | Public Papers; Daily (Weekly) Compilation; CRS reports & other (the Figure 2 title rule) |
| Congress | Congressional Record by section (Senate, House, Extensions of Remarks, Daily Digest, other) vs CRS reports & other |

$\alpha$ is estimated separately for each country, on the exact sample of each test: MFA vs Presidential (Fig 13), and the full country series (Fig 14). It is centred at a document-weighted mean of zero. The Granger procedure is unchanged: `granger_p()`, lag 3, start dates 1 January 2002–2020, weekly and monthly, as in Figs 13, 14 and 28.

## 3. Estimated speaker effects (approach 2, month FE)

Effects are in hybrid-score units. The document-level SD is 0.55 (US) and 0.81 (China). SEs are clustered by month, relative to the reference level (the largest speaker, shown with "ref").

| Speaker | $\hat\alpha$ (SE) | Same, no time FE |
|---|---|---|
| Pres: Public Papers | +0.19 (0.05) | +0.25 |
| Pres: Daily Compilation | −0.06 (ref) | −0.08 |
| Pres: CRS & other | −0.39 (0.06) | −0.39 |
| MFA: Hua Chunying | −0.03 (ref) | −0.11 |
| MFA: Zhao Lijian | +0.12 (0.07) | −0.54 |
| MFA: Wang Wenbin | +0.19 (0.06) | −0.49 |
| MFA: Geng Shuang | +0.06 (0.05) | +0.01 |
| MFA: Lu Kang | +0.08 (0.06) | +0.25 |
| MFA: Qin Gang | −0.20 (0.09) | +0.40 |
| MFA: Kong Quan / Liu Jianchao / Zhang Qiyue | −0.05 / −0.14 / −0.16 (SE 0.16–0.22) | +0.53 / +0.39 / +0.51 |

(MFA vs Presidential sample. Full-sample US effects: Congressional Record House −0.21, Senate −0.15, CRS −0.17; see `speaker_fe_alpha.csv`.)

- **US.** Speaker effects are real and stable across specifications. Public Papers entries (single speeches) score 0.58 higher than CRS reports, about one US document-level SD.
- **MFA.** Compared within the same month, spokespeople are close to each other. The "wolf warrior" spokespeople (Zhao, Wang) are, if anything, slightly *warmer* than Hua on the same days. The large spread without time FE (−0.54 to +0.53) is the era, not the person: the 2020–21 decline is not a spokesperson composition artifact.
- **Composition matters little for the series.** The variance of $\sum_k w_{k,t}\hat\alpha_k$ is 4–10% of the variance of the observed series for MFA vs Presidential, and 9–21% for the full data (`speaker_fe_variance.csv`). Observed and adjusted series correlate at 0.89–0.98.
- **One caveat for the full China series.** People's Daily overlaps with every month, so it anchors the MFA effects. Early MFA spokespeople come out +0.3 to +0.4 relative to People's Daily in the same month, which lowers the adjusted 2003–08 China level (`speaker_fe_series.pdf`). This is the MFA–People's Daily gap narrowing over time, loaded onto the people who spoke early. The model assumes the two Chinese outlets share one $\theta_t$.

## 4. Headline Granger results, observed vs speaker-adjusted

The table gives the number of the 19 start-date windows with $p < 0.05$. In the adjusted series, speaker effects are estimated with month FE.

**Approach 2 (exported exhibits)**

| Test | Interval | US as response: observed → adjusted | China as response: observed → adjusted |
|---|---|---|---|
| MFA vs Presidential (Fig 13) | week | 18 → 18 | 1 → 1 (2019 start) |
| MFA vs Presidential | month | 17 → 17 | 0 → 0 |
| Full data (Fig 14) | week | 18 → 18 | 6 → 6 (2002–07 starts) |
| Full data | month | 17 → 17 | 0 → 0 |

**Approach 1 (closest to the thesis scores)**

| Test | Interval | US as response | China as response |
|---|---|---|---|
| MFA vs Presidential | week | 18 → 18 | 5 → **0** (2002–06 starts lost) |
| MFA vs Presidential | month | 16 → 16 | 0 → 0 |
| Full data | week | 18 → 18 | 0 → 0 |
| Full data | month | 17 → 16 | 0 → 0 |

The windows where US as response is not significant are the late starts in every case: weekly, 2020 only; monthly, 2019–20 (approach 1, MFA/Presidential: 2018–20; approach 1, full data: 2018 is added after adjustment).

**Contrasts.**
- **No time FE.** US as response survives in only 0–7 of 19 windows (approach 2: 2 / 2 / 0 / 5 in the order above; approach 1: 6 / 7 / 0 / 15).
- **Week FE.** US as response is 15 / 8 / 18 / 17. China as response rises to 7 and 12 weekly windows. With SEs near 0.9 on the early spokespeople, this mostly reflects noise in $\hat\alpha$.

## 5. Reading

- **The headline survives the speaker adjustment.** After within-period speaker effects are removed, "US posture responds to Chinese posture" holds in the same 16–18 of 19 windows, weekly and monthly, MFA/Presidential and full data, under both approaches. The weak and early-window "China as response" results are unchanged or weaker. Under approach 1, the MFA/Presidential early windows disappear. So the asymmetry is not produced by shifts in who is speaking.
- **What the no-time-FE contrast shows.** It kills the result. This does not mean the result is a speaker artifact: that specification also deletes most genuine change in Chinese posture, because spokesperson tenures are staggered. It does show that the result rests on *multi-year, era-level* movements in Chinese tone (e.g. warming to 2017, then the 2019–21 decline), not on week-to-week variation within an era. That is also the variation most exposed to trend and non-stationarity concerns, so the methods-branch fixes (differencing, Toda–Yamamoto, gap handling) matter more for this result than speaker effects do.
- **Not identified here.** Administration effects, or "a spokesperson's personal style versus the era they served in", cannot be separated from $\theta$ without overlap. A paper should say plainly that $\theta$ includes them.

Suggested sentence for the paper: *"Re-estimating each series net of speaker fixed effects (MFA spokesperson; US archive and Congressional Record section), identified from within-month overlap, leaves the pattern of Granger tests unchanged: US sentiment responds to lagged Chinese sentiment in 16–18 of 19 windows (Appendix X)."*
