# The weekly version of 05a: Granger tests between the President and the MFA on forward-dated
# windows, with calendar weeks and weeks too thin to measure left out.
#
# Why weekly at all: in 05a, month-to-month changes on the two sides are correlated within the
# month (r = .21) but not across months, so any reaction may be faster than a month. The thesis's
# Figure 13 was weekly.
#
# In:  build/01_units.csv, build/02_relevance_scores.csv, build/05_spec_d_scores.csv,
#      build/06_adjusted_scores.csv
# Out: analysis/05b_granger_weekly.csv          p-values for every threshold, window, lag, score
#                                               and transformation
#      analysis/05b_weekly_coverage.csv         weeks kept per side and threshold, by year
#      analysis/05b_table_granger_weekly.tex    the paper table (needs booktabs, threeparttable)
#
# Choices, and why (all fixed before the tests were run):
# - Calendar weeks starting Monday. Passages -> document means -> mean of the week's documents,
#   as for months.
# - A side's week is left missing if it has fewer than N documents. N = 2 is the main threshold:
#   one speech or one press conference is a noisy measure of a week's posture, and two at least
#   halves that sampling variance. N = 2 is also the most the data allow: before 2011 the MFA held
#   two press conferences a week, so N = 3 removes almost every MFA week before 2011. N = 1 (drop
#   only empty weeks) and N = 3 are the sensitivity checks.
# - Dropped weeks stay missing; they are not interpolated or closed up. granger_calendar
#   (series_common.R) uses a week only if it and all its lags were observed on both sides, so
#   lag 3 is always three calendar weeks. The thesis's inner_join closed the series up over
#   silent weeks, so its lags were observed weeks. Interpolating would fill a dropped week with
#   the following week's value, letting the future leak into the lags. The cost is sample size:
#   at N = 2 and lag 3 about 120 weeks qualify, most after 2017.
# - First differences, as in 05a. The monthly ADF test does not reject a unit root in the MFA
#   series, and whether a series has a unit root does not depend on how often it is sampled. A
#   change is defined only between two observed adjacent weeks. Levels, the thesis's weekly
#   specification, are in the CSV.
# - Lags 3 (the thesis's Figure 13) in the table; 1, 2 and 4 in the CSV. No AIC lag: with gaps,
#   a VAR up to a long lag order has too few complete rows to compare lags on.
# - Score: speaker-adjusted (net_adj) in the table, raw in the CSV.
# - The windows are nested and no correction is made for multiple tests. The table is descriptive.

source("config.R")
source("analysis/series_common.R")

START_YEARS <- 2002:2021
THRESHOLDS <- c(1, 2, 3)
MAIN_THRESHOLD <- 2
TABLE_LAG <- 3
LAGS <- 1:4
ALPHA <- 0.05
SCORES <- c(adjusted = "net_adj", raw = "net")
dir.create(ANALYSIS_DIR, showWarnings = FALSE)

passages <- load_scored_passages() %>%
  filter(source %in% c("mfa", "presdocs")) %>%
  mutate(week = as.Date(cut(as.Date(date), "week", start.on.monday = TRUE)))

# One row per calendar week, from the first week both sides have data to the last, with each
# side's weekly value and document count. A week with no document has count 0 and value NA.
weekly_grid <- function(score) {
  w <- passages %>%
    group_by(source, week, group) %>%
    summarise(value = mean(.data[[score]]), .groups = "drop") %>%
    group_by(source, week) %>%
    summarise(value = mean(value), documents = n(), .groups = "drop") %>%
    pivot_wider(names_from = source, values_from = c(value, documents))
  first <- max(min(w$week[!is.na(w$value_mfa)]), min(w$week[!is.na(w$value_presdocs)]))
  tibble(week = seq(first, max(w$week), by = "week")) %>%
    left_join(w, by = "week") %>%
    mutate(across(starts_with("documents_"), ~ coalesce(.x, 0L)))
}

# The tested series at threshold N: weeks below N on a side are missing on that side.
thresholded <- function(grid, n, difference) {
  d <- grid %>%
    transmute(week,
              china = if_else(documents_mfa >= n, value_mfa, NA_real_),
              us = if_else(documents_presdocs >= n, value_presdocs, NA_real_))
  if (difference) d <- mutate(d, china = china - lag(china), us = us - lag(us))
  d
}

results <- list()
coverage <- list()
for (score_name in names(SCORES)) {
  grid <- weekly_grid(SCORES[[score_name]])
  for (n in THRESHOLDS) {
    if (score_name == "adjusted") {
      coverage[[length(coverage) + 1]] <- grid %>%
        mutate(year = as.integer(format(week, "%Y"))) %>%
        group_by(year) %>%
        summarise(min_docs = n, weeks = n(),
                  kept_china = sum(documents_mfa >= n), kept_us = sum(documents_presdocs >= n),
                  kept_both = sum(documents_mfa >= n & documents_presdocs >= n), .groups = "drop")
    }
    for (transformation in c("differences", "levels")) {
      series <- thresholded(grid, n, transformation == "differences")
      for (start in START_YEARS) {
        window <- filter(series, week >= as.Date(sprintf("%d-01-01", start)))
        for (k in LAGS) {
          cn_us <- granger_calendar(window$china, window$us, k)
          us_cn <- granger_calendar(window$us, window$china, k)
          results[[length(results) + 1]] <- tibble(
            score = score_name, transformation = transformation, min_docs = n,
            start_year = start, first_week = min(window$week), lag = k,
            weeks_used = cn_us[["n"]],  # the same rows enter both directions
            china_to_us = cn_us[["p"]], us_to_china = us_cn[["p"]])
        }
      }
    }
  }
}
results <- bind_rows(results)
coverage <- bind_rows(coverage)
write_csv(results, file.path(ANALYSIS_DIR, "05b_granger_weekly.csv"))
write_csv(coverage, file.path(ANALYSIS_DIR, "05b_weekly_coverage.csv"))

# ---- Paper table -------------------------------------------------------------------

fmt_p <- function(p) {
  s <- ifelse(is.na(p), "--", ifelse(p < 0.001, formatC(p, format = "e", digits = 1), sprintf("%.3f", p)))
  s <- sub("e-0?(\\d+)$", "$\\\\times 10^{-\\1}$", s)
  ifelse(!is.na(p) & p < ALPHA, paste0("\\textbf{", s, "}"), s)
}

table_results <- results %>%
  filter(score == "adjusted", transformation == "differences", lag == TABLE_LAG)

rows <- vapply(START_YEARS, function(start) {
  d <- filter(table_results, start_year == start)
  label <- if (start == min(START_YEARS)) sprintf("%s (all)", format(d$first_week[1], "%b %Y")) else start
  cells <- vapply(THRESHOLDS, function(n) {
    r <- filter(d, min_docs == n)
    sprintf("%d & %s & %s", as.integer(r$weeks_used), fmt_p(r$china_to_us), fmt_p(r$us_to_china))
  }, character(1))
  paste0(label, " & ", paste(cells, collapse = " && "), " \\\\")
}, character(1))

header_n <- vapply(THRESHOLDS, function(n) {
  sprintf("\\multicolumn{3}{c}{$N = %d$%s}", n, if (n == MAIN_THRESHOLD) " (main)" else "")
}, character(1))
cmid <- paste(vapply(seq_along(THRESHOLDS), function(i) {
  a <- 2 + 4 * (i - 1)
  sprintf("\\cmidrule(l{2pt}r{2pt}){%d-%d}", a, a + 2)
}, character(1)), collapse = " ")

tex <- c(
  "% Generated by analysis/05b_forward_dated_granger_weekly.R; do not edit by hand.",
  "% Needs \\usepackage{booktabs} and \\usepackage{threeparttable} in the preamble.",
  "\\begin{table}[htbp]",
  "\\centering",
  "\\small",
  "\\begin{threeparttable}",
  "\\caption{Weekly Granger tests between the President and the MFA on forward-dated windows}",
  "\\label{tab:granger-weekly}",
  sprintf("\\begin{tabular}{@{}l %s@{}}", paste(rep("rrr", length(THRESHOLDS)), collapse = " c ")),
  "\\toprule",
  paste0(" & ", paste(header_n, collapse = " & & "), " \\\\"),
  cmid,
  paste0("Data from & ", paste(rep("Weeks & China $\\to$ US & US $\\to$ China", length(THRESHOLDS)),
                               collapse = " && "), " \\\\"),
  "\\midrule",
  rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{tablenotes}[flushleft]",
  "\\footnotesize",
  paste0(
    "\\item \\textit{Notes:} Each cell is the $p$-value of an $F$-test that ",
    sprintf("%d lags of one series add nothing to an autoregression of the other. ", TABLE_LAG),
    "China $\\to$ US tests whether the MFA's past stance predicts the President's; US $\\to$ China the reverse. ",
    "Each row uses all weeks from January 1 of the year shown to December 2025. ",
    "Stance is the fine-tuned transformer's net stance toward the other country (spec D) with ",
    "spokesperson and genre effects removed, averaged from passages to documents to calendar weeks ",
    "(Monday to Sunday), and first-differenced. ",
    "A side's week is missing if it has fewer than $N$ documents. Missing weeks are not filled: ",
    "a week enters only if it and every week its lags use were observed on both sides, so each lag ",
    "is one calendar week. Weeks is the number that enter. ",
    "Before 2011 the MFA held two press conferences a week, and the President's median is one document a week, ",
    "so at $N = 2$ and $N = 3$ almost every qualifying week falls after 2016 and the earlier windows barely differ. ",
    sprintf("Bold: $p < %.2f$. The windows are nested and the tests are not corrected for multiplicity, ", ALPHA),
    "so the rows are not independent evidence."
  ),
  "\\end{tablenotes}",
  "\\end{threeparttable}",
  "\\end{table}"
)
writeLines(tex, file.path(ANALYSIS_DIR, "05b_table_granger_weekly.tex"))

# ---- Console summary ---------------------------------------------------------------

cat("== Weeks kept, all years ==\n")
print(as.data.frame(coverage %>% group_by(min_docs) %>%
  summarise(weeks = sum(weeks), kept_china = sum(kept_china), kept_us = sum(kept_us),
            kept_both = sum(kept_both))))
cat("\n== Table: adjusted, differences, lag", TABLE_LAG, "==\n")
print(as.data.frame(table_results %>% select(min_docs, start_year, weeks_used, china_to_us, us_to_china) %>%
  mutate(across(c(china_to_us, us_to_china), ~ signif(.x, 2)))), row.names = FALSE)
cat("\n== Smallest p-value per direction, every specification ==\n")
for (dir in c("china_to_us", "us_to_china")) {
  print(as.data.frame(results %>% slice_min(.data[[dir]], n = 5) %>%
    select(score, transformation, min_docs, start_year, lag, weeks_used, all_of(dir))))
}
cat("\n== Share of tests with p < .05 ==\n")
print(as.data.frame(results %>% group_by(score, transformation, min_docs) %>%
  summarise(tests = 2 * n(), share_cn_us = mean(china_to_us < ALPHA, na.rm = TRUE),
            share_us_cn = mean(us_to_china < ALPHA, na.rm = TRUE), .groups = "drop")))
