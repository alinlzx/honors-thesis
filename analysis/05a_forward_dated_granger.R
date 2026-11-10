# Replicates the thesis's Figure 13: Granger tests between the President and the MFA on
# forward-dated windows (all data from January 1 of a start year onward), in both directions.
#
# In:  build/01_units.csv, build/02_relevance_scores.csv, build/05_spec_d_scores.csv,
#      build/06_adjusted_scores.csv
# Out: analysis/05a_granger_forward.csv          p-values for every window, lag, score and gap rule
#      analysis/05a_stationarity.csv             ADF tests on the full-sample monthly series
#      analysis/05a_table_granger_forward.tex    the paper table (needs booktabs, threeparttable)
#
# The weekly version is analysis/05b_forward_dated_granger_weekly.R.
#
# Choices, and why (all fixed before the tests were run):
# - Monthly, not weekly. The thesis grouped passages into calendar weeks (non-overlapping bins,
#   not a rolling average) and joined the two sides with inner_join, which silently dropped weeks
#   in which either side was silent. The rows left were then treated as consecutive, so "lag 3"
#   was three observed weeks, not three calendar weeks. Here the unit is the calendar month
#   (passages -> document means -> monthly mean; analysis_recipes.md 4), which is the primary
#   frequency, and every lag is a calendar month.
# - Non-overlapping months, not a rolling 30-day mean. Overlapping windows share passages, so
#   neighbouring values are mechanically correlated. That builds a moving-average structure into
#   both series that the lag polynomial then has to fit, and makes F-tests overconfident.
# - Missing months are filled by linear interpolation between the neighbouring months: 14 MFA
#   months (mostly the August recess, through 2015) and 1 presidential month (June 2003), out of 279. The
#   alternative, closing the series up over them, would make the lags wrong as the thesis's join
#   did. Interpolation borrows the following month's value, though, so the CSV also has the tests
#   with gaps left missing (gaps = "dropped"): a row enters only if every month it uses was
#   observed (granger_calendar in series_common.R). Windows from 2016 on have no gaps.
# - Stationarity: an augmented Dickey-Fuller test (constant, lag length by AIC up to 12) on each
#   full-sample series in levels. If either series fails to reject a unit root at 5%, both are
#   first-differenced, in every window, so the two directions are always tested on the same
#   transformation. The thesis differenced only the series that failed.
# - Lags: 3, the thesis's Figure 13 setting, and the lag that minimises the AIC of the bivariate
#   VAR on the full sample (up to 12), which is the less discretionary choice. The thesis picked
#   3 after seeing the tables at 2 and 3.
# - The score is spec D with speaker effects removed (net_adj, build/06); the raw score is
#   reported alongside as the robustness check.
# - The windows are nested, so their p-values are far from independent, and no correction is
#   made for testing 20 windows in two directions. The table is descriptive.

source("config.R")
source("analysis/series_common.R")
suppressPackageStartupMessages(library(urca))

START_YEARS <- 2002:2021  # the last window keeps 60 months
THESIS_LAG <- 3
MAX_LAG <- 12
ALPHA <- 0.05
SCORES <- c(adjusted = "net_adj", raw = "net")
GAP_RULES <- c("interpolated", "dropped")  # the first is the table's
dir.create(ANALYSIS_DIR, showWarnings = FALSE)

passages <- load_scored_passages() %>% filter(source %in% c("mfa", "presdocs"))

# Both sides on one calendar grid, from the first month both have data to the last.
paired_series <- function(score) {
  m <- monthly_series(passages, score) %>%
    select(source, month, value) %>%
    pivot_wider(names_from = source, values_from = value)
  first <- max(m$month[!is.na(m$mfa)][1], m$month[!is.na(m$presdocs)][1])
  grid <- tibble(month = seq(first, max(m$month), by = "month"))
  grid %>%
    left_join(m, by = "month") %>%
    mutate(gap_mfa = is.na(mfa), gap_presdocs = is.na(presdocs),
           china = approx(as.numeric(month), mfa, as.numeric(month))$y,
           us = approx(as.numeric(month), presdocs, as.numeric(month))$y) %>%
    select(month, china, us, china_obs = mfa, us_obs = presdocs, gap_mfa, gap_presdocs)
}

adf <- function(x) {
  test <- ur.df(x, type = "drift", lags = MAX_LAG, selectlags = "AIC")
  tibble(statistic = test@teststat[1], critical_5pct = test@cval[1, "5pct"],
         lags = sum(grepl("^z.diff.lag", rownames(test@testreg$coefficients))))
}

# AIC of the bivariate VAR(p) with a constant, every p fit on the same sample.
var_aic_lag <- function(d) {
  y <- as.matrix(d[, c("china", "us")])
  n <- nrow(y)
  aic <- vapply(seq_len(MAX_LAG), function(p) {
    rows <- (MAX_LAG + 1):n
    x <- do.call(cbind, lapply(seq_len(p), function(k) y[rows - k, , drop = FALSE]))
    resid <- lm.fit(cbind(1, x), y[rows, ])$residuals
    log(det(crossprod(resid) / length(rows))) + 2 * (4 * p + 2) / length(rows)
  }, numeric(1))
  which.min(aic)
}

# With no missing months, granger_calendar is identical to lmtest::grangertest.
granger_p <- function(d, lag) {
  c(china_to_us = granger_calendar(d$china, d$us, lag)[["p"]],
    us_to_china = granger_calendar(d$us, d$china, lag)[["p"]])
}

results <- list()
stationarity <- list()
for (score_name in names(SCORES)) {
  levels <- paired_series(SCORES[[score_name]])

  st <- bind_rows(china = adf(levels$china), us = adf(levels$us), .id = "series") %>%
    mutate(score = score_name, months = nrow(levels),
           unit_root_rejected = statistic < critical_5pct,
           gaps_filled = c(sum(levels$gap_mfa), sum(levels$gap_presdocs)))
  stationarity[[score_name]] <- st
  difference <- !all(st$unit_root_rejected)

  transform <- function(d) {
    if (difference) transmute(d, month, china = c(NA, diff(china)), us = c(NA, diff(us))) %>% slice(-1)
    else select(d, month, china, us)
  }
  # The lag is chosen once, on the interpolated series, and used under both gap rules.
  aic_lag <- var_aic_lag(transform(levels))
  for (gaps in GAP_RULES) {
    series <- if (gaps == "interpolated") transform(levels)
              else transform(transmute(levels, month, china = china_obs, us = us_obs))
    for (start in START_YEARS) {
      window <- filter(series, month >= as.Date(sprintf("%d-01-01", start)))
      for (lag in unique(c(THESIS_LAG, aic_lag))) {
        p <- granger_p(window, lag)
        results[[length(results) + 1]] <- tibble(
          score = score_name, gaps = gaps, differenced = difference, start_year = start,
          first_month = min(window$month), months = nrow(window),
          lag = lag, lag_rule = if (lag == THESIS_LAG) "thesis" else "aic",
          china_to_us = p[["china_to_us"]], us_to_china = p[["us_to_china"]])
        if (lag == aic_lag && aic_lag == THESIS_LAG) {
          results[[length(results) + 1]] <- mutate(results[[length(results)]], lag_rule = "aic")
        }
      }
    }
  }
}
results <- bind_rows(results)
stationarity <- bind_rows(stationarity)
write_csv(results, file.path(ANALYSIS_DIR, "05a_granger_forward.csv"))
write_csv(stationarity, file.path(ANALYSIS_DIR, "05a_stationarity.csv"))

# ---- Paper table -------------------------------------------------------------------

fmt_p <- function(p) {
  s <- ifelse(p < 0.001, formatC(p, format = "e", digits = 1), sprintf("%.3f", p))
  s <- sub("e-0?(\\d+)$", "$\\\\times 10^{-\\1}$", s)
  ifelse(p < ALPHA, paste0("\\textbf{", s, "}"), s)
}

table_results <- filter(results, gaps == GAP_RULES[1])
lag_of <- function(score_name, rule) unique(table_results$lag[table_results$score == score_name & table_results$lag_rule == rule])

panel <- function(score_name) {
  d <- table_results %>% filter(score == score_name)
  wide <- d %>%
    select(start_year, first_month, months, lag_rule, china_to_us, us_to_china) %>%
    pivot_wider(names_from = lag_rule, values_from = c(china_to_us, us_to_china))
  vapply(seq_len(nrow(wide)), function(i) {
    w <- wide[i, ]
    label <- if (w$start_year == min(START_YEARS)) sprintf("%s (all)", format(w$first_month, "%b %Y")) else w$start_year
    sprintf("%s & %d & %s & %s && %s & %s \\\\", label, w$months,
            fmt_p(w$china_to_us_thesis), fmt_p(w$us_to_china_thesis),
            fmt_p(w$china_to_us_aic), fmt_p(w$us_to_china_aic))
  }, character(1))
}

adj <- stationarity %>% filter(score == "adjusted")
differenced <- unique(results$differenced[results$score == "adjusted"])
gaps <- setNames(adj$gaps_filled, adj$series)

tex <- c(
  "% Generated by analysis/05a_forward_dated_granger.R; do not edit by hand.",
  "% Needs \\usepackage{booktabs} and \\usepackage{threeparttable} in the preamble.",
  "\\begin{table}[htbp]",
  "\\centering",
  "\\small",
  "\\begin{threeparttable}",
  "\\caption{Granger tests between the President and the MFA on forward-dated windows}",
  "\\label{tab:granger-forward}",
  "\\begin{tabular}{@{}l r rr c rr@{}}",
  "\\toprule",
  sprintf(" & & \\multicolumn{2}{c}{Lag %d (thesis)} & & \\multicolumn{2}{c}{Lag %d (AIC)} \\\\",
          THESIS_LAG, lag_of("adjusted", "aic")),
  "\\cmidrule(l{2pt}r{2pt}){3-4} \\cmidrule(l{2pt}r{2pt}){6-7}",
  "Data from & Months & China $\\to$ US & US $\\to$ China && China $\\to$ US & US $\\to$ China \\\\",
  "\\midrule",
  "\\multicolumn{7}{@{}l}{\\textit{A. Speaker-adjusted stance (main)}} \\\\",
  panel("adjusted"),
  "\\midrule",
  sprintf("\\multicolumn{7}{@{}l}{\\textit{B. Raw stance (lag %d by AIC)}} \\\\", lag_of("raw", "aic")),
  panel("raw"),
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{tablenotes}[flushleft]",
  "\\footnotesize",
  paste0(
    "\\item \\textit{Notes:} Each cell is the $p$-value of an $F$-test that the lags of one series add ",
    "nothing to an autoregression of the other (\\texttt{lmtest::grangertest}). China $\\to$ US tests ",
    "whether the MFA's past stance predicts the President's; US $\\to$ China the reverse. ",
    "Each row uses all months from January 1 of the year shown to December 2025. ",
    "Stance is the fine-tuned transformer's net stance toward the other country (spec D), averaged ",
    "from passages to documents to calendar months. Panel A removes spokesperson (MFA) and genre ",
    "(President) effects estimated within months. ",
    if (differenced) "Both series are first-differenced, because an augmented Dickey--Fuller test does not reject a unit root in at least one of them over the full sample. "
    else "Both series are in levels: augmented Dickey--Fuller tests reject a unit root in each over the full sample. ",
    sprintf("Months with no press conference (%d) or no presidential passage (%d) are linearly interpolated; windows from 2016 have none. Leaving them missing instead, so that a month enters only if every month its lags use was observed, gives no $p < 0.05$ either. ",
            gaps[["china"]], gaps[["us"]]),
    sprintf("The AIC lag minimises the AIC of the bivariate VAR over lags 1--%d on the full sample. ", MAX_LAG),
    sprintf("Bold: $p < %.2f$. The windows are nested and the tests are not corrected for multiplicity, ", ALPHA),
    "so the rows are not independent evidence."
  ),
  "\\end{tablenotes}",
  "\\end{threeparttable}",
  "\\end{table}"
)
writeLines(tex, file.path(ANALYSIS_DIR, "05a_table_granger_forward.tex"))

# ---- Console summary ---------------------------------------------------------------

cat("== Stationarity (full-sample levels) ==\n")
print(as.data.frame(mutate(stationarity, across(where(is.numeric), ~ round(.x, 3)))))
cat("\n== Forward-dated Granger p-values ==\n")
print(as.data.frame(results %>%
  select(score, gaps, start_year, months, lag_rule, lag, china_to_us, us_to_china) %>%
  mutate(across(c(china_to_us, us_to_china), ~ signif(.x, 2)))), row.names = FALSE)
