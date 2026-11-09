# How good is the measurement, period by period, in the two main series: MFA (China) and the
# President (US)? Briefings are computed too, for the CSVs, but left out of the table.
#
# Accuracy can't be estimated month by month: the labeled on-target passages (397 MFA, 263
# President) spread over about 280 months leave about one per corpus-month. So the table has
# two panels:
#   A. Stance accuracy by administration: labeled held-out passages that are about the target.
#   B. Split-half reliability of the monthly series: needs no labels, so it uses every passage.
#      Each month's documents are split at random into two halves, each half is aggregated
#      the way the series will be (passages -> document mean -> monthly mean), and the two
#      half-series are correlated across months. Spearman-Brown scales that up to the full
#      series. This measures how much of the series is noise from which documents happened
#      to fall in a month plus random scoring error. It does not catch scoring error that
#      both halves share, which panel A and 01_series_bias.csv cover.
#
# Why it matters: when one series in a Granger test is noisier, the cleaner one can appear to
# lead it even when it doesn't. Reliability of month-to-month changes matters most, since the
# lead-lag tests work on differenced series.
#
# In:  build/01_labels.csv, build/04_spec_b_oof.csv, build/05_spec_d_oof.csv,
#      build/01_units.csv, build/02_relevance_scores.csv, build/05_spec_d_scores.csv
# Out: analysis/02_accuracy_by_period.csv     stance accuracy by source and administration
#      analysis/02_reliability_by_period.csv  monthly-series reliability, same grid
#      analysis/02_table_measurement.tex      the paper table (needs booktabs, threeparttable)

source("config.R")
source("analysis/series_common.R")

set.seed(20261108)
N_BOOT <- 1000
N_SPLITS <- 200
STANCE_CLASSES <- c("neg", "neutral", "pos")
dir.create(ANALYSIS_DIR, showWarnings = FALSE)

# ---- Panel A: accuracy by administration -------------------------------------------

macro_f1 <- function(truth, pred) {
  f1 <- vapply(STANCE_CLASSES, function(k) {
    tp <- sum(truth == k & pred == k)
    denom <- sum(truth == k) + sum(pred == k)
    if (denom == 0) NA_real_ else 2 * tp / denom
  }, numeric(1))
  mean(f1, na.rm = TRUE)
}

labeled <- read_build("01_labels.csv") %>%
  filter(in_frame, about_target == "yes") %>%
  select(sample_id, source, date, stance3)

predictions <- bind_rows(
  read_build("05_spec_d_oof.csv") %>% transmute(sample_id, spec = "D: Transformer", pred_stance),
  read_build("04_spec_b_oof.csv") %>% transmute(sample_id, spec = "B: TF-IDF", pred_stance)
)

accuracy <- labeled %>%
  inner_join(predictions, by = "sample_id") %>%
  mutate(period = administration(date)) %>%
  with_all() %>%
  group_by(spec, source, period) %>%
  group_modify(~ {
    correct <- .x$stance3 == .x$pred_stance
    boot <- replicate(N_BOOT, mean(sample(correct, replace = TRUE)))
    tibble(n = nrow(.x), accuracy = mean(correct),
           accuracy_lo = quantile(boot, .025), accuracy_hi = quantile(boot, .975),
           majority_baseline = max(table(.x$stance3)) / nrow(.x),
           macro_f1 = macro_f1(.x$stance3, .x$pred_stance))
  }) %>%
  ungroup() %>%
  mutate(period = factor(period, PERIODS)) %>%
  arrange(spec, source, period)
write_csv(accuracy, file.path(ANALYSIS_DIR, "02_accuracy_by_period.csv"))

# ---- Panel B: split-half reliability of the monthly series -------------------------

documents <- document_means(load_kept_passages(), "net")

month_sizes <- documents %>%
  group_by(source, month) %>%
  summarise(docs = n(), passages = sum(passages), .groups = "drop") %>%
  mutate(period = administration(month))

reliability <- split_half_reliability(documents, N_SPLITS) %>%
  left_join(
    month_sizes %>% with_all() %>% group_by(source, period) %>%
      summarise(months = n(), docs_per_month = mean(docs), passages_per_month = mean(passages),
                .groups = "drop"),
    by = c("source", "period")
  ) %>%
  mutate(period = factor(period, PERIODS)) %>%
  arrange(source, period) %>%
  relocate(months, docs_per_month, passages_per_month, .after = period)
write_csv(reliability, file.path(ANALYSIS_DIR, "02_reliability_by_period.csv"))

# ---- LaTeX table -------------------------------------------------------------------

# Political-science style: no leading zero, a real minus sign, an em dash for empty cells.
num <- function(x, digits = 2) {
  out <- formatC(abs(x), format = "f", digits = digits)
  out <- sub("^0\\.", ".", out)
  out <- if_else(x < 0 & round(abs(x), digits) > 0, paste0("$-$", out), out)
  if_else(is.na(x), "---", out)
}
count <- function(x) formatC(round(x), format = "d", big.mark = ",")

ROW_LABELS <- c("Bush" = "Bush (2002--2008)", "Obama" = "Obama (2009--2016)",
                "Trump I" = "Trump I (2017--2020)", "Biden" = "Biden (2021--2024)",
                "Trump II" = "Trump II (2025)", "All years" = "All years")

cells_a <- function(src) {
  d <- accuracy %>% filter(spec == "D: Transformer", source == src)
  setNames(paste(count(d$n), num(d$accuracy), num(d$majority_baseline), num(d$macro_f1), sep = " & "),
           as.character(d$period))
}
cells_b <- function(src) {
  d <- reliability %>% filter(source == src)
  setNames(paste(count(d$months), num(d$passages_per_month, 1), num(d$reliability_levels),
                 num(d$reliability_changes), sep = " & "),
           as.character(d$period))
}

panel_rows <- function(china, us) {
  rows <- vapply(PERIODS, function(p) {
    sprintf("%s & %s && %s \\\\", ROW_LABELS[[p]], china[[p]], us[[p]])
  }, character(1))
  c(rows[1:5], "\\addlinespace", rows[6])
}

trump2_n <- accuracy %>% filter(spec == "D: Transformer", period == "Trump II", source == "presdocs") %>% pull(n)

tex <- c(
  "% Generated by analysis/02_measurement_by_period.R; do not edit by hand.",
  "% Needs \\usepackage{booktabs} and \\usepackage{threeparttable} in the preamble.",
  "\\begin{table}[htbp]",
  "\\centering",
  "\\small",
  "\\begin{threeparttable}",
  "\\caption{Measurement quality by period: Chinese and US corpora}",
  "\\label{tab:measurement-by-period}",
  "\\begin{tabular}{@{}l rrrr c rrrr@{}}",
  "\\toprule",
  " & \\multicolumn{4}{c}{China: MFA press conferences} & & \\multicolumn{4}{c}{US: President} \\\\",
  "\\cmidrule(l{2pt}r{2pt}){2-5} \\cmidrule(l{2pt}r{2pt}){7-10}",
  "\\multicolumn{10}{@{}l}{\\textit{A. Stance classification, held-out labeled passages}} \\\\",
  " & $n$ & Accuracy & Baseline & Macro-F1 & & $n$ & Accuracy & Baseline & Macro-F1 \\\\",
  "\\midrule",
  panel_rows(cells_a("mfa"), cells_a("presdocs")),
  "\\midrule",
  "\\multicolumn{10}{@{}l}{\\textit{B. Split-half reliability of the monthly series}} \\\\",
  " & Months & Passages & Levels & Changes & & Months & Passages & Levels & Changes \\\\",
  "\\midrule",
  panel_rows(cells_b("mfa"), cells_b("presdocs")),
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{tablenotes}[flushleft]",
  "\\footnotesize",
  paste0(
    "\\item \\textit{Notes:} Stance is scored by the fine-tuned transformer (spec D). ",
    "Panel A uses passages labeled as about the other country, each predicted by a model that ",
    "did not train on it (five-fold cross-fitting). Accuracy is the share of passages whose ",
    "predicted stance (negative, neutral or mixed, positive) matches the label; Baseline is the ",
    "share in the most common class; Macro-F1 averages the F1 of the three classes. ",
    sprintf("Trump II has only %d labeled presidential passages, so its row is uninformative. ", trump2_n),
    "Panel B uses every passage in the frame that the relevance filter keeps. Each month's ",
    "documents are split at random into halves, each half is averaged as the series is ",
    "(passages to document means to a monthly mean), and the halves are correlated across ",
    "months; Spearman--Brown scales the correlation to the full series, and the result is ",
    sprintf("averaged over %d random splits. ", N_SPLITS),
    "Levels uses the monthly values; Changes uses month-to-month differences, the input to the ",
    "lead--lag tests. Months counts months with at least one document; reliability uses months ",
    "with two or more. Passages is the mean number per month. Levels for All years include ",
    "differences between administrations, so they are higher than any single period. ",
    "Terms begin January 20."
  ),
  "\\end{tablenotes}",
  "\\end{threeparttable}",
  "\\end{table}"
)
writeLines(tex, file.path(ANALYSIS_DIR, "02_table_measurement.tex"))

# ---- Console summary ---------------------------------------------------------------

round_all <- function(d) as.data.frame(mutate(d, across(where(is.numeric), ~ round(.x, 3))))
cat("== Accuracy by period, spec D ==\n")
print(round_all(filter(accuracy, spec == "D: Transformer") %>% select(-spec)))
cat("\n== Reliability by period ==\n")
print(round_all(reliability))
