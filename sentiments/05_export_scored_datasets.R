# 05 — Attach the sentiment scores to the raw datasets.
#
# Each raw dataset in honors-thesis-original-data/raw/ is written back out with
# every original row and column, plus the scores from approaches 1-3 (01-03) and
# the archived 2023 scores. Rows that were never scored (not in the 2023
# Congress sample, filtered out of People's Daily, or missing text) keep NA scores.
#
# Raw rows are matched to the scored corpora (00_corpora.csv / 0X_scores.csv,
# whose doc_id is the row number in sentiments/_archive/*_Senti.xlsx) on
# document content, not position:
#   Presidential Library  title + date + cleaned text
#   Congress (1 and 2)    title + date + text + subhead
#   MFA                   link + question + answer
#   People's Daily        title + date + text, after dropping Excel's escaped
#                         carriage returns ("_x000D_") and normalizing whitespace
# Exact duplicate documents are matched in order of appearance (k-th copy in the
# archive to the k-th copy in the raw file); they carry identical text.
#
# Exports (to honors-thesis-original-data/sentiments/):
#   05_presidential_scored.csv, 05_congress_scored.csv (Congress1 + Congress2,
#   with raw_file), 05_mfa_scored.csv, 05_peoplesdaily_scored.csv
#
# Added columns:
#   source, raw_file, raw_row     where the row came from
#   doc_id                        join key to 00_corpora.csv and 0X_scores.csv (NA if not scored)
#   scored                        TRUE if the document was scored
#   in_ts_sample                  TRUE if the document enters the country time series
#                                 (scored and dated; for Congress, only the 2,000 drawn
#                                 with set.seed(123) in time_series_analysis.Rmd)
#   {afinn,bing,svm,rf,hybrid}_a1 approach 1 scores (likewise _a2, _a3)
#   {afinn,bing,svm,rf,hybrid}_2023 archived 2023 scores; hybrid_2023 is recomputed as
#                                 (svm + bing + rf) / 3 (the Presidential file had it rounded)
# Lexicon scores carry an approach suffix because Bing and AFINN are standardized
# within the chunk each approach scored, and the chunks differ by approach.
# Read the exports with read_scored() in functions.R.

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "functions.R")
suppressPackageStartupMessages(library(stringr))

raw_path <- function(f) file.path(DATA_DIR, "raw", f)
read_xl <- function(f) suppressMessages(read_excel(f))

# Pastes key columns together and numbers repeated keys, so duplicates match in order.
make_key <- function(df, cols) {
  key <- do.call(paste, c(lapply(cols, function(c) as.character(df[[c]])), sep = "\r"))
  paste(key, ave(seq_along(key), key, FUN = seq_along), sep = "#")
}
norm_text <- function(x) str_squish(gsub("_x000D_|\r", " ", x))

# ---- Scores, wide by version ---------------------------------------------------------
score_cols <- c(afinn = "afinn_sentiment", bing = "bing_sentiment", svm = "svm.label",
                rf = "rf.label", hybrid = "hybrid")
widen <- function(df, suffix) {
  df %>% select(source, doc_id, all_of(unname(score_cols))) %>%
    rename_with(~ paste0(names(score_cols)[match(.x, score_cols)], "_", suffix),
                all_of(unname(score_cols)))
}
scores <- Reduce(function(x, y) inner_join(x, y, by = c("source", "doc_id")), lapply(c("01", "02", "03"), function(a) {
  widen(read_csv(out_path(paste0(a, "_scores.csv")), show_col_types = FALSE), paste0("a", as.integer(a)))
}))

archive_file <- c(pres = "Presidential_Library_Senti.xlsx", congress = "Congress_Senti.xlsx",
                  mofa = "MOFA_Senti.xlsx", peoplesdaily = "PeoplesDaily_Senti.xlsx")
archive <- lapply(archive_file, function(f) read_xl(file.path(OLD_SENTI_DIR, f)) %>% mutate(doc_id = row_number()))
scores_2023 <- bind_rows(lapply(names(archive), function(src) {
  archive[[src]] %>% mutate(source = src, hybrid = (svm.label + bing_sentiment + rf.label) / 3) %>% widen("2023")
}))
scores <- inner_join(scores, scores_2023, by = c("source", "doc_id"))
stopifnot(nrow(scores) == sum(sapply(archive, nrow)))

set.seed(123)
congress_ts_ids <- sample(4800, 2000) # same draw as time_series_analysis.Rmd and 04_compare_to_original.R

# ---- Match raw rows to scored documents -----------------------------------------------------
attach_scores <- function(raw, src, raw_cols, arch_cols, date_col = "date",
                          prep_raw = identity, prep_arch = identity) {
  arch <- archive[[src]]
  raw_key <- make_key(prep_raw(raw), raw_cols)
  arch_key <- make_key(prep_arch(arch), arch_cols)
  stopifnot(!anyDuplicated(raw_key), !anyDuplicated(arch_key))
  hit <- match(arch_key, raw_key)
  if (anyNA(hit)) stop(src, ": ", sum(is.na(hit)), " scored documents not found in the raw file")

  raw$source <- src
  raw$doc_id <- NA_integer_
  raw$doc_id[hit] <- arch$doc_id
  out <- raw %>%
    mutate(scored = !is.na(doc_id),
           in_ts_sample = scored & !is.na(.data[[date_col]]) &
             (src != "congress" | doc_id %in% congress_ts_ids)) %>%
    left_join(filter(scores, source == src) %>% select(-source), by = "doc_id")
  cat(sprintf("%-13s raw rows %6d | scored %5d (no date %4d) | in time series %5d\n",
              src, nrow(out), sum(out$scored), sum(out$scored & is.na(out[[date_col]])),
              sum(out$in_ts_sample)))
  out
}

pres <- read_xl(raw_path("Presidential_Library.xlsx")) %>%
  mutate(raw_file = "Presidential_Library.xlsx", raw_row = row_number())
pres <- attach_scores(pres, "pres", c("Titles", "date", "cleaned_text"), c("title", "date", "text"))

congress <- bind_rows(
  read_xl(raw_path("Congress1.xlsx")) %>% mutate(raw_file = "Congress1.xlsx", raw_row = row_number()),
  read_xl(raw_path("Congress2.xlsx")) %>% mutate(raw_file = "Congress2.xlsx", raw_row = row_number())
)
congress <- attach_scores(congress, "congress", c("Title", "Timestamp", "Text", "Subhead"),
                          c("title", "date", "orig_text", "subhead"), date_col = "Timestamp")

mfa <- read_xl(raw_path("MFA_US.xlsx")) %>% mutate(raw_file = "MFA_US.xlsx", raw_row = row_number())
mfa <- attach_scores(mfa, "mofa", c("link", "question", "answer"), c("link", "question", "answer"))

peoplesdaily <- read_xl(raw_path("PeoplesDailyUSA.xlsx")) %>%
  mutate(raw_file = "PeoplesDailyUSA.xlsx", raw_row = row_number())
peoplesdaily <- attach_scores(
  peoplesdaily, "peoplesdaily", c("headline", "date", "text"), c("title", "date", "orig_text"),
  prep_raw = function(d) mutate(d, headline = norm_text(headline), text = norm_text(text)),
  prep_arch = function(d) mutate(d, title = norm_text(title), orig_text = norm_text(orig_text))
)

# ---- Checks ------------------------------------------------------------------------------
# Matched rows carry the same date as the scored corpus (including the same missing dates).
corpora <- read_corpora() %>% select(source, doc_id, corpus_date = date)
for (d in list(pres = pres, congress = rename(congress, date = Timestamp), mofa = mfa, peoplesdaily = peoplesdaily)) {
  chk <- d %>% filter(scored) %>% inner_join(corpora, by = c("source", "doc_id"))
  stopifnot(nrow(chk) == sum(d$scored), identical(as.Date(chk$date), as.Date(chk$corpus_date)))
}

# ---- Export ------------------------------------------------------------------------------------
front <- c("source", "raw_file", "raw_row", "doc_id", "scored", "in_ts_sample")
export <- function(df, name) {
  # The raw files' unnamed first column (a leftover pandas index) reads in as "...1".
  df <- df %>% rename(any_of(c(unnamed_index = "...1"))) %>% select(all_of(front), everything())
  write_csv(df, out_path(name), na = "")
  cat("Wrote", name, "\n")
}
export(pres, "05_presidential_scored.csv")
export(congress, "05_congress_scored.csv")
export(mfa, "05_mfa_scored.csv")
export(peoplesdaily, "05_peoplesdaily_scored.csv")
cat("Done: export scored datasets\n")
