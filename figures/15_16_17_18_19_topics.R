# 15-19 — Thesis Figures 15 to 19: topics in US and Chinese documents about each other.
#
# Topics are keyword filters (TOPIC_KEYWORDS in setup.R, verbatim from
# time_series_analysis.Rmd) on the cleaned 2023 text; a document can belong to
# several topics. Monthly topic counts and mean sentiments come from rel_count()
# (topic_months() in setup.R). Documents: the country series, dated (US =
# Presidential + the 2,000-document Congress draw; China = MFA + People's Daily).
#   Figures 15 (US), 16 (China): monthly document counts per topic, each smoothed by
#              LOESS (span 0.1) and stacked. Smoothed counts below zero are set to
#              zero. Both figures stack topics in the same order (largest overall at
#              the bottom).
#   Figure 17: share of Chinese documents mentioning the domestic periphery, and the
#              mean sentiment of all Chinese documents, each LOESS-smoothed (span
#              0.3). The thesis drew both on one plot with two y-axes; here they are
#              two stacked panels.
#   Figures 18 (US), 19 (China): monthly mean sentiment per topic, LOESS-smoothed
#              (span 0.7). One panel per topic, plus a panel with all seven curves
#              (the thesis's view).
# Added: faint dots for each document's score (Figures 17-19) and for each month's
# share (Figure 17).
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/15_us_topic_counts.pdf, 16_china_topic_counts.pdf,
#         17_china_periphery_sentiment.pdf, 18_us_topic_sentiment.pdf,
#         19_china_topic_sentiment.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

docs <- read_documents() %>% filter(in_series)
months <- bind_rows(lapply(c("China", "US"), function(ctry) {
  topic_months(filter(docs, country == ctry)) %>% mutate(country = ctry)
})) %>%
  filter(topic %in% names(TOPIC_LABELS)) %>%
  mutate(topic_label = factor(TOPIC_LABELS[topic], levels = TOPIC_LABELS))

# ---- Figures 15, 16: topic counts ---------------------------------------------------------
stack_order <- months %>% group_by(topic_label) %>% summarise(n = sum(topic_count)) %>%
  arrange(n) %>% pull(topic_label) %>% as.character()   # largest topic at the bottom

plot_topic_counts <- function(ctry) {
  curves <- months %>% filter(country == ctry) %>% group_by(topic_label) %>%
    group_modify(~ loess_curve(.x, "month", "topic_count", span = 0.1)) %>% ungroup() %>%
    mutate(fit = pmax(fit, 0), topic_label = factor(topic_label, levels = stack_order))
  ggplot(curves, aes(date, fit, fill = topic_label)) +
    geom_area(position = "stack", colour = "white", linewidth = 0.25) +
    scale_fill_manual(values = TOPIC_COLORS, breaks = unname(TOPIC_LABELS)) +
    scale_x_years() +
    scale_y_continuous("Documents per month (smoothed)", expand = expansion(mult = c(0, 0.05))) +
    guides(fill = guide_legend(nrow = 2)) +
    theme_paper() +
    theme(legend.key.size = unit(0.8, "lines"))
}
save_fig("15_us_topic_counts.pdf", plot_topic_counts("US"), height = 3.8)
save_fig("16_china_topic_counts.pdf", plot_topic_counts("China"), height = 3.8)

# ---- Figure 17: domestic periphery share vs. overall sentiment (China) ----------------------
china_docs <- filter(docs, country == "China")
PANELS_17 <- c(share = "Share of documents mentioning\nthe domestic periphery",
               senti = "Hybrid sentiment score,\nall documents")
periphery <- months %>% filter(country == "China", topic == "domestic_periphery") %>%
  transmute(date = month, value = topic_count / doc_count, mean_sentiment)
curves17 <- bind_rows(
  loess_curve(periphery, "date", "value", span = 0.3) %>% mutate(panel = PANELS_17[["share"]]),
  loess_curve(periphery, "date", "mean_sentiment", span = 0.3) %>% mutate(panel = PANELS_17[["senti"]])
) %>% mutate(panel = factor(panel, levels = PANELS_17))
dots17 <- bind_rows(
  periphery %>% transmute(date, value, panel = PANELS_17[["share"]], size = 1.1, alpha = 0.25),
  china_docs %>% filter(hybrid >= SENTI_YLIM[1], hybrid <= SENTI_YLIM[2]) %>%   # clip, as in other figures
    transmute(date, value = hybrid, panel = PANELS_17[["senti"]], size = 0.7, alpha = DOT_ALPHA)
) %>% mutate(panel = factor(panel, levels = PANELS_17))

fig17 <- ggplot() +
  geom_hline(data = tibble(panel = factor(PANELS_17[["senti"]], levels = PANELS_17)),
             aes(yintercept = 0), colour = "grey70", linewidth = 0.3) +
  geom_point(data = dots17, aes(date, value, size = size, alpha = alpha), colour = COUNTRY_COLORS[[1]],
             shape = 16, stroke = 0) +
  geom_line(data = curves17, aes(date, fit), colour = COUNTRY_COLORS[[1]], linewidth = 0.8) +
  facet_grid(panel ~ ., scales = "free_y", switch = "y") +
  scale_size_identity() + scale_alpha_identity() +
  scale_x_years() +
  scale_y_continuous(NULL) +
  theme_paper() +
  theme(strip.placement = "outside", strip.text.y.left = element_text(angle = 90, face = "plain"),
        panel.spacing.y = unit(0.8, "lines"))
save_fig("17_china_periphery_sentiment.pdf", fig17, height = 4.4)
cat("Fig 17:", clip_note(china_docs))

# ---- Figures 18, 19: sentiment by topic -----------------------------------------------------
ALL_PANEL <- "All topics"
panel_levels <- c(TOPIC_LABELS, ALL_PANEL)

plot_topic_sentiment <- function(ctry) {
  senti_curves <- months %>% filter(country == ctry) %>% group_by(topic_label) %>%
    group_modify(~ loess_curve(.x, "month", "topic_sentiment", span = 0.7)) %>% ungroup()
  curves <- bind_rows(senti_curves %>% mutate(panel = as.character(topic_label)),
                      senti_curves %>% mutate(panel = ALL_PANEL)) %>%
    mutate(panel = factor(panel, levels = panel_levels))
  ctry_docs <- filter(docs, country == ctry)
  dots <- bind_rows(lapply(names(TOPIC_LABELS), function(t) {
    topic_docs(ctry_docs, t) %>% mutate(topic_label = factor(TOPIC_LABELS[[t]], levels = TOPIC_LABELS))
  })) %>% mutate(panel = factor(as.character(topic_label), levels = panel_levels))
  cat(sprintf("Topic sentiment, %s: %s", ctry, clip_note(dots)))

  ggplot() +
    geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
    doc_dots(dots, colour = topic_label) +
    geom_line(data = curves, aes(date, fit, colour = topic_label),
              linewidth = ifelse(curves$panel == ALL_PANEL, 0.5, 0.8)) +
    facet_wrap(~panel, ncol = 4, drop = FALSE,
               labeller = as_labeller(function(x) gsub(" & ", " &\n", x))) +
    scale_colour_manual(values = TOPIC_COLORS, guide = "none") +
    scale_x_years() +
    scale_y_continuous("Hybrid sentiment score") +
    coord_cartesian(ylim = SENTI_YLIM) +
    theme_paper() +
    theme(panel.spacing = unit(0.6, "lines"), axis.text.x = element_text(size = 6.5))
}
save_fig("18_us_topic_sentiment.pdf", plot_topic_sentiment("US"), height = 4.2)
save_fig("19_china_topic_sentiment.pdf", plot_topic_sentiment("China"), height = 4.2)

print(months %>% group_by(country, topic_label) %>%
        summarise(documents = sum(topic_count), months_with_docs = sum(topic_count > 0), .groups = "drop"),
      n = Inf)
cat("Done: 15_16_17_18_19_topics\n")
