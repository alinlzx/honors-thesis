# Does taking speaker and format composition out of the scores (build/06) change the monthly
# series, and how reliable are the adjusted series?
#
# In:  build/01_units.csv, build/02_relevance_scores.csv, build/05_spec_d_scores.csv,
#      build/06_adjusted_scores.csv, build/06_speaker_effects.csv
# Out: analysis/03_reliability_adjusted.csv  split-half reliability, raw vs adjusted
#      analysis/03_adjustment_effect.csv     how much the adjustment moves each monthly series
#
# Choices, and why:
# - Raw and adjusted reliability use the same random splits (same seed, same documents), so
#   the comparison is paired and differences aren't split-to-split noise.
# - The adjustment can raise reliability as well as lower it. A month's overall speaker mix is
#   shared by both halves (and counts as signal), but which speakers land in which half is
#   random (and counts as noise). For MFA, with one spokesperson per press conference, the
#   second dominates: the adjustment raised reliability (analysis_recipes.md 6.8).
# - composition_share is the share of the variance of month-to-month changes that the
#   adjustment removes: var(raw change - adjusted change) / var(raw change).

source("config.R")
source("analysis/series_common.R")

SEED <- 20261108
N_SPLITS <- 200
dir.create(ANALYSIS_DIR, showWarnings = FALSE)

passages <- load_kept_passages() %>%
  inner_join(select(read_build("06_adjusted_scores.csv"), unit_id, source, speaker, net_06 = net, net_adj),
             by = c("unit_id", "source"))
stopifnot(nrow(passages) == nrow(load_kept_passages()), isTRUE(all.equal(passages$net, passages$net_06)))

# ---- Reliability, raw vs adjusted --------------------------------------------------

reliability <- bind_rows(lapply(c(raw = "net", adjusted = "net_adj"), function(score) {
  set.seed(SEED)
  split_half_reliability(document_means(passages, score), N_SPLITS)
}), .id = "score") %>%
  mutate(period = factor(period, PERIODS)) %>%
  arrange(source, period, score)
write_csv(reliability, file.path(ANALYSIS_DIR, "03_reliability_adjusted.csv"))

# ---- How much the adjustment moves the monthly series ------------------------------

monthly <- passages %>%
  group_by(source, month, group) %>%
  summarise(raw = mean(net), adjusted = mean(net_adj), .groups = "drop") %>%
  group_by(source, month) %>%
  summarise(raw = mean(raw), adjusted = mean(adjusted), .groups = "drop") %>%
  arrange(source, month) %>%
  group_by(source) %>%
  mutate(index = as.integer(format(month, "%Y")) * 12 + as.integer(format(month, "%m")),
         adjacent = coalesce(index - lag(index) == 1, FALSE),
         raw_change = if_else(adjacent, raw - lag(raw), NA_real_),
         adjusted_change = if_else(adjacent, adjusted - lag(adjusted), NA_real_)) %>%
  ungroup() %>%
  mutate(period = administration(month))

adjustment_effect <- monthly %>%
  with_all() %>%
  group_by(source, period) %>%
  summarise(
    months = n(),
    corr_levels = cor(raw, adjusted),
    corr_changes = cor(raw_change, adjusted_change, use = "complete.obs"),
    composition_share = var(raw_change - adjusted_change, na.rm = TRUE) / var(raw_change, na.rm = TRUE),
    rms_gap = sqrt(mean((raw - adjusted)^2)),
    .groups = "drop"
  ) %>%
  mutate(period = factor(period, PERIODS)) %>%
  arrange(source, period)
write_csv(adjustment_effect, file.path(ANALYSIS_DIR, "03_adjustment_effect.csv"))

# ---- Console summary ---------------------------------------------------------------

round_all <- function(d) as.data.frame(mutate(d, across(where(is.numeric), ~ round(.x, 3))))
cat("== Speaker effects: share of within-month variance, joint test ==\n")
print(round_all(read_csv(file.path(BUILD_DIR, "06_speaker_effects.csv"), show_col_types = FALSE) %>%
                  distinct(source, partial_r2, joint_f, joint_p)))
cat("\n== Reliability, raw vs adjusted ==\n")
print(round_all(reliability %>%
                  select(source, period, score, reliability_levels, reliability_changes) %>%
                  pivot_wider(names_from = score, values_from = c(reliability_levels, reliability_changes))))
cat("\n== How much the adjustment moves the series ==\n")
print(round_all(adjustment_effect))
