# 20-23 — Thesis Figures 20 (trade & finance), 21 (multilateral negotiations),
# 22 (Taiwan) and 23 (domestic periphery): US and Chinese sentiment on one topic,
# side by side.
#
# As plot_topics() in time_series_analysis.Rmd: the monthly mean sentiment of the
# documents matching a topic's keywords (topic_months() in setup.R), for each country,
# with two LOESS curves: span 0.7 (dashed, the span of the all-topics figures) and
# span 0.1 (solid, to show shorter swings). Documents: the country series (US =
# Presidential + Congress draw; China = MFA + People's Daily), dated.
# Added: a faint dot for every document in the topic.
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/20_trade_sentiment.pdf, 21_multilateral_sentiment.pdf,
#         22_taiwan_sentiment.pdf, 23_periphery_sentiment.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

FIGURES <- c("20_trade_sentiment.pdf" = "trade",
             "21_multilateral_sentiment.pdf" = "multi",
             "22_taiwan_sentiment.pdf" = "tw",
             "23_periphery_sentiment.pdf" = "domestic_periphery")

docs <- read_documents() %>% filter(in_series)
months <- bind_rows(lapply(c("China", "US"), function(ctry) {
  topic_months(filter(docs, country == ctry)) %>% mutate(country = ctry)
})) %>% mutate(country_label = factor(COUNTRY_LABELS[country], levels = COUNTRY_LABELS))

CURVES <- c("LOESS span 0.1", "LOESS span 0.7")

plot_topic <- function(t) {
  d <- filter(months, topic == t)
  curves <- d %>% group_by(country_label) %>%
    group_modify(~ bind_rows(
      loess_curve(.x, "month", "topic_sentiment", span = 0.1) %>% mutate(curve = CURVES[1]),
      loess_curve(.x, "month", "topic_sentiment", span = 0.7) %>% mutate(curve = CURVES[2])
    )) %>% ungroup() %>% mutate(curve = factor(curve, levels = CURVES))
  dots <- topic_docs(docs, t)
  cat(sprintf("%-20s documents: China %4d, US %4d | %s", t, sum(dots$country == "China"),
              sum(dots$country == "US"), clip_note(dots)))
  ggplot() +
    geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
    doc_dots(dots, colour = country_label) +
    geom_line(data = curves, aes(date, fit, colour = country_label, linetype = curve, linewidth = curve)) +
    scale_colour_manual(values = COUNTRY_COLORS) +
    scale_linetype_manual(values = c("solid", "dashed")) +
    scale_linewidth_manual(values = c(0.4, 0.8)) +
    scale_x_years() +
    scale_y_continuous("Hybrid sentiment score") +
    coord_cartesian(ylim = SENTI_YLIM) +
    guides(colour = guide_legend(order = 1, override.aes = list(linewidth = 0.8))) +
    theme_paper()
}

for (f in names(FIGURES)) save_fig(f, plot_topic(FIGURES[[f]]), height = 3.6)
cat("Done: 20_21_22_23_topic_us_china\n")
