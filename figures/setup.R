# Shared paths, plot theme and data loaders for the exhibit scripts.
#
# Run exhibit scripts from the repo root, e.g. `Rscript figures/06_sentiment_stats.R`.
# Inputs come from honors-thesis-original-data/sentiments/ (written by sentiments/0X_*.R);
# exhibits are written to figures/output/.

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "../sentiments/functions.R")
suppressPackageStartupMessages(library(ggplot2))

FIG_DIR <- file.path(REPO_ROOT, "figures", "output")
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)
fig_path <- function(name) file.path(FIG_DIR, name)

APPROACHES <- c("01" = "Approach 1: positive and negative only",
                "02" = "Approach 2: all three classes",
                "03" = "Approach 3: two binary models")
APPROACH_SHORT <- c("01" = "Approach 1", "02" = "Approach 2", "03" = "Approach 3")
CLASS_LABELS <- c(N = "Negative", O = "Ambiguous", P = "Positive")
CLASS_COLORS <- c(Negative = "#B2182B", Ambiguous = "#8C8C8C", Positive = "#2166AC")
CLASS_LINETYPES <- c(Negative = "solid", Ambiguous = "dotted", Positive = "dashed")

theme_paper <- function(base_size = 9) {
  theme_bw(base_size = base_size, base_family = "serif") +
    theme(panel.grid.minor = element_blank(),
          strip.background = element_blank(),
          strip.text = element_text(face = "bold", size = base_size),
          legend.position = "bottom",
          legend.title = element_blank(),
          legend.key.width = unit(1.6, "lines"))
}

# Evaluation sets behind each approach's metrics, as used in sentiments/0X_*.R:
# approach 1 scores its three-class statistics on the P/N test split plus held-out
# ambiguous documents; approaches 2 and 3 use their test split directly.
read_eval_sets <- function() {
  bind_rows(lapply(names(APPROACHES), function(a) {
    preds <- read_csv(out_path(paste0(a, "_test_predictions.csv")), show_col_types = FALSE)
    three_class_set <- if (a == "01") "test split + held-out O, re-vectorized" else "test split"
    # Round away floating-point noise from the CSV round trip, so documents with
    # identical SVM, RF and Bing scores stay tied (as when 0X_metrics.csv was computed).
    preds %>% filter(eval_set == three_class_set) %>% mutate(approach = a, hybrid = round(hybrid, 10))
  }))
}

# ---- Time-series exhibits (Figures 2-4, 9-10, 13-27, 29) ----------------------------
# Which rebuilt score feeds the time series. Default: approach 2, the best performer
# in Figure 6. (The thesis's series used the archived *_Senti.xlsx scores, whose
# SVM/RF labels are binary (P/N), i.e. approach 1.)
# Set to "a1" or "a3" (or the env var THESIS_SCORE_VERSION) to redraw every
# time-series exhibit with another approach.
SCORE_VERSION <- Sys.getenv("THESIS_SCORE_VERSION", "a2")

SOURCE_LABELS <- c(mofa = "MFA press conferences", peoplesdaily = "People's Daily",
                   pres = "Presidential Library", congress = "Congressional documents")
SOURCE_COLORS <- setNames(c("#B2182B", "#D9822B", "#1F4E9A", "#56A3D9"), SOURCE_LABELS)
COUNTRY_LABELS <- c(China = "China on the US", US = "US on China")
COUNTRY_COLORS <- setNames(c("#B2182B", "#2166AC"), COUNTRY_LABELS)
DOT_ALPHA <- 0.10         # per-document dots behind every smoothed line
SENTI_YLIM <- c(-2, 2)    # visible window for document dots (lines are fit on all data)

# Topic keywords, copied verbatim from time_series_analysis.Rmd (case-sensitive grepl
# on the cleaned 2023 text). The thesis plots the first seven; the last four only
# determine which months enter the topic table (rel_count() full-joins all eleven).
TOPIC_KEYWORDS <- c(
  trade = "trade|tariff|protectionis|WTO|import|export|ITC|countervailing duty|intellectual property|manufactur|exchange rate|jobs|currency",
  domestic_periphery = "human rights|Xinjiang|Tibet|Hong Kong|Uyghur",
  tw = "Taiwan",
  multi = "denucleariz|DPRK|North Korea|Iran|JCPOA|IAEA|Paris|climate|COP|ASEAN|APEC|EAS|G20|summit|multilateral",
  scs = "South China Sea",
  epidem = "COVID|coronavirus|WHO|epidemic|Ebola|outbreak|pandemic|SARS",
  intl_actors = "Belt and Road|BRI|Pakistan|Brazil|ASEAN|Germany|France|UK|EU|India|Mexico|APEC|Asia Pacific|Japan",
  russia = "Russia",
  counterterrorism = "Al Qaeda|ISIS|terrori|extremism|Afghanistan|Iraq",
  cooperation = "dialogue|cooperat|partner|trust|coordination|constructive",
  competition = "compete|competit|threat|rival|confrontation|abuse|manipulat|Cold War|bully"
)
TOPIC_LABELS <- c(trade = "Trade & finance", domestic_periphery = "Domestic periphery & human rights",
                  tw = "Taiwan", multi = "Multilateral negotiations", scs = "South China Sea",
                  epidem = "Global health & epidemics", russia = "Russia")
TOPIC_COLORS <- setNames(c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6"),
                         TOPIC_LABELS)

# One row per scored document, from the 05_*_scored.csv exports, with the score
# chosen by SCORE_VERSION as `hybrid` and the exact 2023 text (00_corpora.csv) as
# `text`. Flags:
#   in_series  enters the country series of time_series_analysis.Rmd (us_data /
#              china_data with a date): Presidential + the 2,000-document Congress
#              draw, MFA + People's Daily
#   dated      has a date (Figure 9 plots every dated Congress document, not just the draw)
read_documents <- function(version = SCORE_VERSION) {
  scored <- read_scored()
  scored$congress <- rename(scored$congress, date = Timestamp)
  docs <- bind_rows(lapply(scored, function(d) {
    d %>% transmute(source, doc_id, in_series = in_ts_sample, date = as.Date(date),
                    hybrid = .data[[paste0("hybrid_", version)]])
  }))
  text <- read_corpora() %>% select(source, doc_id, text)
  docs %>% left_join(text, by = c("source", "doc_id")) %>%
    mutate(dated = !is.na(date),
           country = ifelse(source %in% c("mofa", "peoplesdaily"), "China", "US"),
           source_label = factor(SOURCE_LABELS[source], levels = SOURCE_LABELS),
           country_label = factor(COUNTRY_LABELS[country], levels = COUNTRY_LABELS))
}

# group_month() / group_week() from time_series_analysis.Rmd: mean hybrid score and
# document count per calendar month, or per 7-day week counted from 2000-01-01.
group_month <- function(df) {
  df %>% filter(!is.na(date)) %>%
    mutate(month = as.Date(paste0(format(date, "%Y-%m"), "-01"))) %>%
    group_by(month) %>% summarise(mean_sentiment = mean(hybrid), doc_count = n(), .groups = "drop")
}
group_week <- function(df) {
  df %>% filter(!is.na(date)) %>%
    mutate(week = floor(as.numeric(difftime(date, as.Date("2000-01-01"), units = "weeks")))) %>%
    group_by(week) %>% summarise(mean_sentiment = mean(hybrid), doc_count = n(), .groups = "drop") %>%
    mutate(week = as.Date("2000-01-01") + week * 7)
}

scale_x_years <- function(...) {
  scale_x_date(NULL, breaks = seq(as.Date("2000-01-01"), as.Date("2025-01-01"), by = "5 years"),
               date_labels = "%Y", expand = expansion(mult = 0.01), ...)
}

# Faint per-document dots; documents outside SENTI_YLIM are clipped by the coord, not dropped.
doc_dots <- function(data, ...) {
  geom_point(data = data, aes(date, hybrid, ...), size = 0.7, stroke = 0, alpha = DOT_ALPHA,
             shape = 16, inherit.aes = FALSE, show.legend = FALSE)
}
clip_note <- function(docs) {
  sprintf("%.1f%% of document dots fall outside [%g, %g] and are cut off\n",
          100 * mean(docs$hybrid < SENTI_YLIM[1] | docs$hybrid > SENTI_YLIM[2]),
          SENTI_YLIM[1], SENTI_YLIM[2])
}
# Note: pdf() draws "-" in text as a minus sign, so labels avoid hyphens.
save_fig <- function(name, plot, width = 6.5, height = 3.6) {
  ggsave(fig_path(name), plot, width = width, height = height, device = pdf)
  cat("Wrote", name, "\n")
}

# LOESS curve through a time series, as geom_smooth(method = "loess", span = span)
# fits it (degree 2, gaussian, x = date as a number), evaluated on a grid of `n` dates.
# Precomputed rather than drawn with geom_smooth so a curve can appear in several
# panels, or be stacked.
loess_curve <- function(df, x, y, span, n = 400) {
  df <- df[!is.na(df[[x]]) & !is.na(df[[y]]), ]
  xs <- as.numeric(df[[x]])
  fit <- loess(df[[y]] ~ xs, span = span)
  grid <- seq(min(xs), max(xs), length.out = n)
  tibble(date = as.Date(grid, origin = "1970-01-01"), fit = as.numeric(predict(fit, grid)))
}

# rel_count() from time_series_analysis.Rmd, in long form: for one country's documents,
# the monthly mean sentiment (`topic_sentiment`) and count (`topic_count`) of documents
# matching each topic's keywords, with the country's overall monthly mean and count.
# Months: those in which any of the eleven topics has a document; counts of 0 fill
# the gaps, while topic_sentiment stays NA.
topic_months <- function(country_docs) {
  per_topic <- bind_rows(lapply(names(TOPIC_KEYWORDS), function(t) {
    group_month(filter(country_docs, grepl(TOPIC_KEYWORDS[[t]], text))) %>%
      transmute(month, topic = t, topic_sentiment = mean_sentiment, topic_count = doc_count)
  }))
  per_topic %>%
    tidyr::complete(month, topic, fill = list(topic_count = 0L)) %>%
    left_join(group_month(country_docs), by = "month")
}
topic_docs <- function(country_docs, t) {
  filter(country_docs, grepl(TOPIC_KEYWORDS[[t]], text), !is.na(date))
}

# ---- Granger causality (Figures 12-14, 24, 25, 28) ---------------------------------
# As get_gct_pvalue() in time_series_analysis.Rmd: the two series (columns period,
# senti) are inner-joined by period, cut to periods strictly after `after`, and tested
# both ways with lmtest::grangertest(). "US as response" is grangertest(us ~ china).
# Rows with a missing value are dropped before lagging (model.frame() default), so
# lags run across gaps, as in the 2023 code. `method` comes from the stationarity rule
# below.
weekly_series <- function(d) group_week(d) %>% transmute(period = week, senti = mean_sentiment)
monthly_series <- function(d) group_month(d) %>% transmute(period = month, senti = mean_sentiment)
# Stationarity rule (added in the rebuild; the 2023 code tested every series in levels):
#   - ADF with constant and trend, k = trunc((n - 1)^(1/3)) lagged differences (the
#     regression of tseries::adf.test, via urca::ur.df), 5% level;
#   - each series is tested as it enters the full-sample test (the inner-joined pair over
#     all periods), and the decision is kept for every start-date window;
#   - both series reject a unit root -> F-test in levels (as before);
#     neither does                    -> F-test on the first differences of both;
#     only one does (mixed orders)    -> Toda-Yamamoto: both series in levels with
#        order + 1 lags of each, Wald test (F form) on the first `order` lags of the
#        other series only (the extra lag absorbs the unit root and is not tested).
adf_unit_root <- function(x) {   # TRUE if ADF cannot reject a unit root at 5%
  x <- x[!is.na(x)]
  a <- urca::ur.df(x, type = "trend", lags = trunc((length(x) - 1)^(1/3)), selectlags = "Fixed")
  a@teststat[1, "tau3"] >= a@cval["tau3", "5pct"]
}
GRANGER_METHODS <- c(levels = "Levels", differences = "First differences", toda_yamamoto = "Toda-Yamamoto")
stationarity_method <- function(us, china) {
  d <- inner_join(us, china, by = "period", suffix = c("_us", "_ch")) %>%
    filter(!is.na(senti_us), !is.na(senti_ch))
  unit_root <- c(adf_unit_root(d$senti_us), adf_unit_root(d$senti_ch))
  if (!any(unit_root)) "levels" else if (all(unit_root)) "differences" else "toda_yamamoto"
}
# Toda-Yamamoto p-value for "x Granger-causes y": y on a constant and order + dmax lags of
# y and x; Wald test that the first `order` lags of x are all zero, in its F form
# (W / order against F(order, residual df)), so it is on the same footing as the
# grangertest() F-tests and more cautious than the chi-square form in short series.
toda_yamamoto_p <- function(y, x, order, dmax = 1) {
  m <- order + dmax
  e <- embed(cbind(y, x), m + 1)            # columns: y_t, x_t, y_t-1, x_t-1, ...
  y_lags <- e[, seq(3, by = 2, length.out = m), drop = FALSE]
  x_lags <- e[, seq(4, by = 2, length.out = m), drop = FALSE]
  fit <- lm(e[, 1] ~ y_lags + x_lags)
  idx <- paste0("x_lags", seq_len(order))
  b <- coef(fit)[idx]
  w <- as.numeric(t(b) %*% solve(vcov(fit)[idx, idx], b))
  pf(w / order, order, fit$df.residual, lower.tail = FALSE)
}
granger_p <- function(us, china, after = as.Date("1900-01-01"), order = 3, method = "levels") {
  d <- inner_join(us, china, by = "period", suffix = c("_us", "_ch")) %>% filter(period > after)
  d <- transmute(d, us_senti = senti_us, ch_senti = senti_ch)
  n <- sum(complete.cases(d))
  if (method == "toda_yamamoto") {
    d <- d[complete.cases(d), ]
    return(tibble(us_response = toda_yamamoto_p(d$us_senti, d$ch_senti, order),
                  china_response = toda_yamamoto_p(d$ch_senti, d$us_senti, order), n = n, method = method))
  }
  if (method == "differences") {
    d <- d[complete.cases(d), ]
    d <- tibble(us_senti = diff(d$us_senti), ch_senti = diff(d$ch_senti))
  }
  us_resp <- lmtest::grangertest(us_senti ~ ch_senti, data = d, order = order)
  ch_resp <- lmtest::grangertest(ch_senti ~ us_senti, data = d, order = order)
  tibble(us_response = us_resp$`Pr(>F)`[2], china_response = ch_resp$`Pr(>F)`[2], n = n, method = method)
}
# The stationarity rule applied to one pair across start dates.
granger_by_start <- function(us, china, starts, order = 3) {
  method <- stationarity_method(us, china)
  bind_rows(lapply(starts, function(s) granger_p(us, china, s, order, method) %>% mutate(start = s)))
}
GRANGER_OUTCOMES <- c(us = "US as response", china = "China as response", both = "Both", neither = "Neither")
granger_outcome <- function(us_p, china_p, alpha = 0.05) {
  unname(GRANGER_OUTCOMES[case_when(us_p < alpha & china_p < alpha ~ "both", us_p < alpha ~ "us",
                                    china_p < alpha ~ "china", TRUE ~ "neither")])
}
# posneg() + stationary_df() from time_series_analysis.Rmd: monthly count of clearly
# positive (direction = 1) or negative (-1) documents, cutoff mean +/- 0.1 SD of the
# country's hybrid scores, first-differenced (the first month drops out). `country_docs`:
# china_data (all scored Chinese documents) or us_data (the US country series).
polarity_series <- function(country_docs, direction) {
  cutoff <- mean(country_docs$hybrid) + direction * 0.1 * sd(country_docs$hybrid)
  kept <- if (direction > 0) filter(country_docs, hybrid >= cutoff) else filter(country_docs, hybrid <= cutoff)
  m <- group_month(kept)
  tibble(period = m$month[-1], senti = diff(m$doc_count))
}
