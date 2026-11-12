# 07-08 — Thesis Figures 7 (China) and 8 (US): diagnostics of the hybrid
# sentiment score, for each of the three train-test approaches.
#
# ROC curves: one-vs-rest curves for positive, negative and ambiguous documents,
# with the hybrid score as the predictor (pROC defaults, as in the 2023 notebook).
# Confusion matrices: 3x3, with the hybrid score cut into N/O/P at quantiles that
# match the hand-coded class shares (create_cm() in sentiments/functions.R). The
# thesis showed only the 2x2 positive/negative matrix for approach 2.
# Both use the same evaluation sets as the statistics in 0X_metrics.csv.
#
# Input:  honors-thesis-original-data/sentiments/0X_test_predictions.csv, 0X_metrics.csv
# Output: figures/output/07_china_roc.pdf, 07_china_confusion.pdf,
#         figures/output/08_us_roc.pdf,    08_us_confusion.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

eval_sets <- read_eval_sets()
groups <- split(eval_sets, list(eval_sets$approach, eval_sets$country), drop = TRUE)

# ---- ROC curves -------------------------------------------------------------------
roc_curves <- bind_rows(lapply(groups, function(df) {
  bind_rows(lapply(names(CLASS_LABELS), function(cls) {
    r <- roc(ifelse(df$senti_label == cls, 1, 0), df$hybrid, quiet = TRUE)
    pts <- coords(r, "all", ret = c("specificity", "sensitivity"), transpose = FALSE)
    tibble(approach = df$approach[1], country = df$country[1], class = CLASS_LABELS[[cls]],
           fpr = c(0, 1 - pts$specificity, 1), tpr = c(0, pts$sensitivity, 1),
           auc = as.numeric(auc(r))) %>%
      arrange(fpr, tpr)
  }))
}))

# ---- Confusion matrices ----------------------------------------------------------------
confusion <- bind_rows(lapply(groups, function(df) {
  cm <- create_cm(as.data.frame(df))
  as.data.frame(cm$table) %>%
    transmute(approach = df$approach[1], country = df$country[1],
              predicted = CLASS_LABELS[as.character(hybrid)], actual = CLASS_LABELS[as.character(Var2)],
              n = Freq, accuracy = cm$overall[["Accuracy"]])
}))

# Check: the figures reproduce the statistics in 0X_metrics.csv (and the Table 6 export).
metrics <- bind_rows(lapply(names(APPROACHES), function(a) {
  read_csv(out_path(paste0(a, "_metrics.csv")), show_col_types = FALSE,
           col_types = cols(approach = col_character()))
}))
check <- bind_rows(
  confusion %>% distinct(approach, country, value = accuracy) %>%
    inner_join(filter(metrics, metric == "accuracy_3class"), by = c("approach", "country")),
  roc_curves %>% distinct(approach, country, class, value = auc) %>%
    mutate(class = names(CLASS_LABELS)[match(class, CLASS_LABELS)]) %>%
    inner_join(filter(metrics, metric == "auc"), by = c("approach", "country", "class"))
)
# AUCs can differ in the third decimal: near-tied hybrid scores (differences of
# ~1e-17) are rounded into ties here, which changes how a few pairs are counted.
stopifnot(nrow(check) == 24, max(abs(check$value.x - check$value.y)) < 0.005)

# ---- Plots ---------------------------------------------------------------------------------
facet_labels <- function(df) factor(APPROACHES[df$approach], levels = APPROACHES)

plot_roc <- function(ctry) {
  d <- roc_curves %>% filter(country == ctry) %>%
    mutate(panel = facet_labels(.), class = factor(class, levels = CLASS_LABELS))
  auc_text <- d %>% distinct(panel, class, auc) %>% arrange(panel, class) %>%
    group_by(panel) %>%
    mutate(label = sprintf("AUC %s: %.2f", class, auc),
           y = 0.05 + 0.09 * (n() - row_number()))
  ggplot(d, aes(fpr, tpr, colour = class, linetype = class)) +
    geom_abline(intercept = 0, slope = 1, colour = "grey75", linewidth = 0.3) +
    geom_path(linewidth = 0.55) +
    geom_text(data = auc_text, aes(x = 0.98, y = y, label = label, colour = class),
              hjust = 1, size = 2.5, family = "serif", show.legend = FALSE, inherit.aes = FALSE) +
    facet_wrap(~panel, nrow = 1, labeller = as_labeller(function(x) gsub(": ", ":\n", x))) +
    scale_colour_manual(values = CLASS_COLORS) +
    scale_linetype_manual(values = CLASS_LINETYPES) +
    scale_x_continuous("False positive rate", limits = c(0, 1), breaks = c(0, 0.5, 1),
                       labels = c("0", "0.5", "1"), expand = expansion(mult = 0.02)) +
    scale_y_continuous("True positive rate", limits = c(0, 1), breaks = c(0, 0.5, 1),
                       labels = c("0", "0.5", "1"), expand = expansion(mult = 0.02)) +
    coord_equal() +
    theme_paper() +
    theme(panel.spacing.x = unit(1, "lines"), legend.margin = ggplot2::margin(0, 0, 0, 0),
          legend.box.spacing = unit(2, "pt"))
}

plot_confusion <- function(ctry) {
  d <- confusion %>% filter(country == ctry) %>%
    mutate(panel = facet_labels(.),
           predicted = factor(predicted, levels = rev(CLASS_LABELS)),
           actual = factor(actual, levels = CLASS_LABELS)) %>%
    group_by(panel, actual) %>% mutate(share = n / sum(n)) %>% ungroup() %>%
    mutate(panel = factor(sprintf("%s\nAccuracy %.1f%%", gsub(": ", ":\n", panel), 100 * accuracy)))
  d$panel <- factor(d$panel, levels = unique(d$panel[order(d$approach)]))
  ggplot(d, aes(actual, predicted, fill = share)) +
    geom_tile(colour = "white", linewidth = 0.6) +
    geom_text(aes(label = n, colour = share > 0.55), size = 3, family = "serif", fontface = "bold",
              vjust = -0.15) +
    geom_text(aes(label = sprintf("(%.0f%%)", 100 * share), colour = share > 0.55),
              size = 2.3, family = "serif", vjust = 1.35) +
    facet_wrap(~panel, nrow = 1) +
    scale_fill_gradient(low = "#F4F4F4", high = "#2F4B7C", limits = c(0, 1), guide = "none") +
    scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "black"), guide = "none") +
    scale_x_discrete("True label (hand coding)") +
    scale_y_discrete("Predicted label (hybrid score)") +
    coord_equal() +
    theme_paper() +
    theme(panel.grid = element_blank(), panel.border = element_blank(),
          axis.ticks = element_blank(), panel.spacing.x = unit(1, "lines"))
}

for (ctry in c("China", "US")) {
  prefix <- if (ctry == "China") "07_china" else "08_us"
  ggsave(fig_path(paste0(prefix, "_roc.pdf")), plot_roc(ctry), width = 6.5, height = 2.75, device = pdf)
  ggsave(fig_path(paste0(prefix, "_confusion.pdf")), plot_confusion(ctry), width = 6.5, height = 2.8,
         device = pdf)
}

print(as.data.frame(confusion %>% select(-accuracy)) %>% arrange(country, approach))
cat("Done: 07_08_confusion_roc\n")
