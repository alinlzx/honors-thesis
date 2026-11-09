# Compare sentiment specs A, B and D on held-out labeled rows, in three layers:
#   relevance    all rows: about the target or not (transformer used by B and D)
#   stance       rows labeled about the target: the stance model on its own
#   end_to_end   all rows, four outcomes: what actually feeds the series. An off-target row is
#                right only if filtered out; an on-target row wrongly filtered is an error.
#
# In:  build/01_labels.csv, build/02_relevance_oof.csv, build/03_spec_a_labeled.csv,
#      build/04_spec_b_oof.csv, build/05_spec_d_oof.csv
#      build/01_units.csv, build/02_relevance_scores.csv, build/05_spec_d_scores.csv
# Out: analysis/01_metrics.csv           accuracy, F1 and baseline, by layer, spec, source
#      analysis/01_spec_differences.csv  paired bootstrap differences between specs
#      analysis/01_auc.csv               one-vs-rest AUC
#      analysis/01_confusion.csv         confusion counts, by layer, spec, source
#      analysis/01_series_bias.csv       predicted vs labeled net stance by administration
#      analysis/01_series_drift.csv      does prediction error trend over time?
#      analysis/01_filter_cuts.csv       what the relevance filter catches at each cut
#      analysis/01_filter_bound.csv      filtered net stance against a perfect filter
#      analysis/01_filter_series.csv     monthly frame series with and without the filter
#      analysis/01a_confusion_end_to_end.png, 01b_roc_stance.png, 01c_roc_relevance.png
#
# Choices, and why:
# - Rows outside the frame (old thesis rows kept as relevance checks) are not scored: the
#   frame is the population the series covers.
# - Weighted columns use the sampling weights, so they estimate performance on the frame.
#   The sample allocates equally by year, which over-represents thin years.
# - A row is filtered at P(about) <= 0.2: drop only when confident. 0.5 is the sensitivity.
# - Results are also reported for rows first coded by hand (subset = human_coded).

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(tidyr)
})
source("config.R")

set.seed(20261104)
FILTER_CUT <- 0.2
N_BOOT <- 1000
OUTCOMES <- c("off_target", "neg", "neutral", "pos")
SPECS <- c("D: Transformer", "B: TF-IDF", "A: Bing", "A: AFINN")
SOURCES <- c(presdocs = "President", mfa = "MFA", briefings = "Briefings")
dir.create(ANALYSIS_DIR, showWarnings = FALSE)

read_build <- function(f) read_csv(file.path(BUILD_DIR, f), show_col_types = FALSE)

labels <- read_build("01_labels.csv") %>%
  filter(in_frame) %>%
  select(sample_id, source, date, year, weight, human_coded, about_target, stance3, outcome4)
relevance <- read_build("02_relevance_oof.csv")

model_preds <- function(file, spec) {
  read_build(file) %>%
    transmute(sample_id, spec = spec, pred_stance, score_neg = p_neg, score_neutral = p_neutral,
              score_pos = p_pos, net, filtered = TRUE)
}

# A has no filter and no probabilities: its ROC uses the raw lexicon score, and its net
# stance uses the sign, since per-100-word scores aren't on the labels' scale.
lexicon_preds <- function(score, class, spec) {
  read_build("03_spec_a_labeled.csv") %>%
    transmute(sample_id, spec = spec, pred_stance = .data[[class]], score_neg = -.data[[score]],
              score_neutral = -abs(.data[[score]]), score_pos = .data[[score]],
              net = sign(.data[[score]]), filtered = FALSE)
}

preds <- bind_rows(
  model_preds("05_spec_d_oof.csv", "D: Transformer"),
  model_preds("04_spec_b_oof.csv", "B: TF-IDF"),
  lexicon_preds("bing", "bing_class", "A: Bing"),
  lexicon_preds("afinn", "afinn_class", "A: AFINN")
) %>%
  inner_join(labels, by = "sample_id") %>%
  left_join(relevance, by = "sample_id") %>%
  mutate(spec = factor(spec, SPECS))
stopifnot(nrow(preds) == 4 * nrow(labels), !anyNA(preds$p_about), !anyNA(preds$net))

end_to_end <- function(d, cut) if_else(d$filtered & d$p_about <= cut, "off_target", d$pred_stance)

# ---- Metrics -----------------------------------------------------------------------

class_f1 <- function(truth, pred, classes) {
  vapply(classes, function(k) {
    tp <- sum(truth == k & pred == k)
    fp <- sum(truth != k & pred == k)
    fn <- sum(truth == k & pred != k)
    if (tp + fp + fn == 0) NA_real_ else 2 * tp / (2 * tp + fp + fn)
  }, numeric(1))
}

score_set <- function(truth, pred, classes) {
  c(accuracy = mean(truth == pred), macro_f1 = mean(class_f1(truth, pred, classes), na.rm = TRUE))
}

metrics <- function(truth, pred, w, classes) {
  base <- score_set(truth, pred, classes)
  boot <- replicate(N_BOOT, {
    i <- sample.int(length(truth), replace = TRUE)
    score_set(truth[i], pred[i], classes)
  })
  f1 <- class_f1(truth, pred, classes)
  tibble(
    n = length(truth),
    accuracy = base[["accuracy"]],
    accuracy_lo = quantile(boot["accuracy", ], .025), accuracy_hi = quantile(boot["accuracy", ], .975),
    macro_f1 = base[["macro_f1"]],
    macro_f1_lo = quantile(boot["macro_f1", ], .025), macro_f1_hi = quantile(boot["macro_f1", ], .975),
    majority_baseline = max(table(truth)) / length(truth),
    accuracy_weighted = weighted.mean(truth == pred, w),
    majority_baseline_weighted = max(tapply(w, truth, sum)) / sum(w),
    !!!setNames(as.list(f1), paste0("f1_", classes))
  )
}

groups <- function(d) {
  bind_rows(
    d %>% mutate(group = "Pooled", subset = "all"),
    d %>% mutate(group = SOURCES[source], subset = "all"),
    d %>% filter(human_coded) %>% mutate(group = "Pooled", subset = "human_coded"),
    d %>% filter(human_coded) %>% mutate(group = SOURCES[source], subset = "human_coded")
  )
}

e2e <- function(cut) {
  preds %>%
    mutate(truth = outcome4, pred = end_to_end(pick(everything()), cut),
           layer = if_else(cut == FILTER_CUT, "end_to_end", "end_to_end_cut_0.5"))
}

stance_rows <- preds %>%
  filter(about_target == "yes") %>%
  mutate(truth = stance3, pred = pred_stance, layer = "stance")

# The relevance model is the same across specs, so it has one row of results at each cut.
relevance_rows <- function(cut, name) {
  preds %>%
    filter(spec == "D: Transformer") %>%
    mutate(spec = factor("Relevance model", c(SPECS, "Relevance model")), truth = about_target,
           pred = if_else(p_about <= cut, "no", "yes"), layer = name)
}

all_rows <- bind_rows(
  relevance_rows(FILTER_CUT, "relevance"), relevance_rows(0.5, "relevance_cut_0.5"),
  stance_rows, e2e(FILTER_CUT), e2e(0.5)
)

metric_table <- groups(all_rows) %>%
  group_by(layer, spec, group, subset) %>%
  group_modify(~ {
    classes <- if (startsWith(.y$layer, "relevance")) c("no", "yes")
    else if (.y$layer == "stance") c("neg", "neutral", "pos")
    else OUTCOMES
    metrics(.x$truth, .x$pred, .x$weight, classes)
  }) %>%
  ungroup() %>%
  arrange(layer, subset, group, spec)
write_csv(metric_table, file.path(ANALYSIS_DIR, "01_metrics.csv"))

confusion <- groups(all_rows) %>%
  count(layer, spec, group, subset, truth, pred)
write_csv(confusion, file.path(ANALYSIS_DIR, "01_confusion.csv"))

# Paired, because the specs are scored on the same rows: their separate intervals can overlap
# even when one reliably beats the other.
paired_difference <- function(d, a, b, classes) {
  gap <- function(i) {
    score_set(d$truth[i], d[[a]][i], classes) - score_set(d$truth[i], d[[b]][i], classes)
  }
  obs <- gap(seq_len(nrow(d)))
  boot <- replicate(N_BOOT, gap(sample.int(nrow(d), replace = TRUE)))
  tibble(
    comparison = paste(a, "minus", b), n = nrow(d),
    accuracy = obs[["accuracy"]],
    accuracy_lo = quantile(boot["accuracy", ], .025), accuracy_hi = quantile(boot["accuracy", ], .975),
    macro_f1 = obs[["macro_f1"]],
    macro_f1_lo = quantile(boot["macro_f1", ], .025), macro_f1_hi = quantile(boot["macro_f1", ], .975)
  )
}

spec_differences <- all_rows %>%
  filter(layer %in% c("stance", "end_to_end")) %>%
  select(sample_id, source, human_coded, layer, spec, truth, pred) %>%
  mutate(spec = as.character(spec)) %>%
  pivot_wider(names_from = spec, values_from = pred) %>%
  groups() %>%
  filter(subset == "all") %>%
  group_by(layer, group) %>%
  group_modify(~ {
    classes <- if (.y$layer == "stance") c("neg", "neutral", "pos") else OUTCOMES
    bind_rows(
      paired_difference(.x, "D: Transformer", "B: TF-IDF", classes),
      paired_difference(.x, "D: Transformer", "A: AFINN", classes),
      paired_difference(.x, "B: TF-IDF", "A: AFINN", classes)
    )
  }) %>%
  ungroup()
write_csv(spec_differences, file.path(ANALYSIS_DIR, "01_spec_differences.csv"))

# ---- AUC and ROC -------------------------------------------------------------------

auc <- function(positive, score) {
  n1 <- sum(positive)
  n0 <- sum(!positive)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  (sum(rank(score)[positive]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

roc_points <- function(positive, score) {
  tibble(score, positive) %>%
    group_by(score) %>%
    summarise(tp = sum(positive), fp = sum(!positive), .groups = "drop") %>%
    arrange(desc(score)) %>%
    transmute(tpr = cumsum(tp) / sum(positive), fpr = cumsum(fp) / sum(!positive)) %>%
    bind_rows(tibble(tpr = 0, fpr = 0), .)
}

stance_long <- stance_rows %>%
  pivot_longer(c(score_neg, score_neutral, score_pos), names_to = "class", names_prefix = "score_",
               values_to = "score") %>%
  mutate(positive = stance3 == class)
relevance_long <- preds %>%
  filter(spec == "D: Transformer") %>%
  transmute(sample_id, source, human_coded, spec = "Relevance model", class = "off_target",
            score = 1 - p_about, positive = about_target == "no")

auc_table <- bind_rows(
  mutate(stance_long, layer = "stance", spec = as.character(spec)),
  mutate(relevance_long, layer = "relevance")
) %>%
  groups() %>%
  group_by(layer, spec, class, group, subset) %>%
  summarise(n = n(), auc = auc(positive, score), .groups = "drop")
write_csv(auc_table, file.path(ANALYSIS_DIR, "01_auc.csv"))

# ---- Series-level checks -----------------------------------------------------------

label_value <- c(neg = -1, neutral = 0, pos = 1)
admin <- function(date) {
  cut(as.Date(date), as.Date(c("2001-01-20", "2009-01-20", "2017-01-20", "2021-01-20", "2025-01-20", "2030-01-01")),
      labels = c("Bush", "Obama", "Trump I", "Biden", "Trump II"), right = FALSE)
}

series_rows <- preds %>%
  mutate(
    administration = admin(date),
    kept = !(filtered & p_about <= FILTER_CUT),
    label_net = label_value[stance3]
  )

# Each side averages the rows it would put in a series: labeled on-target rows on one side,
# rows the spec keeps on the other.
series_bias <- series_rows %>%
  group_by(spec, source, administration) %>%
  summarise(
    n_labeled = sum(about_target == "yes"),
    labeled_net = weighted.mean(label_net[about_target == "yes"], weight[about_target == "yes"]),
    predicted_net = weighted.mean(net[kept], weight[kept]),
    .groups = "drop"
  ) %>%
  mutate(bias = predicted_net - labeled_net)
write_csv(series_bias, file.path(ANALYSIS_DIR, "01_series_bias.csv"))

series_drift <- series_rows %>%
  filter(about_target == "yes", kept) %>%
  mutate(error = net - label_net, decade = (year - 2013) / 10) %>%
  group_by(spec, source) %>%
  group_modify(~ {
    fit <- lm(error ~ decade, data = .x)
    ci <- confint(fit)["decade", ]
    # A compressed score errs upward when labels fall. Holding the label fixed removes that,
    # so what remains is drift in how the same stance gets scored.
    given_label <- lm(error ~ decade + label_net, data = .x)
    ci_given <- confint(given_label)["decade", ]
    tibble(n = nrow(.x), mean_error = mean(.x$error),
           label_trend_per_decade = coef(lm(label_net ~ decade, data = .x))[["decade"]],
           slope_per_decade = coef(fit)[["decade"]], slope_lo = ci[[1]], slope_hi = ci[[2]],
           slope_given_label = coef(given_label)[["decade"]],
           slope_given_label_lo = ci_given[[1]], slope_given_label_hi = ci_given[[2]],
           corr_pred_label = cor(.x$net, .x$label_net))
  }) %>%
  ungroup()
write_csv(series_drift, file.path(ANALYSIS_DIR, "01_series_drift.csv"))

# ---- Does the relevance filter matter? ---------------------------------------------

filter_rows <- filter(series_rows, spec == "D: Transformer")

filter_cuts <- bind_rows(lapply(c(0.2, 0.5, 0.8, 0.9, 0.95, 0.98, 0.99), function(cut) {
  drop <- filter_rows$p_about <= cut
  off <- filter_rows$about_target == "no"
  tibble(cut, dropped = sum(drop), off_target_caught = sum(drop & off),
         precision = sum(drop & off) / sum(drop), recall = sum(drop & off) / sum(off),
         on_target_lost = sum(drop & !off) / sum(!off))
}))
write_csv(filter_cuts, file.path(ANALYSIS_DIR, "01_filter_cuts.csv"))

# The bound: on labeled rows a perfect filter keeps exactly the on-target rows, so its gap from
# no filter is the most any better relevance model could move net stance.
filter_bound <- filter_rows %>%
  group_by(source, administration) %>%
  summarise(
    n = n(), n_off_target = sum(about_target == "no"),
    perfect_filter = weighted.mean(net[about_target == "yes"], weight[about_target == "yes"]),
    no_filter = weighted.mean(net, weight),
    cut_0.2 = weighted.mean(net[p_about > 0.2], weight[p_about > 0.2]),
    cut_0.5 = weighted.mean(net[p_about > 0.5], weight[p_about > 0.5]),
    .groups = "drop"
  ) %>%
  mutate(no_filter_gap = no_filter - perfect_filter)
write_csv(filter_bound, file.path(ANALYSIS_DIR, "01_filter_bound.csv"))

# Frame-wide, at the frequency the series will use. These are plain monthly means of passages;
# the document-level aggregation in recipes section 4 isn't built yet.
frame <- read_build("01_units.csv") %>%
  select(unit_id, source, date) %>%
  inner_join(select(read_build("05_spec_d_scores.csv"), unit_id, net), by = "unit_id") %>%
  inner_join(select(read_build("02_relevance_scores.csv"), unit_id, p_about), by = "unit_id") %>%
  mutate(month = format(as.Date(date), "%Y-%m"))
stopifnot(nrow(frame) == nrow(read_build("01_units.csv")), !anyNA(frame$month))

filter_series <- bind_rows(lapply(c(0.2, 0.5, 0.98), function(cut) {
  frame %>%
    group_by(source, month) %>%
    summarise(all = mean(net), kept = mean(net[p_about > cut]), .groups = "drop") %>%
    filter(!is.nan(kept)) %>%
    group_by(source) %>%
    summarise(cut, months = n(), corr_levels = cor(all, kept), corr_changes = cor(diff(all), diff(kept)),
              rms_gap = sqrt(mean((all - kept)^2)), .groups = "drop") %>%
    left_join(frame %>% group_by(source) %>% summarise(share_dropped = mean(p_about <= cut)), by = "source")
}))
write_csv(filter_series, file.path(ANALYSIS_DIR, "01_filter_series.csv"))

# ---- Figures -----------------------------------------------------------------------

INK <- "#0b0b0b"
MUTED <- "#52514e"
SPEC_COLORS <- c("D: Transformer" = "#2a78d6", "B: TF-IDF" = "#eb6834",
                 "A: Bing" = "#1baf7a", "A: AFINN" = "#eda100")
theme_paper <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = "#e8e7e3", linewidth = 0.3),
        plot.background = element_rect(fill = "white", color = NA),
        axis.text = element_text(color = MUTED), strip.text = element_text(color = INK, face = "bold"),
        plot.title = element_text(color = INK, face = "bold"), plot.subtitle = element_text(color = MUTED),
        legend.position = "top", legend.justification = "left")

OUTCOME_LABELS <- c(off_target = "Off-target", neg = "Negative", neutral = "Neutral/mixed", pos = "Positive")
confusion_plot <- confusion %>%
  filter(layer == "end_to_end", subset == "all", group == "Pooled") %>%
  mutate(spec = droplevels(spec)) %>%
  complete(spec, truth = OUTCOMES, pred = OUTCOMES, fill = list(n = 0)) %>%
  group_by(spec, truth) %>%
  mutate(share = n / sum(n)) %>%
  ungroup() %>%
  mutate(truth = factor(OUTCOME_LABELS[truth], rev(OUTCOME_LABELS)),
         pred = factor(OUTCOME_LABELS[pred], OUTCOME_LABELS),
         label = sprintf("%d\n%.0f%%", n, 100 * share))
p <- ggplot(confusion_plot, aes(pred, truth, fill = share)) +
  geom_tile(color = "white", linewidth = 1) +
  geom_text(aes(label = label, color = share > 0.55), size = 2.9, lineheight = 0.9, show.legend = FALSE) +
  scale_color_manual(values = c(`TRUE` = "white", `FALSE` = INK)) +
  scale_fill_gradient(low = "#f1f6fd", high = "#1c5cab", limits = c(0, 1), labels = scales::percent) +
  facet_wrap(~spec, nrow = 2) +
  labs(title = "End-to-end confusion on held-out rows",
       subtitle = "Count and share of each labeled outcome. A has no relevance filter, so it never predicts off-target.",
       x = "Predicted", y = "Labeled", fill = "Share of row") +
  theme_paper +
  theme(panel.grid.major = element_blank(), axis.text.x = element_text(angle = 25, hjust = 1))
ggsave(file.path(ANALYSIS_DIR, "01a_confusion_end_to_end.png"), p, width = 8.5, height = 7.5, dpi = 200)

# ROC curves are drawn as paths, not steps: tied scores (common for the lexicons) then run
# diagonally, so the area under the drawn curve equals the reported AUC.
ROC_AXES <- list(scale_x_continuous(breaks = c(0, 0.5, 1), labels = c("0", "0.5", "1")),
                 scale_y_continuous(breaks = c(0, 0.5, 1), labels = c("0", "0.5", "1")))
CLASS_LABELS <- c(neg = "Negative vs. rest", neutral = "Neutral/mixed vs. rest", pos = "Positive vs. rest")
roc_stance <- stance_long %>%
  group_by(spec, class) %>%
  group_modify(~ roc_points(.x$positive, .x$score)) %>%
  ungroup() %>%
  mutate(class = factor(CLASS_LABELS[class], CLASS_LABELS))
auc_labels <- auc_table %>%
  filter(layer == "stance", subset == "all", group == "Pooled") %>%
  mutate(class = factor(CLASS_LABELS[class], CLASS_LABELS), spec = factor(spec, SPECS)) %>%
  arrange(class, spec) %>%
  group_by(class) %>%
  summarise(label = paste(sprintf("%s  %.2f", spec, auc), collapse = "\n"), .groups = "drop")
p <- ggplot(roc_stance, aes(fpr, tpr, color = spec)) +
  geom_abline(color = "#b5b4ae", linetype = "dashed", linewidth = 0.4) +
  geom_path(linewidth = 0.7) +
  geom_text(data = auc_labels, aes(x = 1, y = 0.03, label = label), inherit.aes = FALSE,
            hjust = 1, vjust = 0, size = 2.7, color = INK, lineheight = 1) +
  scale_color_manual(values = SPEC_COLORS, name = NULL) +
  ROC_AXES +
  coord_equal() +
  facet_wrap(~class) +
  labs(title = "Stance ROC on held-out rows about the target",
       subtitle = "AUC beside each spec. Lexicons use the raw score; B and D use class probabilities.",
       x = "False positive rate", y = "True positive rate") +
  theme_paper
ggsave(file.path(ANALYSIS_DIR, "01b_roc_stance.png"), p, width = 9, height = 3.9, dpi = 200)

roc_relevance <- groups(relevance_long) %>%
  filter(subset == "all") %>%
  group_by(group) %>%
  group_modify(~ roc_points(.x$positive, .x$score)) %>%
  ungroup() %>%
  mutate(group = factor(group, c("Pooled", SOURCES)))
relevance_labels <- auc_table %>%
  filter(layer == "relevance", subset == "all") %>%
  mutate(group = factor(group, c("Pooled", SOURCES)), label = sprintf("AUC %.2f\nn = %d", auc, n))
p <- ggplot(roc_relevance, aes(fpr, tpr)) +
  geom_abline(color = "#b5b4ae", linetype = "dashed", linewidth = 0.4) +
  geom_path(linewidth = 0.7, color = "#2a78d6") +
  geom_text(data = relevance_labels, aes(x = 1, y = 0.03, label = label), hjust = 1, vjust = 0,
            size = 2.8, color = INK) +
  ROC_AXES +
  coord_equal() +
  facet_wrap(~group, nrow = 1) +
  labs(title = "Relevance ROC on held-out rows: detecting off-target passages",
       x = "False positive rate", y = "True positive rate") +
  theme_paper
ggsave(file.path(ANALYSIS_DIR, "01c_roc_relevance.png"), p, width = 9, height = 3.1, dpi = 200)

# ---- Console summary ---------------------------------------------------------------

show <- function(l, subset_name = "all") {
  metric_table %>%
    filter(layer == l, subset == subset_name) %>%
    transmute(spec, group, n, acc = round(accuracy, 3), base = round(majority_baseline, 3),
              f1 = round(macro_f1, 3), lo = round(macro_f1_lo, 3), hi = round(macro_f1_hi, 3),
              acc_w = round(accuracy_weighted, 3)) %>%
    as.data.frame() %>%
    print()
}
for (l in unique(metric_table$layer)) { cat("\n==", l, "==\n"); show(l) }
cat("\n== stance, human_coded ==\n"); show("stance", "human_coded")
cat("\n== end_to_end, human_coded ==\n"); show("end_to_end", "human_coded")
round_all <- function(d) as.data.frame(mutate(d, across(where(is.numeric), ~ round(.x, 3))))
cat("\n== Paired differences, pooled ==\n")
print(round_all(filter(spec_differences, group == "Pooled")))
cat("\n== Paired differences, D minus B by source ==\n")
print(round_all(filter(spec_differences, group != "Pooled", comparison == "D: Transformer minus B: TF-IDF")))
cat("\n== Filter: what each cut catches ==\n"); print(round_all(filter_cuts))
cat("\n== Filter: gap from a perfect filter, labeled rows ==\n"); print(round_all(filter_bound))
cat("\n== Filter: monthly frame series, with vs without ==\n"); print(round_all(filter_series))
cat("\n== AUC, pooled ==\n")
print(as.data.frame(filter(auc_table, subset == "all", group == "Pooled") %>% mutate(auc = round(auc, 3))))
cat("\n== Drift ==\n")
print(as.data.frame(mutate(series_drift, across(where(is.numeric), ~ round(.x, 3)))))
