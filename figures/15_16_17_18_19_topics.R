# 15-19 — Thesis Figures 15 to 19: topics in US and Chinese documents about each other.
#
# Topics are keyword filters (TOPIC_KEYWORDS in setup.R, verbatim from
# time_series_analysis.Rmd) on the cleaned 2023 text; a document can belong to
# several topics. Monthly topic counts and mean sentiments come from rel_count()
# (topic_months() in setup.R). Documents: the country series, dated (US =
# Presidential + the 2,000-document Congress draw; China = MFA + People's Daily).
#   Figures 15 (US), 16 (China): monthly document counts per topic, each smoothed by
#              LOESS (span 0.1) and stacked. Smoothed counts below zero are set to
#              zero. Both panels stack topics in the same order (largest overall at
#              the bottom). Drawn as one figure, US panel above China panel.
#   Figure 17: share of Chinese documents mentioning the domestic periphery, and the
#              mean sentiment of all Chinese documents, each LOESS-smoothed (span
#              0.3). The thesis drew both on one plot with two y-axes; here they are
#              two stacked panels.
#   Figures 18 (US), 19 (China): monthly mean sentiment per topic, LOESS-smoothed
#              (span 0.4; the thesis used 0.7). Drawn as one figure: one panel per topic, with the US and
#              Chinese curves together in each (the thesis's all-topics panel is dropped).
# Added: faint dots for each document's score (Figures 17-19) and for each month's
# share (Figure 17).
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/15_16_topic_counts.pdf, 17_china_periphery_sentiment.pdf,
#         18_19_topic_sentiment.pdf

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

count_curves <- months %>% group_by(country, topic_label) %>%
  group_modify(~ loess_curve(.x, "month", "topic_count", span = 0.1)) %>% ungroup() %>%
  mutate(fit = pmax(fit, 0), topic_label = factor(topic_label, levels = stack_order),
         country = factor(COUNTRY_LABELS[country], levels = COUNTRY_LABELS[c("US", "China")]))
fig15_16 <- ggplot(count_curves, aes(date, fit, fill = topic_label)) +
  geom_area(position = "stack", colour = "white", linewidth = 0.25) +
  facet_wrap(~country, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = TOPIC_COLORS, breaks = unname(TOPIC_LABELS)) +
  scale_x_years() +
  scale_y_continuous("Documents per month (smoothed)", expand = expansion(mult = c(0, 0.05))) +
  guides(fill = guide_legend(nrow = 2)) +
  theme_paper() +
  theme(legend.key.size = unit(0.8, "lines"), panel.spacing.y = unit(0.8, "lines"))
save_fig("15_16_topic_counts.pdf", fig15_16, height = 5.4)

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
senti_curves <- months %>% group_by(country, topic_label) %>%
  group_modify(~ loess_curve(.x, "month", "topic_sentiment", span = 0.4)) %>% ungroup() %>%
  mutate(country = factor(COUNTRY_LABELS[country], levels = COUNTRY_LABELS))
senti_dots <- bind_rows(lapply(c("US", "China"), function(ctry) {
  ctry_docs <- filter(docs, country == ctry)
  bind_rows(lapply(names(TOPIC_LABELS), function(t) {
    topic_docs(ctry_docs, t) %>% mutate(topic_label = factor(TOPIC_LABELS[[t]], levels = TOPIC_LABELS))
  })) %>% mutate(country = factor(COUNTRY_LABELS[[ctry]], levels = COUNTRY_LABELS))
}))
cat("Topic sentiment:", clip_note(senti_dots))

fig18_19 <- ggplot() +
  geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
  doc_dots(senti_dots, colour = country) +
  geom_line(data = senti_curves, aes(date, fit, colour = country), linewidth = 0.8) +
  facet_wrap(~topic_label, ncol = 4, labeller = as_labeller(function(x) gsub(" & ", " &\n", x))) +
  scale_colour_manual(values = COUNTRY_COLORS) +
  scale_x_years() +
  scale_y_continuous("Hybrid sentiment score") +
  coord_cartesian(ylim = SENTI_YLIM) +
  theme_paper() +
  theme(panel.spacing = unit(0.6, "lines"), axis.text.x = element_text(size = 6.5),
        legend.position = "inside", legend.position.inside = c(0.875, 0.25),   # the empty eighth slot
        legend.direction = "vertical", legend.key.width = unit(1.6, "lines"))
save_fig("18_19_topic_sentiment.pdf", fig18_19, height = 4.2)

print(months %>% group_by(country, topic_label) %>%
        summarise(documents = sum(topic_count), months_with_docs = sum(topic_count > 0), .groups = "drop"),
      n = Inf)
cat("Done: 15_16_17_18_19_topics\n")
