# Clean the Chinese MFA press conference corpus (raw/03_CMFA_PressCon_v6.xlsx; Mochtak &
# Turcsanyi v6, Oct 2002 - 2025) and flag the exchanges that mention the US.
#
# In:  raw/03_CMFA_PressCon_v6.xlsx  one row per question-answer pair
# Out: clean/02_mfa_qa.csv           one row per question-answer pair, all topics, with
#                                    US-mention flags for the question and the answer
#
# Choices, and why:
# - The unit is the question-answer pair, as in the source. The spokesperson's answer is
#   the text to score; the journalist's question is kept only to decide relevance, the
#   same way 01a keeps reporters' questions to the president.
# - All pairs are kept, not just US ones, so the share of exchanges about the US (an
#   attention measure) and alternative relevance filters are available downstream.
# - Questions that bundle several sub-questions were split by the source into one row
#   per sub-answer (id_split "8_1", "8_2"), each carrying the full question. A US mention
#   in such a question may belong to a different sub-question, so split rows are flagged
#   and build/ can require the US mention in the answer for them.
# - The source's own sentiment score (a_sentiment) is kept as an outside benchmark for
#   the classifiers; the lemmatized text and question-side NER columns are dropped.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(readxl)
  library(stringr)
})
source("config.R")

mfa <- read_excel(file.path(RAW_DIR, "03_CMFA_PressCon_v6.xlsx"), col_types = "text")
n_raw <- nrow(mfa)

mfa <- mfa %>%
  transmute(
    id = as.integer(id),
    id_orig = as.integer(id_orig),
    id_split,
    # Excel serial dates; "-" for one 2004 session whose date the source could not parse.
    date = as.Date(suppressWarnings(as.numeric(date)), origin = "1899-12-30"),
    spokesperson = na_if(na_if(spokesperson, "-"), "missing"),
    opening_remark = question == "opening_remark",
    question = if_else(opening_remark, NA_character_, str_squish(question)),
    answer = str_squish(answer),
    who_asked = na_if(who_asked, "-"),
    a_loc = na_if(a_loc, "-"),
    a_org = na_if(a_org, "-"),
    a_per = na_if(a_per, "-"),
    ms_sentiment = as.numeric(a_sentiment),
    link
  ) %>%
  group_by(id_orig) %>%
  mutate(is_split = n() > 1) %>%
  ungroup()

n_nodate <- sum(is.na(mfa$date))
mfa <- filter(mfa, !is.na(date))

# Placeholder answers carry no text to score.
n_empty <- sum(is.na(mfa$answer) | mfa$answer %in% c("-", "No Answer", ""))
mfa <- filter(mfa, !is.na(answer), !answer %in% c("-", "No Answer", ""))

# The same answer can be attached to two sub-questions of one split question, or
# transcribed twice in one session. Keep the first.
n_before <- nrow(mfa)
mfa <- mfa %>%
  arrange(id) %>%
  distinct(date, answer, .keep_all = TRUE)
n_dup <- n_before - nrow(mfa)

# ---- US mentions -------------------------------------------------------------------

# Case-sensitive, so the pronoun "us" does not match "US". Excludes currency ("US$",
# "US dollar"), other Americas ("Latin America"), and the Washington Post. Officials
# are matched by surname only where the surname is unambiguous in this corpus.
US <- str_c(
  "\\bUnited States\\b|\\bUSA\\b|\\bU\\.S\\.(?!\\s?\\$| ?dollars?)|\\bUS\\b(?!\\s?\\$| dollars?)",
  "|(?<!Latin |South |Central |North |Latin-)\\bAmerica(ns?)?\\b",
  "|\\bWashington\\b(?! Post)|White House|Pentagon|State Department|Department of State",
  "|\\b(Bush|Obama|Trump|Biden|Powell|Condoleezza Rice|Secretary Rice|Hillary|Kerry|Tillerson",
  "|Pompeo|Blinken|Rubio|Rumsfeld|Mattis|Esper|Hegseth|Paulson|Geithner|Mnuchin|Yellen",
  "|Bessent|Lighthizer|Pelosi|AUKUS)\\b"
)

mfa <- mfa %>%
  mutate(
    us_q = coalesce(str_detect(question, US), FALSE),
    us_a = str_detect(answer, US),
    # The source's NER on the answer, as a cross-check on the regex.
    us_ner_a = coalesce(str_detect(a_loc, "\\b(US|U\\.S\\.|United States|America|USA)\\b"), FALSE)
  )

write_csv(mfa, file.path(CLEAN_DIR, "02_mfa_qa.csv"))

message(sprintf(
  "%d raw pairs -> %d kept (%d undated, %d empty answers, %d duplicate answers dropped)",
  n_raw, nrow(mfa), n_nodate, n_empty, n_dup
))
message(sprintf(
  "US mentioned in answer: %d; in question only: %d (of which split: %d); in neither: %d",
  sum(mfa$us_a), sum(mfa$us_q & !mfa$us_a), sum(mfa$us_q & !mfa$us_a & mfa$is_split),
  sum(!mfa$us_q & !mfa$us_a)
))
message(sprintf(
  "Regex vs source NER on answers: both %d, regex only %d, NER only %d",
  sum(mfa$us_a & mfa$us_ner_a), sum(mfa$us_a & !mfa$us_ner_a), sum(!mfa$us_a & mfa$us_ner_a)
))
