# 00 — Assemble the inputs shared by the three training approaches.
#
# Exports (to honors-thesis-original-data/sentiments/):
#   00_training_sample.csv  hand-coded US and China training documents
#   00_corpora.csv          the four corpora to be scored, with a stable doc_id
#
# Training sample: same construction as "senti analysis ML.Rmd" (Data Processing).
# Corpora: the documents scored in 2023, taken from the archived *_Senti.xlsx files
# (minus their old scores) so new and old scores line up document by document.
# doc_id = row number in the archived file.

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "functions.R")

# ---- Training sample ----------------------------------------------------------
read_sample <- function(f) suppressMessages(read_excel(file.path(SAMPLE_DIR, f)))

pres_sample <- read_sample("pres_sample.xlsx")
congress_sample <- read_sample("congress_sample.xlsx")
mofa_sample <- read_sample("mofa_sample.xlsx")
peoplesdaily_sample <- read_sample("peoplesdaily_sample.xlsx")

# For US
congress_sample <- congress_sample[, c("date", "title", "text", "pos_label", "neg_label")]
pres_sample <- pres_sample[!is.na(pres_sample$pos_label), c("date", "title", "text", "pos_label", "neg_label")]
us_sample <- rbind(pres_sample, congress_sample)

# For China
peoplesdaily_sample <- filter(peoplesdaily_sample, grepl("US", cleaned_text))
peoplesdaily_sample <- peoplesdaily_sample[, c("date", "headline", "cleaned_text", "pos_label", "neg_label", "relevance")]
colnames(peoplesdaily_sample) <- c("date", "title", "text", "pos_label", "neg_label", "relevance")
peoplesdaily_sample <- peoplesdaily_sample %>% subset(is.na(relevance))

# REBUILD: in mofa_sample.xlsx the coding sits in `pos_label` alone (P / N / NN,
# where NN = ambiguous) and `neg_label` is redundant (NN when P, NP otherwise).
# Recode into the pos_label (P/NP) + neg_label (N/NN) scheme used by the other
# samples. Without this, the 103 ambiguous MFA documents would be treated as
# negative. The thesis's China confusion matrix (30 N / 29 P in the test split)
# matches the recoded counts (143 N / 143 P), so the 2023 run used this recoding.
stopifnot(all(mofa_sample$pos_label %in% c("P", "N", "NN")))
mofa_sample <- mofa_sample %>%
  mutate(neg_label = ifelse(pos_label == "N", "N", "NN"),
         pos_label = ifelse(pos_label == "P", "P", "NP"))

mofa_sample <- mofa_sample[, c("date", "a_loc", "cleaned_text", "pos_label", "neg_label")]
colnames(mofa_sample) <- c("date", "title", "text", "pos_label", "neg_label")

china_sample <- rbind(mofa_sample, peoplesdaily_sample[, 1:5])

training_sample <- bind_rows(
  us_sample %>% mutate(country = "US",
                       sample_source = rep(c("pres", "congress"), c(nrow(pres_sample), nrow(congress_sample)))),
  china_sample %>% mutate(country = "China",
                          sample_source = rep(c("mofa", "peoplesdaily"), c(nrow(mofa_sample), nrow(peoplesdaily_sample))))
) %>% add_senti_label()

write_csv(training_sample, out_path("00_training_sample.csv"))
print(table(training_sample$sample_source, training_sample$senti_label))

# ---- Corpora to score ---------------------------------------------------------
old <- function(f) suppressMessages(read_excel(file.path(OLD_SENTI_DIR, f)))
pres <- old("Presidential_Library_Senti.xlsx")
congress <- old("Congress_Senti.xlsx")
mofa <- old("MOFA_Senti.xlsx")
peoplesdaily <- old("PeoplesDaily_Senti.xlsx")

corpora <- bind_rows(
  pres %>% transmute(source = "pres", doc_id = row_number(), date, title, subhead, text),
  congress %>% transmute(source = "congress", doc_id = row_number(), date, title, subhead, text),
  mofa %>% transmute(source = "mofa", doc_id = row_number(), date, title = spokesperson,
                     subhead = NA_character_, text),
  peoplesdaily %>% transmute(source = "peoplesdaily", doc_id = row_number(), date, title,
                             subhead = NA_character_, text)
)
stopifnot(!any(is.na(corpora$text)))
write_csv(corpora, out_path("00_corpora.csv"))
print(count(corpora, source))
