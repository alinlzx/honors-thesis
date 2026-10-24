# Clean the White House press briefings (raw/02_app_briefings.csv, American Presidency
# Project) into question-answer pairs, the same unit as the MFA press conferences.
#
# In:  raw/02_app_briefings.csv          one row per briefing, gaggle or press call
# Out: clean/03_briefings_paragraphs.csv one row per paragraph, all speakers, with
#                                        speaker, role, pair_id and China flags
#      clean/03_briefings_pairs.csv      one row per question-answer pair (and one per
#                                        opening-statement paragraph), with China flags
#                                        on the question and the answer
#
# Choices, and why:
# - A pair is a run of reporter paragraphs (the question, with any follow-ups) and the
#   officials' paragraphs that follow it, up to the next question. This mirrors the MFA
#   unit. Opening statements come before any question and cover many topics, so each
#   paragraph is its own row, the counterpart of an MFA opening remark.
# - Every administration official who answers counts as the US voice: press secretaries,
#   guest briefers (national security advisers, cabinet members) and anonymous "senior
#   administration officials". Roles are flagged so build/ can narrow this. Moderators and
#   call operators only manage the floor and are left out of answer text.
# - All pairs are kept, not just China ones, so the China share of briefings is available
#   as a salience measure. Relevance is decided in build/ from the flags.
# - Unlike the MFA source, multi-part questions are not split into sub-answers, so an
#   answer can cover China and something else. Paragraph-level China flags are kept so
#   build/ can score only the China paragraphs of an answer as a robustness check.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
})
source("config.R")

raw <- read_csv(file.path(RAW_DIR, "02_app_briefings.csv"), show_col_types = FALSE)

# ---- Briefing metadata -------------------------------------------------------------

docs <- raw %>%
  transmute(
    doc_id, date, title, url,
    president = case_when(
      str_detect(president, "Bush") ~ "Bush",
      str_detect(president, "Obama") ~ "Obama",
      str_detect(president, "Trump") ~ "Trump",
      str_detect(president, "Biden") ~ "Biden",
      TRUE ~ president # Vice Presidents and the First Lady, for their own press offices
    ),
    # Briefings run by the Vice President's or First Lady's press office, not the White
    # House press secretary's.
    other_office = str_detect(category, "Vice Presid|First Lady"),
    format = case_when(
      str_detect(title, regex("background", ignore_case = TRUE)) ~ "background",
      str_detect(title, regex("gaggle", ignore_case = TRUE)) ~ "gaggle",
      str_detect(title, regex("call|teleconference", ignore_case = TRUE)) ~ "call",
      TRUE ~ "briefing"
    ),
    text
  )

# The same transcript is occasionally posted twice under different titles.
n_raw <- nrow(docs)
docs <- docs %>%
  arrange(date, doc_id) %>%
  distinct(date, text, .keep_all = TRUE)
n_dup_docs <- n_raw - nrow(docs)

# ---- Paragraphs and speakers -------------------------------------------------------

# Labels are upper case and end in a colon ("MS. PSAKI:", "SENIOR ADMINISTRATION
# OFFICIAL:"); surnames such as "McCLELLAN" keep their mixed case. Requiring capitals
# keeps sentence openers like "Let me be clear:" from reading as labels.
TOKEN <- "(?:[A-Z][A-Z.'’\\-]*|(?:Mc|Mac|La|De)[A-Z][A-Z'’\\-]+)"
label_re <- str_c("^(Q|", TOKEN, "(?: ", TOKEN, "){0,6}|Operator)(?::|(?<=^Q) )\\s*")

QUESTIONER <- "^(Q|QUESTION|THE PRESS|PARTICIPANT|AUDIENCE MEMBER|REPORTER|PRESS)$"
FLOOR <- "^(MODERATOR|MODEARTOR|MODERTOR|MOERATOR|OPERATOR|Operator|AIDE|STAFF)$"
PRESIDENT <- "^THE PRESIDENT$"
ANONYMOUS <- "OFFICIAL" # "SENIOR ADMINISTRATION OFFICIAL", "WHITE HOUSE OFFICIAL", ...
# White House press secretaries and principal deputies who held regular briefings.
PRESS_SECRETARIES <- c(
  "FLEISCHER", "McCLELLAN", "SNOW", "PERINO", "FRATTO", "STANZEL", "GIBBS", "CARNEY",
  "EARNEST", "SCHULTZ", "BURTON", "SPICER", "SANDERS", "SHAH", "GIDLEY", "McENANY",
  "PSAKI", "JEAN-PIERRE", "BATES", "DALTON", "LEAVITT"
)
# A press secretary is labeled by surname alone or with an honorific ("MS. PSAKI",
# "LEAVITT"), never with a title, which separates them from namesakes such as
# "SECRETARY LEAVITT" (HHS) and "REPRESENTATIVE WASSERMAN SCHULTZ". One typo is
# allowed ("MR. EARENST"), and case is ignored ("MS. MCENANY").
TITLED <- "^(GENERAL|REPRESENTATIVE|SECRETARY|DR|DIRECTOR|ADMINISTRATOR|SENATOR|AMBASSADOR|GOVERNOR|ADMIRAL|CHAIR|ACTING|UNDER|DEPUTY)\\b"
is_press_secretary <- function(speaker) {
  u <- unique(speaker)
  sur <- toupper(str_extract(u, "[^ .]+$"))
  near <- apply(adist(sur, toupper(PRESS_SECRETARIES)), 1, min) <= if_else(str_length(sur) >= 6, 1, 0)
  hit <- setNames(near & !str_detect(u, TITLED), u)
  unname(hit[speaker])
}

# Stage directions in parentheses; bracketed redactions such as "[Senior administration
# official]" stay, since they stand in for words that were said.
STAGE <- regex("\\((laughter|applause|inaudible|cross-?talk|crosstalk|off-?mic|laughs|audio [^)]*|technical [^)]*)[^)]*\\)", ignore_case = TRUE)
TIME_LINE <- "^\\d{1,2}:\\d{2} ?[AP]\\.? ?M\\.?( [A-Z]{2,4})?\\.?$"

paras <- docs %>%
  select(doc_id, text) %>%
  mutate(text = str_split(text, "\\n\\n")) %>%
  unnest(text) %>%
  mutate(text = str_squish(str_remove_all(text, STAGE))) %>%
  filter(text != "") %>%
  group_by(doc_id) %>%
  mutate(para_src = row_number()) %>%
  ungroup() %>%
  mutate(label = str_trim(str_match(text, label_re)[, 2]))

# Header: location and time lines before the first label ("James S. Brady Press Briefing
# Room", "10:16 A.M. EST"). Trailer: "END" and anything after it (closing time stamps,
# links to video). Time stamps elsewhere are dropped too.
n_before <- nrow(paras)
paras <- paras %>%
  group_by(doc_id) %>%
  mutate(
    first_label = coalesce(first(which(!is.na(label))), n() + 1L),
    end_at = coalesce(first(which(str_detect(text, "^END\\b"))), n() + 1L)
  ) %>%
  filter(para_src >= first_label, para_src < end_at) %>%
  ungroup() %>%
  filter(!str_detect(text, TIME_LINE), !str_detect(text, "^To view the ")) %>%
  select(-first_label, -end_at)
n_hdr_trl <- n_before - nrow(paras)

paras <- paras %>%
  mutate(text = if_else(!is.na(label), str_squish(str_sub(text, str_length(str_match(text, label_re)[, 1]) + 1)), text)) %>%
  group_by(doc_id) %>%
  mutate(speaker = label) %>%
  fill(speaker, .direction = "down") %>% # unlabeled paragraphs continue the last speaker
  ungroup() %>%
  filter(text != "") %>%
  mutate(
    speaker = str_replace(speaker, "ADMINSTRATION", "ADMINISTRATION"), # source typo
    role = case_when(
      str_detect(speaker, QUESTIONER) ~ "question",
      str_detect(speaker, FLOOR) ~ "floor",
      str_detect(speaker, PRESIDENT) ~ "president",
      str_detect(speaker, ANONYMOUS) ~ "anonymous",
      is_press_secretary(speaker) ~ "press_secretary",
      TRUE ~ "official"
    )
  )

# ---- Pairs -------------------------------------------------------------------------

# "Go ahead." or a reporter's name between two question paragraphs only hands over the
# floor; it is not an answer, so the question run continues across it. Real one-word
# answers ("Yes.", "No.") are not treated this way.
PROCEDURAL <- "^(((Yes|Sure|Okay|OK|Yeah|Please)[,.] )?(Go ahead|Go for it|Please|Uh-huh|Mm-hmm|Sure|Yep)[.!]?|(?!(Yes|No|Right|Correct|Exactly|Absolutely|True|Nope|Never)\\.)[A-Z][a-z]+\\.)$"

paras <- paras %>%
  group_by(doc_id) %>%
  mutate(
    para_id = row_number(),
    procedural = role != "question" & str_detect(text, PROCEDURAL) &
      lag(role, default = "") == "question" & lead(role, default = "") == "question",
    is_q = role == "question" | procedural,
    # A new pair starts at the first question paragraph after an answer.
    pair_id = cumsum(is_q & !lag(is_q, default = FALSE)),
    opening = pair_id == 0,
    china_core = str_detect(text, CHINA_CORE),
    china_any = china_core | str_detect(text, CHINA_PERIPH)
  ) %>%
  ungroup()

ANSWER_ROLES <- c("press_secretary", "official", "anonymous", "president")

pairs <- paras %>%
  filter(!opening) %>%
  group_by(doc_id, pair_id) %>%
  summarise(
    question = str_c(text[is_q & !procedural], collapse = "\n\n"),
    answer = str_c(text[!is_q & role %in% ANSWER_ROLES], collapse = "\n\n"),
    answer_speakers = str_c(unique(speaker[!is_q & role %in% ANSWER_ROLES]), collapse = "; "),
    answer_roles = str_c(unique(role[!is_q & role %in% ANSWER_ROLES]), collapse = "; "),
    china_core_q = any(china_core[is_q]),
    china_any_q = any(china_any[is_q]),
    china_core_a = any(china_core[!is_q & role %in% ANSWER_ROLES]),
    china_any_a = any(china_any[!is_q & role %in% ANSWER_ROLES]),
    .groups = "drop"
  ) %>%
  mutate(opening = FALSE, para_id = NA_integer_)

# Opening statements: one row per paragraph, no question.
openings <- paras %>%
  filter(opening, role %in% ANSWER_ROLES) %>%
  transmute(doc_id, pair_id, para_id, question = NA_character_, answer = text,
            answer_speakers = speaker, answer_roles = role,
            china_core_q = FALSE, china_any_q = FALSE,
            china_core_a = china_core, china_any_a = china_any, opening = TRUE)

pairs <- bind_rows(openings, pairs) %>%
  filter(answer != "") %>% # questions nobody answered (end of briefing, crosstalk)
  inner_join(select(docs, doc_id, date, president, format, other_office), by = "doc_id") %>%
  arrange(date, doc_id, pair_id, para_id) %>%
  group_by(doc_id) %>%
  mutate(
    # The previous pair was about China, for follow-ups that do not name it ("And on
    # the tariffs?"). Opening paragraphs do not count as a previous pair.
    prev_china_core = lag(!opening & (china_core_q | china_core_a), default = FALSE) & !opening
  ) %>%
  ungroup() %>%
  mutate(n_chars_a = str_length(answer)) %>%
  select(doc_id, date, president, format, other_office, pair_id, para_id, opening,
         question, answer, answer_speakers, answer_roles, n_chars_a,
         china_core_q, china_any_q, china_core_a, china_any_a, prev_china_core)

# ---- Outputs -----------------------------------------------------------------------

para_out <- paras %>%
  inner_join(select(docs, doc_id, date), by = "doc_id") %>%
  select(doc_id, date, para_id, para_src, pair_id, opening, speaker, role, procedural,
         china_core, china_any, text)

write_csv(para_out, file.path(CLEAN_DIR, "03_briefings_paragraphs.csv"))
write_csv(pairs, file.path(CLEAN_DIR, "03_briefings_pairs.csv"))

qa <- filter(pairs, !opening)
message(sprintf("%d raw briefings -> %d (%d duplicate transcripts); %d header/trailer paragraphs dropped",
                n_raw, nrow(docs), n_dup_docs, n_hdr_trl))
message(sprintf("%d paragraphs; roles: %s", nrow(para_out),
                str_c(names(table(para_out$role)), table(para_out$role), sep = " ", collapse = ", ")))
message(sprintf("%d Q&A pairs and %d opening-statement paragraphs", nrow(qa), sum(pairs$opening)))
message(sprintf(
  "China (core) in answer: %d; in question only: %d; follow-up to a China pair only: %d; opening paragraphs: %d",
  sum(qa$china_core_a), sum(qa$china_core_q & !qa$china_core_a),
  sum(qa$prev_china_core & !qa$china_core_q & !qa$china_core_a),
  sum(pairs$opening & pairs$china_core_a)
))
