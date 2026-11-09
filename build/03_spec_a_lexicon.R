# Spec A: Bing Liu and AFINN lexicon scores, the thesis's baseline.
#
# In:  build/01_units.csv, build/01_labels.csv
# Out: build/03_spec_a_labeled.csv  scores for labeled rows
#      build/03_spec_a_scores.csv   scores for all frame units
#
# Choices, and why:
# - Lexicon words come from syuzhet's copies of both lists, so there is nothing to download
#   at run time and no training step.
# - Score = net lexicon value per 100 words, so longer passages don't score more extreme.
# - The class is the sign of the score: above 0 pos, below 0 neg, exactly 0 neutral. There is
#   no tuned neutral band, because A should stay the plain baseline. The raw score is what
#   the ROC curves use.
# - No relevance filter. A lexicon can't tell who a word is about, and that cost should show
#   in its results.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(syuzhet)
})
source("config.R")

bing <- get_sentiment_dictionary("bing") %>% distinct(word, .keep_all = TRUE)
afinn <- get_sentiment_dictionary("afinn") %>% distinct(word, .keep_all = TRUE)
bing_values <- setNames(bing$value, bing$word)
afinn_values <- setNames(afinn$value, afinn$word)

score_text <- function(text) {
  tokens <- str_extract_all(str_to_lower(text), "[a-z]+(?:[-'][a-z]+)*")
  n <- lengths(tokens)
  net <- function(values) {
    vapply(tokens, function(w) sum(values[w], na.rm = TRUE), numeric(1))
  }
  tibble(
    n_words = n,
    bing = 100 * net(bing_values) / pmax(n, 1),
    afinn = 100 * net(afinn_values) / pmax(n, 1)
  )
}

classify <- function(x) case_when(x > 0 ~ "pos", x < 0 ~ "neg", TRUE ~ "neutral")

add_scores <- function(d) {
  bind_cols(d, score_text(d$text)) %>%
    mutate(bing_class = classify(bing), afinn_class = classify(afinn))
}

labeled <- read_csv(file.path(BUILD_DIR, "01_labels.csv"), show_col_types = FALSE,
                    col_types = cols(unit_id = col_character())) %>%
  select(sample_id, text) %>%
  add_scores() %>%
  select(-text)
units <- read_csv(file.path(BUILD_DIR, "01_units.csv"), show_col_types = FALSE,
                  col_types = cols(unit_id = col_character())) %>%
  select(unit_id, source, text) %>%
  add_scores() %>%
  select(-text)

write_csv(labeled, file.path(BUILD_DIR, "03_spec_a_labeled.csv"))
write_csv(units, file.path(BUILD_DIR, "03_spec_a_scores.csv"))

message(sprintf("Scored %d labeled rows and %d units.", nrow(labeled), nrow(units)))
print(summarise(units, mean_bing = mean(bing), mean_afinn = mean(afinn),
                zero_bing = mean(bing == 0), zero_afinn = mean(afinn == 0), .by = source))
