# Measurement noise and the direction of Granger causality: numbers for
# robustness/noise_granger_note.md. Run from the repo root (about 1 minute).
#   Part 1: closed-form one-lag MSEs (Section 3) against a long simulation.
#   Part 2: noise share of the weekly MFA and Presidential series (Section 5).
#   Part 3: Granger rejection rates under a common-driver null at those noise levels.
#   Part 4: signal-to-noise table for the paper (output/noise_snr.tex): full country
#           series (Fig 14 sample) and MFA vs Presidential (Fig 13 sample).

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")
suppressPackageStartupMessages(library(lmtest))

lam <- function(p) p / (1 + p)                     # reliability: signal share of Var(ybar)
mse <- function(V, rho, tau2, p) V + tau2 - rho^2 * V * lam(p)

# ---- Part 1: theory vs simulation, one lag ------------------------------------------------
rho <- 0.8; V <- 1 / (1 - rho^2); tUS2 <- 9; tCN2 <- 0.25
pUS <- V / tUS2; pCN <- V / tCN2
th <- c(US_R = mse(V, rho, tUS2, pUS), US_U = mse(V, rho, tUS2, pUS + pCN),
        CN_R = mse(V, rho, tCN2, pCN), CN_U = mse(V, rho, tCN2, pUS + pCN))
set.seed(2); n <- 2e6
S <- as.numeric(stats::filter(rnorm(n), rho, method = "recursive"))
x <- S + rnorm(n, sd = sqrt(tUS2)); z <- S + rnorm(n, sd = sqrt(tCN2)); i <- 2:n
f <- function(m) mean(resid(m)^2)
sim <- c(f(lm(x[i] ~ x[i - 1])), f(lm(x[i] ~ x[i - 1] + z[i - 1])),
         f(lm(z[i] ~ z[i - 1])), f(lm(z[i] ~ z[i - 1] + x[i - 1])))
cat(sprintf("Part 1: V = %.2f, pi_US = %.2f, pi_CN = %.2f\n", V, pUS, pCN))
print(round(rbind(theory = th, simulation = sim), 3))
rel <- c(US = (th[[1]] - th[[2]]) / th[[2]], CN = (th[[3]] - th[[4]]) / th[[4]])
cat("Delta / MSE_U:", round(rel, 4), "  ncp at T = 600:", round(600 * rel, 1),
    "  power (1 lag):", round(1 - pchisq(qchisq(.95, 1), 1, ncp = 600 * rel), 2), "\n\n")

# ---- Part 2: noise share of the observed weekly series ----------------------------------------
docs <- read_documents() %>% filter(dated) %>%
  mutate(wk = floor(as.numeric(difftime(date, as.Date("2000-01-01"), units = "weeks"))))
weeks <- function(s) docs %>% filter(source == s) %>% group_by(wk) %>%
  summarise(m = mean(hybrid), n = n(), ss = sum((hybrid - mean(hybrid))^2), .groups = "drop")
P <- weeks("pres"); M <- weeks("mofa"); ov <- intersect(P$wk, M$wk)   # the 648 weeks of Fig 13
calib <- bind_rows(lapply(list(Presidential = P, MFA = M), function(w) {
  w <- filter(w, wk %in% ov)
  s2 <- sum(w$ss) / sum(w$n - 1)                   # pooled within-week variance
  tau2 <- s2 * mean(1 / w$n); v <- var(w$m)
  tibble(weeks = nrow(w), sigma = sqrt(s2), mean_inv_n = mean(1 / w$n), tau2 = tau2,
         var_ybar = v, V = v - tau2, pi = (v - tau2) / tau2, reliability = (v - tau2) / v,
         ac1 = acf(w$m, plot = FALSE)$acf[2])
}), .id = "series")
cat("Part 2:\n"); print(as.data.frame(calib), digits = 3)

# ---- Part 3: rejection rates, common driver, calibrated pi, 3 lags, T = 648 ---------------------
run <- function(rho, piUS, piCN, T = 648, reps = 1000) {
  rowMeans(replicate(reps, {
    S <- as.numeric(arima.sim(list(ar = rho), T, sd = sqrt(1 - rho^2)))   # Var(theta) = 1
    d <- data.frame(us = S + rnorm(T, sd = sqrt(1 / piUS)), ch = S + rnorm(T, sd = sqrt(1 / piCN)))
    c(grangertest(us ~ ch, data = d, order = 3)$`Pr(>F)`[2] < .05,
      grangertest(ch ~ us, data = d, order = 3)$`Pr(>F)`[2] < .05)
  }))
}
set.seed(3)
cat("\nPart 3: share of 1,000 simulations with p < 0.05\n")
for (r in c(0.5, 0.8, 0.95)) {
  p <- run(r, calib$pi[1], calib$pi[2])
  cat(sprintf("rho = %.2f   US as response %.2f   China as response %.2f\n", r, p[1], p[2]))
}

# ---- Part 4: signal-to-noise table (paper) ------------------------------------------------------
# Same estimator as Part 2, on the weeks where both series have at least one document (the
# inner join used by granger_p()). sigma_c^2: pooled within-week variance of document scores;
# tau_c^2 = sigma_c^2 * mean(1/n); Var(theta) = Var(ybar) - tau_c^2; SNR = Var(theta) / tau_c^2.
snr_rows <- function(a, b, labels) {
  wk <- lapply(list(a, b), function(d) d %>% group_by(wk) %>%
    summarise(m = mean(hybrid), n = n(), ss = sum((hybrid - mean(hybrid))^2), .groups = "drop"))
  ov <- intersect(wk[[1]]$wk, wk[[2]]$wk)
  bind_rows(lapply(1:2, function(i) {
    w <- filter(wk[[i]], wk %in% ov)
    s2 <- sum(w$ss) / sum(w$n - 1); tau2 <- s2 * mean(1 / w$n); v <- var(w$m)
    tibble(series = labels[i], weeks = nrow(w), snr = (v - tau2) / tau2,
           mean_n = mean(w$n), one_doc = sum(w$n < 2), one_doc_share = mean(w$n < 2))
  }))
}
snr <- bind_rows(
  snr_rows(filter(docs, in_series, country == "US"), filter(docs, in_series, country == "China"),
           c("United States", "China")) %>% mutate(panel = "A"),
  snr_rows(filter(docs, source == "pres"), filter(docs, source == "mofa"),
           c("Presidential Library", "MFA press conferences")) %>% mutate(panel = "B"))
cat("\nPart 4:\n"); print(as.data.frame(snr), digits = 3)

dir.create("robustness/output", showWarnings = FALSE)
snr_line <- function(r) sprintf("\\quad %s & %.2f & %.1f & %d (%.0f\\%%) \\\\",
                                r$series, r$snr, r$mean_n, r$one_doc, 100 * r$one_doc_share)
panel <- function(p, title) {
  s <- filter(snr, panel == p)
  c(sprintf("\\multicolumn{4}{l}{\\textit{%s} (%d weeks)} \\\\", title, s$weeks[1]),
    sapply(seq_len(nrow(s)), function(i) snr_line(s[i, ])))
}
writeLines(c(
  "% Generated by robustness/noise_granger.R (Part 4) -- do not edit by hand.",
  "% Requires \\usepackage{booktabs} and \\usepackage{threeparttable}.",
  "\\begin{table}[htbp]",
  "\\centering",
  "\\begin{threeparttable}",
  "\\caption{Signal-to-noise ratio of the weekly sentiment series}",
  "\\label{tab:noise-snr}",
  "\\small",
  "\\begin{tabular}{l rrr}",
  "\\toprule",
  " & Signal-to-noise & Documents & Weeks with \\\\",
  " & ratio & per week (mean) & one document \\\\",
  "\\midrule",
  panel("A", "Panel A: Full country series"),
  "\\addlinespace",
  panel("B", "Panel B: MFA vs.\\ Presidential Library"),
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{tablenotes}[flushleft]",
  "\\footnotesize",
  paste("\\item \\textit{Notes:} Signal-to-noise ratio is $\\widehat{\\mathrm{Var}}(\\theta_{c,t})/\\hat\\tau_c^2$,",
        "where $\\hat\\sigma_c^2$ is the pooled within-week variance of document scores,",
        "$\\hat\\tau_c^2 = \\hat\\sigma_c^2 \\cdot \\overline{1/n_{c,t}}$, and",
        "$\\widehat{\\mathrm{Var}}(\\theta_{c,t}) = \\widehat{\\mathrm{Var}}(\\bar y_{c,t}) - \\hat\\tau_c^2$.",
        "Weeks are those in which both series of a panel have at least one document, the samples of the",
        "Granger tests in the left (Panel A) and right (Panel B) panels of \\cref{tab:granger-time}.",
        "Weeks with one document add nothing to $\\hat\\sigma_c^2$ and are the noisiest weeks of the series.",
        "Panel A: US = Presidential Library and a random sample of 2,000 Congressional documents;",
        "China = MFA press conference answers and \\emph{People's Daily} articles.",
        sprintf("Sentiment is the hybrid score (approach %s).", sub("a", "", SCORE_VERSION))),
  "\\end{tablenotes}",
  "\\end{threeparttable}",
  "\\end{table}"), "robustness/output/noise_snr.tex")
cat("Wrote robustness/output/noise_snr.tex\n")
