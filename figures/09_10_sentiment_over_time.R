# 09-10 — Thesis Figures 9 and 10: mean sentiment over time, by corpus and by country.
#
# As in the thesis ("sentiment analysis & EDA.Rmd", Data Viz chunks): documents are
# grouped into 7-day weeks counted from 2000-01-01, the weekly mean hybrid score is
# taken, and a LOESS curve is fit to the weekly means.
#   Figure 9:  one curve per corpus, span 0.08. Congress uses every dated scored
#              document (congress_week), not only the 2,000-document draw.
#   Figure 10: country series (US = Presidential + Congress draw; China = MFA +
#              People's Daily), span 0.08 (solid) plus a long-run curve (dashed;
#              span 0.3 for China, 0.2 for US).
# Added: a faint dot for every document (date x hybrid score), to show how much
# document-level noise the curves smooth over. Figure 9 is split into one panel per
# corpus, with the other three curves in gray for reference.
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/09_sentiment_by_source.pdf, 10_sentiment_by_country.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

docs <- read_documents()

# ---- Figure 9: by corpus ---------------------------------------------------------------
source_docs <- docs %>% filter(dated) # every dated scored document
source_curves <- source_docs %>% group_by(source_label) %>%
  group_modify(~ loess_curve(group_week(.x), "week", "mean_sentiment", span = 0.08)) %>% ungroup()
reference <- source_curves %>% rename(curve_of = source_label) %>%
  tidyr::crossing(source_label = factor(SOURCE_LABELS, levels = SOURCE_LABELS)) %>%
  filter(curve_of != source_label)

fig9 <- ggplot() +
  geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
  doc_dots(source_docs, colour = source_label) +
  geom_line(data = reference, aes(date, fit, group = curve_of), colour = "grey70", linewidth = 0.3) +
  geom_line(data = source_curves, aes(date, fit, colour = source_label), linewidth = 0.7) +
  facet_wrap(~source_label, ncol = 2) +
  scale_colour_manual(values = SOURCE_COLORS, guide = "none") +
  scale_x_years() +
  scale_y_continuous("Hybrid sentiment score") +
  coord_cartesian(ylim = SENTI_YLIM) +
  theme_paper() +
  theme(panel.spacing = unit(0.8, "lines"))
save_fig("09_sentiment_by_source.pdf", fig9, height = 4.6)
cat("Fig 9:", clip_note(source_docs))

# ---- Figure 10: by country -------------------------------------------------------------
country_docs <- docs %>% filter(in_series)
long_span <- c(China = 0.3, US = 0.2)
country_curves <- country_docs %>% group_by(country, country_label) %>%
  group_modify(~ bind_rows(
    loess_curve(group_week(.x), "week", "mean_sentiment", span = 0.08) %>% mutate(curve = "LOESS span 0.08"),
    loess_curve(group_week(.x), "week", "mean_sentiment", span = long_span[[.y$country]]) %>%
      mutate(curve = "LOESS span 0.3 (China), 0.2 (US)")
  )) %>% ungroup() %>%
  mutate(curve = factor(curve, levels = c("LOESS span 0.08", "LOESS span 0.3 (China), 0.2 (US)")))

fig10 <- ggplot() +
  geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
  doc_dots(country_docs, colour = country_label) +
  geom_line(data = country_curves,
            aes(date, fit, colour = country_label, linetype = curve, linewidth = curve)) +
  scale_colour_manual(values = COUNTRY_COLORS) +
  scale_linetype_manual(values = c("solid", "dashed")) +
  scale_linewidth_manual(values = c(0.45, 0.8)) +
  scale_x_years() +
  scale_y_continuous("Hybrid sentiment score") +
  coord_cartesian(ylim = SENTI_YLIM) +
  guides(colour = guide_legend(order = 1, override.aes = list(linewidth = 0.8))) +
  theme_paper()
save_fig("10_sentiment_by_country.pdf", fig10, height = 3.6)
cat("Fig 10:", clip_note(country_docs))

print(source_docs %>% count(source_label, name = "dated documents"))
cat("Done: 09_10_sentiment_over_time\n")
