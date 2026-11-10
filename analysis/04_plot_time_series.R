# Replicates the thesis's Figures 9 and 10 with the rebuilt corpora and the speaker-adjusted
# scores: stance toward the other country over time, by corpus and by country.
#
# In:  build/01_units.csv, build/02_relevance_scores.csv, build/05_spec_d_scores.csv,
#      build/06_adjusted_scores.csv
# Out: analysis/04_monthly_series.csv          the plotted monthly values (the figures' data)
#      analysis/04a_sentiment_by_source.png     Figure 9: MFA, President, White House briefings
#      analysis/04b_sentiment_by_country.png    Figure 10: China (MFA) and US (President + briefings)
#
# Choices, and why:
# - The score is spec D's net stance with speaker and format effects removed (net_adj, build/06).
#   The raw score moves the monthly series very little (analysis_recipes.md 6.8).
# - The thesis plotted LOESS curves of weekly means. These use calendar-month means
#   (passages -> document means -> monthly mean), the series the lead-lag tests use. The faint
#   points are the monthly values themselves, so the reader sees how noisy they are.
# - LOESS spans are fractions of the series, so the same span covers about the same stretch of
#   time at either frequency. The thesis's 0.08 (about two years here) is kept for the local
#   curve. Figure 10's trend curve uses 0.25 for both countries; the thesis used 0.3 for China
#   and 0.2 for the US, which made the two sides look differently smooth for no reason.
# - The US series in Figure 10 pools the President's documents and the briefings, each document
#   counted once. Both corpora run at a similar level except under Obama (briefings about .2
#   higher), and briefings nearly stop in 2018-20, so the pooled series shifts toward the
#   President in those years. The main lead-lag pairing is President <-> MFA (05), not this
#   pooled series.

source("config.R")
source("analysis/series_common.R")
suppressPackageStartupMessages(library(ggplot2))

SPAN_LOCAL <- 0.08
SPAN_TREND <- 0.25
dir.create(ANALYSIS_DIR, showWarnings = FALSE)

# Palette checked with the dataviz validator (CVD and normal-vision separation, contrast).
SOURCE_LABELS <- c(mfa = "China: MFA press conferences",
                   presdocs = "US: President",
                   briefings = "US: White House briefings")
SOURCE_COLORS <- setNames(c("#C8402F", "#2A5DB0", "#1A9E8F"), SOURCE_LABELS)
COUNTRY_COLORS <- c(China = "#C8402F", US = "#2A5DB0")

passages <- load_scored_passages()

by_source <- monthly_series(passages, "net_adj")
by_country <- passages %>%
  mutate(source = if_else(source == "mfa", "China", "US")) %>%
  monthly_series("net_adj")

write_csv(bind_rows(mutate(by_source, series = "source"), mutate(by_country, series = "country")) %>%
            select(series, source, month, value, documents, passages),
          file.path(ANALYSIS_DIR, "04_monthly_series.csv"))

theme_series <- function() {
  theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major = element_line(color = "grey92", linewidth = 0.3),
          axis.title = element_text(color = "grey30"),
          axis.text = element_text(color = "grey40"),
          legend.position = "bottom",
          legend.title = element_blank(),
          legend.text = element_text(color = "grey15"),
          plot.background = element_rect(fill = "white", color = NA))
}
y_label <- "Net stance toward the other country\n(monthly mean, speaker-adjusted)"
x_dates <- list(scale_x_date(date_breaks = "4 years", date_labels = "%Y", expand = expansion(mult = 0.01)),
                coord_cartesian(ylim = c(-1, 1)))  # a few single-document months fall outside; the curves are fit to all

# ---- Figure 9: each corpus --------------------------------------------------------

fig_source <- by_source %>%
  mutate(source = factor(SOURCE_LABELS[source], SOURCE_LABELS)) %>%
  ggplot(aes(month, value, color = source)) +
  geom_hline(yintercept = 0, color = "grey60", linewidth = 0.3) +
  geom_point(size = 0.8, alpha = 0.3, stroke = 0) +
  geom_smooth(method = "loess", formula = y ~ x, span = SPAN_LOCAL, se = FALSE, linewidth = 0.7) +
  scale_color_manual(values = SOURCE_COLORS) +
  x_dates +
  labs(x = NULL, y = y_label) +
  guides(color = guide_legend(override.aes = list(alpha = 1, size = 2))) +
  theme_series()
ggsave(file.path(ANALYSIS_DIR, "04a_sentiment_by_source.png"), fig_source,
       width = 7.5, height = 4.5, dpi = 300, bg = "white")

# ---- Figure 10: by country, local and trend curves --------------------------------

fig_country <- ggplot(by_country, aes(month, value, color = source)) +
  geom_hline(yintercept = 0, color = "grey60", linewidth = 0.3) +
  geom_point(size = 0.8, alpha = 0.3, stroke = 0) +
  geom_smooth(aes(linetype = "Local (span 0.08)"), method = "loess", formula = y ~ x,
              span = SPAN_LOCAL, se = FALSE, linewidth = 0.5) +
  geom_smooth(aes(linetype = "Trend (span 0.25)"), method = "loess", formula = y ~ x,
              span = SPAN_TREND, se = FALSE, linewidth = 0.9) +
  scale_color_manual(values = COUNTRY_COLORS,
                     labels = c(China = "China (MFA)", US = "US (President and briefings)")) +
  scale_linetype_manual(values = c("Local (span 0.08)" = "solid", "Trend (span 0.25)" = "22")) +
  x_dates +
  labs(x = NULL, y = y_label) +
  guides(color = guide_legend(order = 1, override.aes = list(alpha = 1, size = 2, linetype = "solid")),
         linetype = guide_legend(order = 2, override.aes = list(color = "grey30"))) +
  theme_series()
ggsave(file.path(ANALYSIS_DIR, "04b_sentiment_by_country.png"), fig_country,
       width = 7.5, height = 4.5, dpi = 300, bg = "white")

# ---- Console summary ---------------------------------------------------------------

cat("== Monthly series ==\n")
print(as.data.frame(bind_rows(by_source, by_country) %>%
  group_by(source) %>%
  summarise(months = n(), first = min(month), last = max(month),
            docs_per_month = round(mean(documents), 1), mean = round(mean(value), 3), .groups = "drop")))
