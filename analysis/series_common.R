# Shared pieces for the series analyses: periods, the relevance cut, the kept passages, and
# split-half reliability. Source after config.R, from the repo root.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
})

FILTER_CUT <- 0.2   # passages at or below it leave the series (analysis_recipes.md 6.3)
PERIODS <- c("Bush", "Obama", "Trump I", "Biden", "Trump II", "All years")

read_build <- function(f) read_csv(file.path(BUILD_DIR, f), show_col_types = FALSE,
                                   col_types = cols(unit_id = col_character()))

# Terms start January 20; a passage dated that day belongs to the incoming president.
administration <- function(date) {
  as.character(cut(as.Date(date),
                   as.Date(c("2001-01-20", "2009-01-20", "2017-01-20", "2021-01-20", "2025-01-20", "2030-01-01")),
                   labels = PERIODS[1:5], right = FALSE))
}

# Every row once in its administration and once in "All years".
with_all <- function(d) bind_rows(d, mutate(d, period = "All years"))

# Passages the relevance filter keeps, with spec D's net stance and their month.
load_kept_passages <- function() {
  read_build("01_units.csv") %>%
    select(unit_id, source, group, date) %>%
    inner_join(select(read_build("05_spec_d_scores.csv"), unit_id, net), by = "unit_id") %>%
    inner_join(select(read_build("02_relevance_scores.csv"), unit_id, p_about), by = "unit_id") %>%
    filter(p_about > FILTER_CUT) %>%
    mutate(month = as.Date(format(as.Date(date), "%Y-%m-01")))
}

# Passages to document means (a speech, a press conference, a briefing), for one score column.
document_means <- function(passages, score) {
  passages %>%
    group_by(source, month, group) %>%
    summarise(value = mean(.data[[score]]), passages = n(), .groups = "drop")
}

# Split-half reliability of the monthly series, by source and period. Each month's documents
# are split at random into halves; each half's monthly value is the mean of its documents; the
# halves are correlated across months, in levels and in month-to-month changes, and
# Spearman-Brown scales the correlation to the full series. Months need two documents to split,
# and a change is kept only between adjacent calendar months. Averaged over n_splits draws.
split_half_reliability <- function(documents, n_splits) {
  split_once <- function() {
    documents %>%
      group_by(source, month) %>%
      filter(n() >= 2) %>%
      mutate(half = if_else(rank(runif(n())) %% 2 == 0, "a", "b")) %>%
      group_by(source, month, half) %>%
      summarise(value = mean(value), .groups = "drop") %>%
      pivot_wider(names_from = half, values_from = value) %>%
      arrange(source, month) %>%
      group_by(source) %>%
      mutate(index = as.integer(format(month, "%Y")) * 12 + as.integer(format(month, "%m")),
             adjacent = coalesce(index - lag(index) == 1, FALSE),
             change_a = if_else(adjacent, a - lag(a), NA_real_),
             change_b = if_else(adjacent, b - lag(b), NA_real_)) %>%
      ungroup() %>%
      mutate(period = administration(month)) %>%
      with_all() %>%
      group_by(source, period) %>%
      summarise(months = n(), r_levels = cor(a, b),
                changes = sum(!is.na(change_a)), r_changes = cor(change_a, change_b, use = "complete.obs"),
                .groups = "drop")
  }
  spearman_brown <- function(r) 2 * r / (1 + r)

  bind_rows(replicate(n_splits, split_once(), simplify = FALSE)) %>%
    group_by(source, period) %>%
    summarise(months_split = first(months), changes = first(changes),
              r_half_levels = mean(r_levels), r_half_changes = mean(r_changes), .groups = "drop") %>%
    mutate(reliability_levels = spearman_brown(r_half_levels),
           reliability_changes = spearman_brown(r_half_changes))
}
