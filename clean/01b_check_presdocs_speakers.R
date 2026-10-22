# Check the speaker attribution in clean/01a against a gold standard.
#
# DCPD documents (2009 on) mark speaker labels in italics in the source HTML
# ("<I>The President.</I> Hello, everybody."). The plain text that 01a parses has lost
# that markup, so the italic labels are an independent check of the label regex. WCPD
# (2002-2008) has no markup, but the two collections use the same labeling conventions,
# so DCPD accuracy is a reasonable guide to WCPD accuracy.
#
# In:  raw/govinfo_cpd/docs/DCPD-*.htm, raw/01_govinfo_presdocs.csv, clean/01a_presdocs_paragraphs.csv
# Out: clean/01b_presdocs_speaker_check.csv  paragraphs where 01a and the gold standard
#                                            disagree on is_president, for reading

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
})
source("config.R")

raw <- read_csv(file.path(RAW_DIR, "01_govinfo_presdocs.csv"), show_col_types = FALSE) %>%
  filter(collection == "DCPD")
paras <- read_csv(file.path(CLEAN_DIR, "01a_presdocs_paragraphs.csv"), show_col_types = FALSE)
docs <- read_csv(file.path(CLEAN_DIR, "01a_presdocs_docs.csv"), show_col_types = FALSE) %>%
  filter(collection == "DCPD", spoken)

# Paragraphs of a DCPD page, split the way scrape/extract_text does, with the italic
# label (if any) that opens each one. Pages come in two formats: older ones wrap labels
# in <I>, newer ones (most of 2020 on) style them with an italic CSS class, either on the
# paragraph (with the speech in <span class="p">) or on a leading <span>.
gold_paras <- function(path) {
  body <- str_replace_all(str_c(readLines(path, warn = FALSE), collapse = " "), "\\s+", " ")
  italic <- str_match_all(body, "\\.([\\w-]+) \\{[^}]*font-style: italic")[[1]][, 2]
  blocks <- str_split(body, regex("(?=<p\\b)|</p\\s*>", ignore_case = TRUE))[[1]]
  blocks <- blocks[!str_detect(blocks, "^</?p\\b[^>]*>$")]
  blocks <- str_replace_all(blocks, "(?i)</i>\\s*<i>", "") # merge adjacent italic runs
  plain <- str_squish(str_replace_all(str_remove_all(blocks, "<[^>]+>"), "&nbsp;|&#160;", " "))

  # <I> format; the period can sit inside or just after the italics.
  m <- str_match(blocks, "(?i)^\\s*(?:<(?!i>)[^>]+>\\s*)*<i>\\s*([^<]{1,100}?)\\s*</i>\\s*(?:<[^>]+>\\s*)*(\\.)?")
  lab_i <- if_else(!is.na(m[, 2]) & (str_detect(m[, 2], "\\.$") | !is.na(m[, 3])), m[, 2], NA_character_)
  # CSS format: italic paragraph class with the label before the first <span>, or a
  # leading italic <span>.
  p_cls <- str_match(blocks, "^\\s*<p\\b[^>]*class=\"([\\w-]+)\"[^>]*>([^<]{1,100})")
  s_cls <- str_match(blocks, "^\\s*<p\\b[^>]*>\\s*<span class=\"([\\w-]+)\"[^>]*>([^<]{1,100})</span>")
  lab_css <- case_when(
    p_cls[, 2] %in% italic ~ str_trim(p_cls[, 3]),
    s_cls[, 2] %in% italic ~ str_trim(s_cls[, 3])
  )
  lab_css <- if_else(str_detect(lab_css, "\\.$"), lab_css, NA_character_)

  tibble(gold_label = str_remove(coalesce(lab_i, lab_css), "\\.$"), plain = plain) %>%
    filter(plain != "") %>%
    mutate(para_src = row_number())
}

gold <- docs %>%
  select(doc_id, president) %>%
  mutate(g = lapply(file.path(RAW_DIR, "govinfo_cpd", "docs", str_c(doc_id, ".htm")), gold_paras)) %>%
  unnest(g)

# Use only documents whose paragraph count matches the scraped text, so positions align.
n_raw <- raw %>%
  transmute(doc_id, n_raw = lengths(str_split(text, "\\n\\n")))
aligned <- gold %>%
  count(doc_id, name = "n_gold") %>%
  inner_join(n_raw, by = "doc_id") %>%
  filter(n_gold == n_raw) %>%
  pull(doc_id)

# Gold speaker: carry each italic label forward; unlabeled openings are the president's,
# the same default 01a uses.
gold <- gold %>%
  filter(doc_id %in% aligned) %>%
  group_by(doc_id) %>%
  mutate(gold_speaker = gold_label) %>%
  fill(gold_speaker, .direction = "down") %>%
  ungroup() %>%
  mutate(
    gold_speaker = coalesce(gold_speaker, "The President"),
    gold_president = gold_speaker == "The President" |
      str_detect(gold_speaker, str_c("^President (.+ )?", president, "$"))
  )

cmp <- paras %>%
  filter(doc_id %in% aligned) %>%
  inner_join(gold, by = c("doc_id", "para_src"))

message(sprintf("%d of %d spoken DCPD documents aligned; %d paragraphs compared",
                length(aligned), nrow(docs), nrow(cmp)))
message("Label detected (rows: 01a, cols: gold italic label present):")
print(table(regex = !is.na(cmp$label), gold = !is.na(cmp$gold_label)))
message("is_president (rows: 01a, cols: gold):")
print(table(regex = cmp$is_president, gold = cmp$gold_president))
message(sprintf("is_president agreement: %.2f%%; among China-mentioning paragraphs: %.2f%%",
                100 * mean(cmp$is_president == cmp$gold_president),
                100 * mean((cmp$is_president == cmp$gold_president)[cmp$china_any])))

bad <- cmp %>%
  filter(is_president != gold_president) %>%
  select(doc_id, para_src, speaker, gold_speaker, is_president, gold_president, label, gold_label, china_any, text)
write_csv(bad, file.path(CLEAN_DIR, "01b_presdocs_speaker_check.csv"))
message("Most common disagreements (01a speaker -> gold speaker):")
print(head(count(bad, speaker, gold_speaker, sort = TRUE), 25))
