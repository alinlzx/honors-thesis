# 26-27 — Thesis Figures 26 and 27: share of clearly positive / negative documents
# per month, US vs. China.
#
# As posneg() and stationary_df() in time_series_analysis.Rmd:
#   cutoff     mean hybrid score +/- 0.1 SD, computed per country over all scored
#              documents in china_data (MFA, incl. the 8 undated, + People's Daily)
#              or us_data (dated Presidential + Congress draw)
#   positive   hybrid >= mean + 0.1 SD;  negative: hybrid <= mean - 0.1 SD
#   share      monthly count of positive (negative) documents / all documents that month,
#              for months with at least one such document
#   join       China and US months inner-joined, after dropping each series' first month
#              (stationary_df() first-differences the counts)
#   curve      LOESS, span 0.1 (geom_smooth default method for < 1,000 points)
# Added: a faint dot for every monthly share, the series the curves smooth. (These
# figures plot a share per month, so there is no per-document value to show.)
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/26_positive_doc_share.pdf, 27_negative_doc_share.pdf

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")

docs <- read_documents()
country_data <- list(China = filter(docs, country == "China"),   # china_data keeps undated MFA
                     US = filter(docs, in_series, country == "US"))

valence_shares <- function(df, direction) {
  cutoff <- mean(df$hybrid) + direction * 0.1 * sd(df$hybrid)
  kept <- if (direction > 0) filter(df, hybrid >= cutoff) else filter(df, hybrid <= cutoff)
  group_month(kept) %>% select(month, n_kept = doc_count) %>%
    left_join(group_month(df) %>% select(month, doc_count), by = "month") %>%
    mutate(share = n_kept / doc_count) %>%
    slice(-1)   # stationary_df() drops the first month of each series
}

plot_shares <- function(direction) {
  shares <- lapply(country_data, valence_shares, direction = direction)
  common <- intersect(shares$China$month, shares$US$month)
  d <- bind_rows(shares, .id = "country") %>% filter(month %in% common) %>%
    mutate(country_label = factor(COUNTRY_LABELS[country], levels = COUNTRY_LABELS))
  curves <- d %>% group_by(country_label) %>%
    group_modify(~ loess_curve(.x, "month", "share", span = 0.1)) %>% ungroup()
  cat(sprintf("%s: %d common months, %s to %s\n", if (direction > 0) "Positive" else "Negative",
              length(common), min(d$month), max(d$month)))
  ggplot() +
    geom_point(data = d, aes(month, share, colour = country_label), size = 1, alpha = 0.25,
               shape = 16, stroke = 0, show.legend = FALSE) +
    geom_line(data = curves, aes(date, fit, colour = country_label), linewidth = 0.8) +
    scale_colour_manual(values = COUNTRY_COLORS) +
    scale_x_years() +
    scale_y_continuous(sprintf("Share of documents that are %s", if (direction > 0) "positive" else "negative"),
                       limits = c(0, 1), labels = scales::label_percent(), expand = expansion(mult = 0.01)) +
    theme_paper()
}

save_fig("26_positive_doc_share.pdf", plot_shares(+1), height = 3.4)
save_fig("27_negative_doc_share.pdf", plot_shares(-1), height = 3.4)
cat("Done: 26_27_valence_shares\n")
