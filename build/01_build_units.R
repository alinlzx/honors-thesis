# Assemble what the sentiment specs need: every unit to score, and the labeled rows with
# fixed cross-validation folds, so all specs are compared on the same held-out rows.
#
# In:  clean/01a_presdocs_paragraphs.csv, clean/01a_presdocs_docs.csv, clean/02_mfa_qa.csv,
#      clean/03_briefings_paragraphs.csv, clean/03_briefings_pairs.csv,
#      clean/04_sample_data/04_sample_{presdocs,mfa,briefings}_reviewed.xlsx (final labels),
#      clean/04_sample_data/archive/04_sample_*.xlsx (which rows were coded by hand first),
#      clean/04_sample_data/04_sample_key.csv (frame membership and weights)
# Out: build/01_units.csv   one row per frame unit (the frames in clean/04_sample_data.R)
#      build/01_labels.csv  one row per labeled unit, with fold and collapsed outcomes
#
# Choices, and why:
# - `aux` holds the question or preceding paragraph. Only the relevance model reads it,
#   following the codebook: context says what the text refers to, not what its stance is.
# - stance3 merges mixed into neutral: a passage with both a clear positive and a clear
#   negative stance has no net direction, and mixed is thin in every source.
# - Folds keep a document's rows together, so a model is never tested on paragraphs from a
#   speech it trained on. MFA rows are grouped by press conference date.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(readxl)
  library(stringr)
  library(tidyr)
})
source("config.R")

set.seed(20261104)
N_FOLDS <- 5
SAMPLE_DIR <- file.path(CLEAN_DIR, "04_sample_data")
dir.create(BUILD_DIR, showWarnings = FALSE)

# Question and preceding text, without the blanks and placeholders.
join_aux <- function(...) {
  parts <- list(...)
  parts <- lapply(parts, function(x) if_else(is.na(x) | x == "opening_remark", "", as.character(x)))
  str_squish(do.call(paste, parts))
}

# ---- Units: same frames as clean/04_sample_data.R ----------------------------------

pd_docs <- read_csv(file.path(CLEAN_DIR, "01a_presdocs_docs.csv"), show_col_types = FALSE) %>%
  select(doc_id, date, genre)
pd <- read_csv(file.path(CLEAN_DIR, "01a_presdocs_paragraphs.csv"), show_col_types = FALSE) %>%
  arrange(doc_id, para_id) %>%
  group_by(doc_id) %>%
  mutate(context = lag(str_c(coalesce(speaker, "[unlabeled]"), ": ", text))) %>%
  ungroup() %>%
  filter(is_president, china_core) %>%
  inner_join(pd_docs, by = "doc_id") %>%
  transmute(unit_id = str_c(doc_id, "_", para_id), source = "presdocs", group = doc_id, date,
            genre, text, aux = join_aux(context))

mf <- read_csv(file.path(CLEAN_DIR, "02_mfa_qa.csv"), show_col_types = FALSE) %>%
  filter(us_a | (us_q & !is_split)) %>%
  transmute(unit_id = as.character(id), source = "mfa", group = as.character(date), date,
            genre = NA_character_, text = answer, aux = join_aux(question))

br_questions <- read_csv(file.path(CLEAN_DIR, "03_briefings_pairs.csv"), show_col_types = FALSE) %>%
  filter(!opening) %>%
  select(doc_id, pair_id, question)
br <- read_csv(file.path(CLEAN_DIR, "03_briefings_paragraphs.csv"), show_col_types = FALSE) %>%
  arrange(doc_id, para_id) %>%
  group_by(doc_id) %>%
  mutate(context = lag(str_c(speaker, ": ", text))) %>%
  ungroup() %>%
  filter(china_core, role %in% c("press_secretary", "official", "anonymous")) %>%
  left_join(br_questions, by = c("doc_id", "pair_id")) %>%
  transmute(unit_id = str_c(doc_id, "_", para_id), source = "briefings", group = doc_id, date,
            genre = role, text, aux = join_aux(question, context))

units <- bind_rows(pd, mf, br)
stopifnot(!anyDuplicated(paste(units$source, units$unit_id)))
stopifnot(nrow(pd) == 7891, nrow(mf) == 11192, nrow(br) == 7082)

# ---- Labels ------------------------------------------------------------------------

key <- read_csv(file.path(SAMPLE_DIR, "04_sample_key.csv"), show_col_types = FALSE,
                col_types = cols(unit_id = col_character())) %>%
  select(sample_id, in_frame, weight, year)

read_labels <- function(source_name) {
  final <- read_excel(file.path(SAMPLE_DIR, sprintf("04_sample_%s_reviewed.xlsx", source_name)),
                      sheet = "sample", guess_max = 5000)
  first <- read_excel(file.path(SAMPLE_DIR, "archive", sprintf("04_sample_%s.xlsx", source_name)),
                      sheet = "sample", guess_max = 5000)
  aux <- switch(source_name,
    mfa = join_aux(final$question),
    briefings = join_aux(final$question, final$context),
    presdocs = join_aux(final$context)
  )
  group <- switch(source_name,
    mfa = as.character(as.Date(final$date)),
    str_remove(final$unit_id, "_[^_]+$")
  )
  tibble(
    sample_id = final$sample_id, unit_id = as.character(final$unit_id), source = source_name,
    group = group, date = as.Date(final$date), text = final$text, aux = aux,
    about_target = final$about_target, stance = final$stance,
    human_coded = final$sample_id %in% first$sample_id[!is.na(first$about_target)]
  )
}

labels <- bind_rows(lapply(c("presdocs", "mfa", "briefings"), read_labels)) %>%
  left_join(key, by = "sample_id") %>%
  mutate(
    stance3 = case_when(about_target == "no" ~ NA_character_,
                        stance == "mixed" ~ "neutral",
                        TRUE ~ stance),
    outcome4 = coalesce(stance3, "off_target")
  )
stopifnot(!anyNA(labels$about_target), all(labels$outcome4 %in% c("off_target", "neg", "neutral", "pos")))

# Every in-frame labeled row must be the same text as its unit, or the labels don't apply.
check <- labels %>%
  filter(in_frame) %>%
  left_join(select(units, source, unit_id, unit_text = text), by = c("source", "unit_id"))
stopifnot(!anyNA(check$unit_text), mean(str_squish(check$text) == str_squish(check$unit_text)) == 1)

# ---- Folds -------------------------------------------------------------------------

# Greedy assignment: take document groups in random order and give each to the fold where
# its outcomes are least represented so far, source by source.
assign_folds <- function(d) {
  counts <- matrix(0, N_FOLDS, 4, dimnames = list(NULL, c("off_target", "neg", "neutral", "pos")))
  g <- d %>% count(group, outcome4) %>% pivot_wider(names_from = outcome4, values_from = n, values_fill = 0)
  for (col in setdiff(colnames(counts), names(g))) g[[col]] <- 0L
  g <- g[sample.int(nrow(g)), ]
  g$fold <- NA_integer_
  for (i in seq_len(nrow(g))) {
    add <- unlist(g[i, colnames(counts)])
    cost <- apply(counts, 1, function(row) sum((row + add)^2))
    best <- which(cost == min(cost))
    f <- best[sample.int(length(best), 1)]
    counts[f, ] <- counts[f, ] + add
    g$fold[i] <- f
  }
  left_join(d, select(g, group, fold), by = "group")
}

labels <- labels %>%
  group_split(source) %>%
  lapply(assign_folds) %>%
  bind_rows() %>%
  arrange(sample_id)

# ---- Outputs -----------------------------------------------------------------------

write_csv(units, file.path(BUILD_DIR, "01_units.csv"))
write_csv(labels, file.path(BUILD_DIR, "01_labels.csv"))

message(sprintf("Units: %d. Labeled: %d, %d in frame.", nrow(units), nrow(labels), sum(labels$in_frame)))
print(count(labels, source, fold, outcome4) %>% pivot_wider(names_from = outcome4, values_from = n, values_fill = 0))
print(summarise(labels, max_group = max(table(group)), groups = n_distinct(group), .by = source))
