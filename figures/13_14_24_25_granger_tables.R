# 13, 14, 24, 25 — Thesis Figures 13, 14, 24 and 25: Wald test p-values of bivariate
# Granger causality tests between US and Chinese sentiment.
#
# granger_p() in setup.R, as get_gct_pvalue() in time_series_analysis.Rmd: the two series are inner-joined by
# period, cut to periods strictly after a start date, and tested both ways with
# lmtest::grangertest(order = 3). "US as response" is grangertest(us ~ china): do
# lagged Chinese scores improve the prediction of US scores, given lagged US scores?
# Rows with a missing value are dropped before lagging (grangertest's model.frame()
# default), so lags run across gaps, as in the 2023 code.
# Stationarity (added in the rebuild): each pair goes through the ADF rule in setup.R
# (stationarity_method()), decided on the pair's full sample and kept for every start
# date: levels if both series are stationary, first differences if neither is,
# Toda-Yamamoto if only one is. Topic rows tested other than in levels are marked.
#   Figure 13: weekly mean sentiment, MFA (dated) vs. Presidential Library (dated);
#              start dates 1 January 2002, ..., 2020.
#   Figure 14: weekly mean sentiment, full country series (US = Presidential + the
#              2,000-document Congress draw; China = MFA + People's Daily); same dates.
#   Figure 24: monthly mean sentiment of the documents on each topic (rel_count() /
#              topic_months() in setup.R), full country series, after 1 January 2002
#              (the first start date of the Rmd loop; the MFA series begins in
#              October 2002, so this is the full overlap).
#   Figure 25: as Figure 24, after 1 January 2015.
# Figures 13 and 14 are written as one table with two side-by-side panels (full data
# left, MFA / Presidential right); likewise Figures 24 (left) and 25 (right).
#
# Input:  honors-thesis-original-data/sentiments/05_*_scored.csv (score: SCORE_VERSION)
# Output: figures/output/13_14_granger_time.tex, 24_25_granger_topics.tex (booktabs tables),
#         13_14_24_25_granger_preview.pdf (standalone compile, for checking)

source(if (file.exists("figures/setup.R")) "figures/setup.R" else "setup.R")
suppressPackageStartupMessages(library(lmtest))

LAG_ORDER <- 3
ALPHA <- 0.05
START_DATES <- as.Date(paste0(2002:2020, "-01-01"))
GRANGER_TOPICS <- c("domestic_periphery", "multi", "trade", "tw", "scs", "epidem", "russia")  # Rmd order
SCORE_NOTE <- c(a1 = "approach 1", a2 = "approach 2", a3 = "approach 3")[[SCORE_VERSION]]

docs <- read_documents() %>% filter(dated)

# ---- Figures 13, 14: forward time filter, weekly -----------------------------------------
by_start <- function(us_docs, china_docs) {
  granger_by_start(weekly_series(us_docs), weekly_series(china_docs), START_DATES, LAG_ORDER)
}
tab13 <- by_start(filter(docs, source == "pres"), filter(docs, source == "mofa"))
tab14 <- by_start(filter(docs, in_series, country == "US"), filter(docs, in_series, country == "China"))

# ---- Figures 24, 25: by topic, monthly ------------------------------------------------------
series <- filter(docs, in_series)
topic_series <- lapply(c(US = "US", China = "China"), function(ctry) {
  topic_months(filter(series, country == ctry)) %>% transmute(topic, period = month, senti = topic_sentiment)
})
topic_tab <- bind_rows(lapply(GRANGER_TOPICS, function(t) {
  granger_by_start(filter(topic_series$US, topic == t) %>% select(-topic),
                   filter(topic_series$China, topic == t) %>% select(-topic),
                   as.Date(c("2002-01-01", "2015-01-01")), LAG_ORDER) %>% mutate(topic = t)
}))
tab24 <- filter(topic_tab, start == as.Date("2002-01-01"))
tab25 <- filter(topic_tab, start == as.Date("2015-01-01"))

# ---- LaTeX ------------------------------------------------------------------------------------
fmt_p <- function(p) {
  s <- ifelse(p < 0.001, "$<$0.001", sprintf("%.3f", p))
  ifelse(p < ALPHA, paste0("\\textbf{", s, "}"), s)
}
row_line <- function(cells) paste0(paste(cells, collapse = " & "), " \\\\")

GRANGER_NOTE <- paste0(
  "Wald test $p$-values of bivariate Granger causality tests with ", LAG_ORDER,
  " lags of each series. ``US as response'' tests whether lagged Chinese sentiment improves the prediction of US sentiment ",
  "beyond lagged US sentiment; ``China as response'' tests the reverse. ",
  "Bold: $p < ", ALPHA, "$. Sentiment is the mean hybrid score (", SCORE_NOTE, ") of the documents in each period. ",
  "Each pair of series is first tested for a unit root (augmented Dickey--Fuller, constant and trend, 5\\% level, full sample). ",
  "If both series are stationary, the test is run in levels; if neither is, on first differences; ",
  "if only one is, by the Toda--Yamamoto procedure (both series in levels with one additional, untested lag of each). ",
  "All $p$-values are from $F$-tests.")
METHOD_MARK <- c(levels = "", differences = "$^{a}$", toda_yamamoto = "$^{b}$")
method_note <- function(methods) {
  used <- intersect(c("differences", "toda_yamamoto"), methods)
  if (length(used) == 0) return("Every pair is stationary, so all tests are in levels.")
  paste0(paste(c(differences = "$^{a}$ First differences.", toda_yamamoto = "$^{b}$ Toda--Yamamoto.")[used],
               collapse = " "), " Other rows: levels.")
}

# One table, two side-by-side panels sharing the row labels. `panels` is a named list
# (panel heading -> results table with us_response, china_response, n); `labels` are
# the row labels, aligned with every panel's rows.
make_table <- function(file, caption, label, head, labels, panels, n_label, note) {
  stopifnot(length(panels) == 2, all(sapply(panels, nrow) == length(labels)))
  body <- sapply(seq_along(labels), function(i) {
    row_line(c(labels[i], unlist(lapply(panels, function(t) {
      c(fmt_p(t$us_response[i]), fmt_p(t$china_response[i]), t$n[i])
    }))))
  })
  tex <- c(
    sprintf("%% Generated by figures/13_14_24_25_granger_tables.R (score: %s) -- do not edit by hand.", SCORE_VERSION),
    "% Requires \\usepackage{booktabs} and \\usepackage{threeparttable}.",
    "\\begin{table}[htbp]",
    "\\centering",
    "\\begin{threeparttable}",
    sprintf("\\caption{%s}", caption),
    sprintf("\\label{%s}", label),
    "\\small",
    "\\begin{tabular}{l rrr @{\\hspace{1.5em}} rrr}",
    "\\toprule",
    row_line(c("", sprintf("\\multicolumn{3}{c}{%s}", names(panels)))),
    "\\cmidrule(lr){2-4}\\cmidrule(lr){5-7}",
    row_line(c(head, rep(c("US as", "China as", n_label), 2))),
    row_line(c("", rep(c("response", "response", ""), 2))),
    "\\midrule",
    body,
    "\\bottomrule",
    "\\end{tabular}",
    "\\begin{tablenotes}[flushleft]",
    "\\footnotesize",
    paste("\\item \\textit{Notes:}", GRANGER_NOTE, note),
    "\\end{tablenotes}",
    "\\end{threeparttable}",
    "\\end{table}")
  writeLines(tex, fig_path(file))
  cat("Wrote", file, "\n")
}

date_labels <- function(tab) {
  first <- format(tab$start, "%Y")
  first[1] <- paste(first[1], "(full series)")
  first
}
stopifnot(identical(tab13$start, tab14$start), identical(tab24$topic, tab25$topic))

WEEK_NOTE <- paste(
  "Each row uses the weeks after 1 January of the year shown; the MFA series begins in October 2002, so the first row covers the full overlap.",
  "Weeks are seven-day bins counted from 1 January 2000; a week enters when both series have at least one document.",
  "Full data: US, Presidential Library documents and a random sample of 2,000 Congressional documents;",
  "China, MFA press conference answers and People's Daily articles.",
  "MFA / Presidential: US, dated Presidential Library documents; China, dated MFA press conference answers.")
time_methods <- c("Full data" = unique(tab14$method), "MFA / Presidential" = unique(tab13$method))
TIME_METHOD_NOTE <- if (all(time_methods == "levels")) "Every weekly series is stationary, so all tests are in levels." else
  paste0("Tests: ", paste(names(time_methods), tolower(GRANGER_METHODS[time_methods]), sep = ", ", collapse = "; "), ".")
make_table("13_14_granger_time.tex",
           "Granger causality between US and Chinese sentiment, by start date",
           "tab:granger-time", "Data after", date_labels(tab14),
           list("Full data" = tab14, "MFA / Presidential" = tab13), "Weeks", paste(WEEK_NOTE, TIME_METHOD_NOTE))
TOPIC_NOTE <- paste(
  "Each series is the monthly mean score of the documents matching a topic's keywords (full US and Chinese data).",
  "Months in which either country has no document on the topic are dropped before lagging; ``Months'' counts the months left.",
  "The right panel uses only months after 1 January 2015.")
make_table("24_25_granger_topics.tex", "Granger causality between US and Chinese sentiment, by topic",
           "tab:granger-topics", "Topic",
           paste0(gsub("&", "\\\\&", TOPIC_LABELS[tab24$topic]), METHOD_MARK[tab24$method]),
           list("All years" = tab24, "After 2015" = tab25), "Months",
           paste(TOPIC_NOTE, "The test for each topic is chosen on all months and kept for the right panel.",
                 method_note(tab24$method)))

# ---- Standalone preview of all four tables ------------------------------------------------------
TABLES <- c("13_14_granger_time.tex", "24_25_granger_topics.tex")
preview_dir <- tempfile("tex_preview_")
dir.create(preview_dir)
writeLines(c("\\documentclass[11pt]{article}",
             "\\usepackage[margin=1in]{geometry}",
             "\\usepackage{booktabs,threeparttable}",
             "\\pagestyle{empty}",
             "\\begin{document}",
             sprintf("\\input{%s}\n\\clearpage", normalizePath(fig_path(TABLES))),
             "\\end{document}"),
           file.path(preview_dir, "preview.tex"))
status <- system2("pdflatex", c("-interaction=nonstopmode", "-halt-on-error",
                                paste0("-output-directory=", shQuote(preview_dir)),
                                shQuote(file.path(preview_dir, "preview.tex"))),
                  stdout = FALSE, stderr = FALSE)
if (status == 0) {
  file.copy(file.path(preview_dir, "preview.pdf"), fig_path("13_14_24_25_granger_preview.pdf"), overwrite = TRUE)
} else {
  warning("pdflatex failed; see ", file.path(preview_dir, "preview.log"))
}

options(width = 120)
cat("\nFigure 13\n"); print(as.data.frame(tab13), digits = 3)
cat("\nFigure 14\n"); print(as.data.frame(tab14), digits = 3)
cat("\nFigure 24\n"); print(as.data.frame(tab24), digits = 3)
cat("\nFigure 25\n"); print(as.data.frame(tab25), digits = 3)
cat("Done: 13_14_24_25_granger_tables\n")
