# Speaker fixed effects: do the headline Granger results survive once speaker
# composition is taken out of the US and China series?
#
# Model (see robustness/speaker_fe_note.md):
#   y_d = theta_{c, t(d)} + alpha_{k(d)} + e_d
# for document d by speaker k in period t of country c. The observed period mean is
#   ybar_t = theta_t + sum_k w_{kt} alpha_k + ebar_t,
# so a shift in who is speaking (w_{kt}) moves the series even when posture theta_t
# does not. The adjusted series is the period mean of (y_d - alpha_hat_k).
#
# Speakers:
#   MFA            the press-conference spokesperson (raw `spokesperson`; 24 rows coded
#                  "missing" kept as their own level)
#   People's Daily one level
#   Presidential   archive, by the Figure 2 title/subhead rule: Public Papers, Daily
#                  Compilation, CRS reports & other
#   Congress       Congressional Record by section (Senate, House, Extensions of Remarks,
#                  Daily Digest, other Record items) vs CRS reports & other
#
# Estimating alpha:
#   twfe   y_d ~ speaker + month   (main). alpha is identified from speakers who
#          overlap within a month (MFA spokespeople rotate day to day; the US archives
#          run in parallel), so it does not absorb real change in posture over time.
#          The adjusted monthly series is then exactly the estimated month effects.
#   week   y_d ~ speaker + week    (alpha from within-week overlap only).
#   naive  y_d ~ speaker           (no time effects). An upper bound: because MFA
#          tenures are staggered, this also strips out genuine posture shifts that
#          coincide with a spokesperson's tenure.
# alpha is estimated separately on the exact sample of each test (MFA/Presidential;
# full country series), and separately for each country.
#
# Granger tests: unchanged from Figures 13, 14 and 28 (granger_p() in setup.R; lag 3;
# periods strictly after 1 January of each year 2002-2020; weekly and monthly).
#
# Run from the repo root:  Rscript robustness/speaker_fe.R
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv, 00_corpora.csv
# Output: robustness/output/speaker_fe_alpha.csv       speaker effects with SEs
#         robustness/output/speaker_fe_granger.csv     every test, raw and adjusted
#         robustness/output/speaker_fe_summary.csv     significant windows, by spec
#         robustness/output/speaker_fe_variance.csv    how much of each series is composition
#         robustness/output/speaker_fe_series.pdf      raw vs adjusted series

source("figures/setup.R")
suppressPackageStartupMessages(library(lmtest))

OUT <- file.path(REPO_ROOT, "robustness", "output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
LAG_ORDER <- 3
START_YEARS <- 2002:2020
VERSIONS <- c("a2", "a1")   # approach 2 = the exported exhibits; approach 1 = closest to the thesis

# ---- Speaker labels --------------------------------------------------------------------------
speaker_labels <- function() {
  s <- read_scored()
  titles <- read_corpora() %>% select(source, doc_id, title, subhead)
  mofa <- s$mofa %>% transmute(source, doc_id, speaker = paste("MFA:", ifelse(is.na(spokesperson), "missing", spokesperson)))
  pd <- s$peoplesdaily %>% transmute(source, doc_id, speaker = "People's Daily")
  pres <- s$pres %>% select(source, doc_id) %>% left_join(titles, by = c("source", "doc_id")) %>%
    transmute(source, doc_id, speaker = case_when(   # Figure 2 rule
      grepl("Pub. Papers", title) ~ "Pres: Public Papers",
      grepl("Compilation", title) | grepl("Compilation", subhead) ~ "Pres: Daily Compilation",
      TRUE ~ "Pres: CRS & other"))
  cong <- s$congress %>% select(source, doc_id) %>% left_join(titles, by = c("source", "doc_id")) %>%
    transmute(source, doc_id, speaker = case_when(
      !grepl("Cong. Rec.", title) ~ "Cong: CRS & other",
      grepl("Senate", subhead) ~ "Cong: Record, Senate",
      grepl("House", subhead) ~ "Cong: Record, House",
      grepl("Extension", subhead) ~ "Cong: Record, Extensions",
      grepl("Daily Digest", subhead) ~ "Cong: Record, Daily Digest",
      TRUE ~ "Cong: Record, other"))
  bind_rows(mofa, pd, pres, cong)
}
SPEAKERS <- speaker_labels()

add_periods <- function(d) {
  d %>% mutate(month = as.Date(paste0(format(date, "%Y-%m"), "-01")),
               week = as.Date("2000-01-01") +
                 7 * floor(as.numeric(difftime(date, as.Date("2000-01-01"), units = "weeks"))))
}

# ---- Speaker effects ---------------------------------------------------------------------------
# CR1 cluster-robust standard errors (as sandwich::vcovCL(type = "HC1"), which is not installed).
# Only `keep` (the speaker terms) is returned: the period dummies' variances can be
# numerically <= 0 for single-document periods.
cluster_se <- function(fit, cluster, keep) {
  X <- model.matrix(fit)[, !is.na(coef(fit)), drop = FALSE]
  u <- residuals(fit); n <- nrow(X); k <- ncol(X); G <- length(unique(cluster))
  bread <- chol2inv(qr.R(qr(X)))
  meat <- crossprod(rowsum(X * u, cluster))
  V <- bread %*% meat %*% bread * (G / (G - 1)) * ((n - 1) / (n - k))
  sqrt(setNames(diag(V), colnames(X))[keep])
}

# Returns one row per speaker: alpha (centred so the document-weighted mean is 0 within
# the sample; the level of a series does not matter for Granger tests) and its SE
# (HC1, clustered by month).
estimate_alpha <- function(d, method) {
  d <- mutate(d, speaker = relevel(factor(speaker), ref = names(which.max(table(speaker)))))
  if (nlevels(d$speaker) == 1) return(tibble(speaker = levels(d$speaker), alpha = 0, se = NA_real_))
  f <- switch(method, twfe = hybrid ~ speaker + factor(month), week = hybrid ~ speaker + factor(week),
              naive = hybrid ~ speaker)
  fit <- lm(f, data = d)
  b <- coef(fit)[paste0("speaker", levels(d$speaker)[-1])]
  if (anyNA(b)) stop("speaker effect not identified (", method, "): ", paste(names(b)[is.na(b)], collapse = ", "))
  se <- cluster_se(fit, d$month, names(b))
  out <- tibble(speaker = levels(d$speaker), raw = c(0, b), se = c(NA, se))
  w <- table(d$speaker)[out$speaker]
  mutate(out, alpha = raw - sum(raw * w) / sum(w), n_docs = as.integer(w)) %>% select(-raw)
}

adjust <- function(d, method) {
  if (method == "raw") return(d)
  a <- estimate_alpha(d, method)
  d %>% left_join(select(a, speaker, alpha), by = "speaker") %>% mutate(hybrid = hybrid - alpha)
}

# ---- Run ------------------------------------------------------------------------------------------
METHODS <- c("raw", "twfe", "week", "naive")
builders <- list(week = weekly_series, month = monthly_series)

run_version <- function(version) {
  docs <- read_documents(version) %>% filter(dated) %>% left_join(SPEAKERS, by = c("source", "doc_id")) %>%
    add_periods()
  stopifnot(!anyNA(docs$speaker))
  pairs <- list(mfa_pres = list(us = filter(docs, source == "pres"), ch = filter(docs, source == "mofa")),
                full = list(us = filter(docs, in_series, country == "US"),
                            ch = filter(docs, in_series, country == "China")))

  alpha <- bind_rows(lapply(names(pairs), function(p) bind_rows(lapply(c("twfe", "week", "naive"), function(m) {
    bind_rows(lapply(c("us", "ch"), function(ctry) estimate_alpha(pairs[[p]][[ctry]], m) %>% mutate(country = ctry))) %>%
      mutate(data = p, method = m)
  })))) %>% mutate(version = version)

  granger <- bind_rows(lapply(names(pairs), function(p) bind_rows(lapply(METHODS, function(m) {
    us_d <- adjust(pairs[[p]]$us, m); ch_d <- adjust(pairs[[p]]$ch, m)
    bind_rows(lapply(names(builders), function(b) {
      us <- builders[[b]](us_d); ch <- builders[[b]](ch_d)
      bind_rows(lapply(START_YEARS, function(y) granger_p(us, ch, as.Date(paste0(y, "-01-01")), LAG_ORDER) %>%
                         mutate(start = y))) %>% mutate(interval = b)
    })) %>% mutate(data = p, method = m)
  })))) %>% mutate(version = version)

  # Composition term c_t = sum_k w_kt alpha_k (twfe alpha): its share of the observed series' variance.
  variance <- bind_rows(lapply(names(pairs), function(p) bind_rows(lapply(c("us", "ch"), function(ctry) {
    d <- pairs[[p]][[ctry]]
    a <- estimate_alpha(d, "twfe")
    d <- left_join(d, select(a, speaker, alpha), by = "speaker")
    bind_rows(lapply(c("week", "month"), function(b) {
      s <- d %>% group_by(t = .data[[b]]) %>% summarise(y = mean(hybrid), comp = mean(alpha), .groups = "drop")
      tibble(interval = b, var_observed = var(s$y), var_composition = var(s$comp),
             cor_observed_adjusted = cor(s$y, s$y - s$comp))
    })) %>% mutate(data = p, country = ctry)
  })))) %>% mutate(version = version)

  list(alpha = alpha, granger = granger, variance = variance, docs = pairs)
}

res <- lapply(VERSIONS, run_version)
alpha <- bind_rows(lapply(res, `[[`, "alpha"))
granger <- bind_rows(lapply(res, `[[`, "granger"))
variance <- bind_rows(lapply(res, `[[`, "variance"))

summary_tab <- granger %>%
  group_by(version, data, interval, method) %>%
  summarise(us_response_sig = sum(us_response < 0.05), china_response_sig = sum(china_response < 0.05),
            china_sig_starts = paste(start[china_response < 0.05], collapse = " "),
            us_nonsig_starts = paste(start[us_response >= 0.05], collapse = " "),
            median_us_p = median(us_response), median_china_p = median(china_response), .groups = "drop") %>%
  mutate(method = factor(method, levels = METHODS)) %>% arrange(version, data, interval, method)

write_csv(alpha, file.path(OUT, "speaker_fe_alpha.csv"))
write_csv(granger, file.path(OUT, "speaker_fe_granger.csv"))
write_csv(summary_tab, file.path(OUT, "speaker_fe_summary.csv"))
write_csv(variance, file.path(OUT, "speaker_fe_variance.csv"))

options(width = 200)
print(as.data.frame(summary_tab))
print(as.data.frame(variance %>% mutate(share = var_composition / var_observed)), digits = 3)
print(as.data.frame(alpha %>% filter(version == "a2", method != "week") %>%
                      select(data, method, country, speaker, n_docs, alpha, se) %>% arrange(data, country, method, speaker)),
      digits = 3)

# ---- Figure: raw vs adjusted monthly series (approach 2, full data, twfe) ---------------------------
d2 <- res[[which(VERSIONS == "a2")]]$docs$full
plot_df <- bind_rows(lapply(c("raw", "twfe", "naive"), function(m) bind_rows(
  monthly_series(adjust(d2$us, m)) %>% mutate(country = "US on China"),
  monthly_series(adjust(d2$ch, m)) %>% mutate(country = "China on the US")) %>% mutate(method = m))) %>%
  mutate(method = factor(c(raw = "Observed", twfe = "Speaker FE (with month FE)", naive = "Speaker FE (no time FE)")[method],
                         levels = c("Observed", "Speaker FE (with month FE)", "Speaker FE (no time FE)")))
curves <- plot_df %>% group_by(country, method) %>%
  group_modify(~ loess_curve(.x, "period", "senti", span = 0.15)) %>% ungroup()
fig <- ggplot(curves, aes(date, fit, colour = method, linetype = method)) +
  geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
  geom_line(linewidth = 0.6) +
  facet_wrap(~country, ncol = 1) +
  scale_colour_manual(values = c("black", "#2166AC", "#B2182B")) +
  scale_linetype_manual(values = c("solid", "dashed", "dotted")) +
  scale_x_years() + ylab("Monthly mean hybrid score (LOESS)") + theme_paper()
save_fig("speaker_fe_series.pdf", fig, height = 4.5)   # writes to figures/output; move below
file.rename(fig_path("speaker_fe_series.pdf"), file.path(OUT, "speaker_fe_series.pdf"))
cat("Done: speaker_fe\n")
