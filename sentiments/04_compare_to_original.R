# 04 — Compare rebuilt scores (01-03) with the archived 2023 scores, and rerun
# the headline Granger tests (thesis Figures 13 and 14).
#
# Exports (to honors-thesis-original-data/sentiments/):
#   04_doc_agreement.csv      document-level correlation / agreement, by source and approach
#   04_series_correlation.csv correlation of weekly and monthly mean-sentiment series
#   04_granger_headline.csv   forward-filter Granger p-values (lag 3, weekly), with thesis values
#
# Series construction follows "time_series_analysis.Rmd": US = all Presidential
# Library docs + 2,000 Congress docs drawn with set.seed(123); China = MFA +
# People's Daily; weeks counted from 2000-01-01.
#
# The archived Presidential Library `hybrid` column was rounded to +/-1 after
# scoring; it is recomputed here as (svm.label + bing_sentiment + rf.label) / 3,
# the same formula that reproduces the other archived files' hybrid scores.

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "functions.R")
suppressPackageStartupMessages(library(lmtest))

# ---- Load old and new scores ----------------------------------------------------
old_file <- c(pres = "Presidential_Library_Senti.xlsx", congress = "Congress_Senti.xlsx",
              mofa = "MOFA_Senti.xlsx", peoplesdaily = "PeoplesDaily_Senti.xlsx")
old <- bind_rows(lapply(names(old_file), function(src) {
  suppressMessages(read_excel(file.path(OLD_SENTI_DIR, old_file[[src]]))) %>%
    transmute(source = src, doc_id = row_number(), date = as.POSIXct(date),
              svm.label, rf.label, bing_sentiment,
              hybrid = (svm.label + bing_sentiment + rf.label) / 3)
})) %>% mutate(version = "2023 archive")

approaches <- c("01" = "01 approach 1 (binary)", "02" = "02 approach 2 (three-class)",
                "03" = "03 approach 3 (two binary)")
new <- bind_rows(lapply(names(approaches), function(a) {
  read_csv(out_path(paste0(a, "_scores.csv")), show_col_types = FALSE) %>%
    mutate(version = approaches[[a]])
}))

# ---- Document-level agreement ------------------------------------------------------
doc_agreement <- new %>%
  inner_join(old, by = c("source", "doc_id"), suffix = c("", "_old")) %>%
  group_by(version, source) %>%
  summarise(n_docs = n(),
            cor_hybrid = cor(hybrid, hybrid_old),
            cor_bing = cor(bing_sentiment, bing_sentiment_old),
            svm_agree = mean(svm.label == svm.label_old),
            rf_agree = mean(rf.label == rf.label_old),
            svm_share_O = mean(svm.label == 0),
            rf_share_O = mean(rf.label == 0),
            hybrid_sign_agree = mean(sign(hybrid) == sign(hybrid_old)),
            mean_hybrid = mean(hybrid), mean_hybrid_old = mean(hybrid_old),
            .groups = "drop")
write_csv(doc_agreement, out_path("04_doc_agreement.csv"))
print(as.data.frame(doc_agreement), digits = 3)

# ---- Country series ----------------------------------------------------------------
set.seed(123)
cong_ids <- sample(4800, 2000) # same draw as time_series_analysis.Rmd (rows of Congress_Senti.xlsx)

group_week <- function(df) {
  df$week <- floor(as.numeric(difftime(df$date, as.Date("2000-01-01"), units = "weeks")))
  df %>% group_by(week) %>% summarise(mean_sentiment = mean(hybrid), doc_count = n(), .groups = "drop") %>%
    mutate(week = as.Date("2000-01-01") + week * 7)
}
group_month <- function(df) {
  df %>% mutate(month = as.Date(paste0(format(date, "%Y-%m"), "-01"))) %>%
    group_by(month) %>% summarise(mean_sentiment = mean(hybrid), doc_count = n(), .groups = "drop")
}

build_series <- function(scores) {
  scores <- filter(scores, !is.na(date))
  us <- filter(scores, source == "pres" | (source == "congress" & doc_id %in% cong_ids))
  ch <- filter(scores, source %in% c("mofa", "peoplesdaily"))
  list(us_week = group_week(us), china_week = group_week(ch),
       pres_week = group_week(filter(scores, source == "pres")),
       mofa_week = group_week(filter(scores, source == "mofa")),
       us_month = group_month(us), china_month = group_month(ch))
}

all_versions <- bind_rows(old, new)
series <- lapply(split(all_versions, all_versions$version), build_series)

series_cor <- bind_rows(lapply(approaches, function(v) {
  bind_rows(lapply(c("us_week", "china_week", "pres_week", "mofa_week", "us_month", "china_month"), function(s) {
    key <- if (grepl("week", s)) "week" else "month"
    j <- inner_join(series[["2023 archive"]][[s]], series[[v]][[s]], by = key)
    tibble(version = v, series = s, n_periods = nrow(j),
           cor_mean_sentiment = cor(j$mean_sentiment.x, j$mean_sentiment.y))
  }))
}))
write_csv(series_cor, out_path("04_series_correlation.csv"))
print(as.data.frame(series_cor), digits = 3)

# ---- Headline Granger tests (Figures 13 and 14) ----------------------------------------
get_gct_pvalue <- function(dates, us_dat, ch_dat) {
  us_china_gct <- inner_join(us_dat, ch_dat, by = "week") %>% subset(week > as.Date(dates))
  colnames(us_china_gct) <- c("week", "us_senti", "us_doc_count", "ch_senti", "ch_doc_count")
  gct_1 <- grangertest(us_senti ~ ch_senti, data = us_china_gct, order = 3)
  gct_2 <- grangertest(ch_senti ~ us_senti, data = us_china_gct, order = 3)
  c(us_response = gct_1$`Pr(>F)`[2], china_response = gct_2$`Pr(>F)`[2])
}

# p-values as printed in the thesis (Figure 13: MFA vs Presidential Library;
# Figure 14: full China vs full US data).
thesis <- tribble(
  ~year, ~fig13_china, ~fig13_us, ~fig14_china, ~fig14_us,
  2002, 2.41e-4, 1.09e-4, 0.05, 5.20e-5,
  2003, 2.39e-4, 1.35e-4, 0.05, 6.86e-5,
  2004, 5.17e-4, 3.65e-4, 0.06, 1.81e-4,
  2005, 4.94e-4, 3.14e-4, 0.05, 2.32e-4,
  2006, 3.63e-4, 1.46e-4, 0.02, 2.89e-4,
  2007, 4.01e-3, 2.24e-4, 0.03, 4.88e-4,
  2008, 0.02, 3.12e-4, 0.05, 5.69e-4,
  2009, 0.02, 4.69e-4, 0.03, 9.79e-4,
  2010, 0.04, 3.04e-4, 0.01, 2.76e-3,
  2011, 0.11, 5.68e-5, 0.01, 8.03e-4,
  2012, 0.12, 1.09e-5, 0.01, 7.14e-4,
  2013, 0.07, 3.09e-7, 0.03, 2.48e-4,
  2014, 0.14, 1.43e-7, 0.23, 2.82e-4,
  2015, 0.30, 1.12e-6, 0.05, 2.66e-4,
  2016, 0.11, 2.73e-5, 0.17, 3.28e-4,
  2017, 0.07, 2.60e-4, 0.03, 5.85e-4,
  2018, 0.02, 2.33e-4, 0.04, 0.01,
  2019, 0.08, 0.03, 0.06, 0.02,
  2020, 0.98, 0.31, 0.53, 0.38
)
thesis_long <- bind_rows(
  thesis %>% transmute(year, figure = "Fig 13: MFA vs Presidential", response = "US", p = fig13_us),
  thesis %>% transmute(year, figure = "Fig 13: MFA vs Presidential", response = "China", p = fig13_china),
  thesis %>% transmute(year, figure = "Fig 14: full China vs full US", response = "US", p = fig14_us),
  thesis %>% transmute(year, figure = "Fig 14: full China vs full US", response = "China", p = fig14_china)
) %>% mutate(version = "thesis (as printed)")

granger <- bind_rows(lapply(names(series), function(v) {
  s <- series[[v]]
  bind_rows(lapply(2002:2020, function(y) {
    d <- paste0(y, "-01-01")
    p13 <- get_gct_pvalue(d, s$pres_week, s$mofa_week)
    p14 <- get_gct_pvalue(d, s$us_week, s$china_week)
    tibble(year = y,
           figure = rep(c("Fig 13: MFA vs Presidential", "Fig 14: full China vs full US"), each = 2),
           response = rep(c("US", "China"), 2),
           p = c(p13[["us_response"]], p13[["china_response"]], p14[["us_response"]], p14[["china_response"]]))
  })) %>% mutate(version = v)
})) %>% bind_rows(thesis_long) %>%
  select(figure, response, year, version, p) %>%
  arrange(figure, response, year, version)
write_csv(granger, out_path("04_granger_headline.csv"))

granger_summary <- granger %>%
  group_by(figure, response, version) %>%
  summarise(years_p_below_05 = sum(p < 0.05), of_years = n(),
            p_full_series = p[year == 2002], p_after_2010 = p[year == 2010],
            p_after_2015 = p[year == 2015], .groups = "drop")
print(as.data.frame(granger_summary), digits = 3)
