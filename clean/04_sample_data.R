# Draw the hand-coding samples for the sentiment classifiers: presidential paragraphs,
# MFA question-answer pairs and White House briefing paragraphs, each about the other
# country.
#
# In:  clean/01a_presdocs_paragraphs.csv, clean/01a_presdocs_docs.csv
#      clean/02_mfa_qa.csv, clean/04_sample_data/mofa_sample.xlsx (the thesis's MFA sample)
#      clean/03_briefings_paragraphs.csv, clean/03_briefings_pairs.csv,
#      raw/02_app_briefings.csv (titles and URLs only)
# Out: clean/04_sample_data/04_sample_presdocs.xlsx   300 paragraphs to code
#      clean/04_sample_data/04_sample_mfa.xlsx        300 old + 150 new pairs to code
#      clean/04_sample_data/04_sample_briefings.xlsx  300 paragraphs to code
#      clean/04_sample_data/04_sample_key.csv         sampling frame, weights and the
#                                                     thesis's old MFA labels
#
# Choices, and why:
# - The labels are attitude toward the other country, not general tone. The thesis
#   coded general sentiment, so its 300 MFA pairs are re-coded too. Their old labels go
#   to the key file, not the coding sheet, so the re-code is blind.
# - Frames: president paragraphs with core China terms; MFA pairs where the answer
#   mentions the US, or the question does for unsplit rows (analysis_recipes.md section
#   2); briefing paragraphs with core China terms spoken by the press secretary, other
#   officials or anonymous officials. The president's own briefing paragraphs are left
#   out because they may duplicate the presidential documents.
# - Stratified by year with equal allocation, not proportional, so thin years and
#   administrations get enough cases to check whether classifier error drifts over
#   time. A year with fewer units than its share gives all it has, and the rest goes to
#   the other years. The key carries weights (frame units / sampled units in the year)
#   so accuracy can be estimated for the whole frame.
# - The thesis's MFA sample is kept whole and topped up with 150 pairs from 2022-2025,
#   which it does not cover. Its 15 pairs outside today's frame stay in as checks of the
#   "about the US" code and get no weight.
# - Rows are shuffled so coding order does not follow time.
# - Coded files are never overwritten: delete them, or set OVERWRITE_SAMPLES=true, to
#   redraw.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(readxl)
  library(stringr)
  library(writexl)
})
source("config.R")

set.seed(20261024)
N_SAMPLE <- 300
N_MFA_NEW <- 150
OUT_DIR <- file.path(CLEAN_DIR, "04_sample_data")
dir.create(OUT_DIR, showWarnings = FALSE)

# Equal allocation across strata: every stratum gets the same number, capped at its size,
# with the remainder handed out one unit at a time in random order.
allocate <- function(N_h, n) {
  a <- integer(length(N_h))
  while (sum(a) < n) {
    open <- which(a < N_h)
    if (length(open) == 0) stop("frame smaller than sample")
    for (h in open[sample.int(length(open))]) {
      if (sum(a) == n) break
      a[h] <- a[h] + 1L
    }
  }
  a
}

# Sample n units from frame, stratified by year.
draw <- function(frame, n) {
  sizes <- count(frame, year, name = "N_h")
  sizes$n_h <- allocate(sizes$N_h, n)
  frame %>%
    inner_join(sizes, by = "year") %>%
    group_by(year) %>%
    filter(rank(runif(n())) <= first(n_h)) %>%
    ungroup() %>%
    select(-N_h, -n_h)
}

# Coding columns, left blank.
add_codes <- function(d) {
  mutate(d, about_target = NA_character_, stance = NA_character_, notes = NA_character_)
}

# ---- Presidential documents --------------------------------------------------------

pd_docs <- read_csv(file.path(CLEAN_DIR, "01a_presdocs_docs.csv"), show_col_types = FALSE) %>%
  select(doc_id, date, president, genre, title, url)

pd_frame <- read_csv(file.path(CLEAN_DIR, "01a_presdocs_paragraphs.csv"), show_col_types = FALSE) %>%
  arrange(doc_id, para_id) %>%
  group_by(doc_id) %>%
  # The paragraph before, so a coder can see the question or the subject being answered.
  mutate(context = lag(str_c(coalesce(speaker, "[unlabeled]"), ": ", text))) %>%
  ungroup() %>%
  filter(is_president, china_core) %>%
  inner_join(pd_docs, by = "doc_id") %>%
  mutate(unit_id = str_c(doc_id, "_", para_id), year = as.integer(format(date, "%Y")))

pd <- draw(pd_frame, N_SAMPLE)

# ---- MFA press conferences ---------------------------------------------------------

mfa <- read_csv(file.path(CLEAN_DIR, "02_mfa_qa.csv"), show_col_types = FALSE) %>%
  mutate(
    year = as.integer(format(date, "%Y")),
    in_frame = us_a | (us_q & !is_split),
    unit_id = as.character(id)
  )

# The thesis sample matches the clean file on answer text (all 300 rows); its own ids are
# off by one for one row. Its two binary columns combine into one 3-class label.
old <- read_excel(file.path(OUT_DIR, "mofa_sample.xlsx")) %>%
  transmute(
    answer = str_squish(answer),
    old_label = case_when(pos_label == "P" ~ "pos", pos_label == "N" ~ "neg", TRUE ~ "neutral")
  ) %>%
  inner_join(mfa, by = "answer") %>%
  mutate(origin = "thesis")
stopifnot(nrow(old) == 300)

mfa_new <- mfa %>%
  filter(in_frame, year >= 2022, !id %in% old$id) %>%
  draw(N_MFA_NEW) %>%
  mutate(origin = "new", old_label = NA_character_)

mf <- bind_rows(old, mfa_new)

# ---- White House briefings ---------------------------------------------------------

br_docs <- read_csv(file.path(RAW_DIR, "02_app_briefings.csv"), show_col_types = FALSE,
                    col_select = c(doc_id, title, url))
br_pairs <- read_csv(file.path(CLEAN_DIR, "03_briefings_pairs.csv"), show_col_types = FALSE)
br_meta <- distinct(br_pairs, doc_id, president, format, other_office)
br_questions <- br_pairs %>%
  filter(!opening) %>%
  select(doc_id, pair_id, question)

br_frame <- read_csv(file.path(CLEAN_DIR, "03_briefings_paragraphs.csv"), show_col_types = FALSE) %>%
  arrange(doc_id, para_id) %>%
  group_by(doc_id) %>%
  mutate(context = lag(str_c(speaker, ": ", text))) %>%
  ungroup() %>%
  filter(china_core, role %in% c("press_secretary", "official", "anonymous")) %>%
  left_join(br_questions, by = c("doc_id", "pair_id")) %>%
  inner_join(br_meta, by = "doc_id") %>%
  inner_join(br_docs, by = "doc_id") %>%
  mutate(unit_id = str_c(doc_id, "_", para_id), year = as.integer(format(date, "%Y")))

br <- draw(br_frame, N_SAMPLE)

# ---- Coding sheets -----------------------------------------------------------------

codebook <- tibble(
  column = c("about_target", "about_target", "stance", "stance", "stance", "stance", "notes"),
  value = c("yes", "no", "neg", "pos", "mixed", "neutral", "free text"),
  meaning = c(
    "The text says something about the target country (China for the US sheets, the US for the MFA sheet): its government, leaders, policies, actions, or relations with it.",
    "It does not (the mention is incidental, or about another country). Leave stance blank.",
    "The speaker criticizes, opposes, accuses, warns or makes demands of the target, or presents it as a threat.",
    "The speaker praises or welcomes the target, or stresses cooperation, agreement or goodwill with it.",
    "Both a clear negative and a clear positive stance toward the target.",
    "The target is mentioned without an evaluative stance: schedules, factual readouts, \"I have no information on that\".",
    "Anything worth flagging: unclear reference, garbled text, wrong speaker."
  )
)
rules <- tibble(rule = c(
  "Code the speaker's attitude toward the target country, not the overall tone of the text. Warm words about a third country are not positive toward the target.",
  "Code only the text column. The context and question columns are there to work out what the text refers to.",
  "Code each row on its own; rows are in random order on purpose."
))

shuffle <- function(d) d[sample.int(nrow(d)), ]

pd_sheet <- pd %>%
  shuffle() %>%
  transmute(sample_id = sprintf("P%03d", row_number()), unit_id, date, president, genre,
            title, context, text, url) %>%
  add_codes()
mf_sheet <- mf %>%
  shuffle() %>%
  transmute(sample_id = sprintf("M%03d", row_number()), unit_id, date, spokesperson,
            question, text = answer, url = link) %>%
  add_codes()
br_sheet <- br %>%
  shuffle() %>%
  transmute(sample_id = sprintf("B%03d", row_number()), unit_id, date, president, speaker,
            role, title, question, context, text, url) %>%
  add_codes()

# ---- Key: frame sizes and weights --------------------------------------------------

weights <- function(sample, frame, source) {
  N <- count(frame, year, name = "frame_n_year")
  n <- sample %>% filter(in_frame) %>% count(year, name = "sample_n_year")
  sample %>%
    left_join(N, by = "year") %>%
    left_join(n, by = "year") %>%
    mutate(source = source, weight = if_else(in_frame, frame_n_year / sample_n_year, NA_real_))
}

key <- bind_rows(
  pd %>% mutate(in_frame = TRUE, origin = "new") %>%
    weights(pd_frame, "presdocs") %>% left_join(select(pd_sheet, unit_id, sample_id), by = "unit_id"),
  mf %>% weights(filter(mfa, in_frame), "mfa") %>%
    left_join(select(mf_sheet, unit_id, sample_id), by = "unit_id"),
  br %>% mutate(in_frame = TRUE, origin = "new") %>%
    weights(br_frame, "briefings") %>% left_join(select(br_sheet, unit_id, sample_id), by = "unit_id")
) %>%
  select(source, sample_id, unit_id, date, year, origin, in_frame, frame_n_year,
         sample_n_year, weight, old_label)

# ---- Outputs -----------------------------------------------------------------------

sheets <- list(
  "04_sample_presdocs.xlsx" = pd_sheet,
  "04_sample_mfa.xlsx" = mf_sheet,
  "04_sample_briefings.xlsx" = br_sheet
)
overwrite <- tolower(Sys.getenv("OVERWRITE_SAMPLES")) == "true"
for (f in names(sheets)) {
  path <- file.path(OUT_DIR, f)
  if (file.exists(path) && !overwrite) {
    message("Kept existing ", f, " (may hold coding); set OVERWRITE_SAMPLES=true to redraw")
    next
  }
  write_xlsx(list(sample = sheets[[f]], codebook = codebook, rules = rules), path)
}
if (!file.exists(file.path(OUT_DIR, "04_sample_key.csv")) || overwrite) {
  write_csv(key, file.path(OUT_DIR, "04_sample_key.csv"))
}

message(sprintf("Frames: presdocs %d, MFA %d, briefings %d",
                nrow(pd_frame), sum(mfa$in_frame), nrow(br_frame)))
message(sprintf("Samples: presdocs %d, MFA %d (%d thesis, %d of them outside the frame; %d new), briefings %d",
                nrow(pd_sheet), nrow(mf_sheet), nrow(old), sum(!old$in_frame), nrow(mfa_new), nrow(br_sheet)))
