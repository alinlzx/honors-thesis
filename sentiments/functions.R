# Shared paths and helper functions for the sentiment rebuild.
#
# Every function below is copied from the original notebooks
# ("sentiment and ts analysis/senti analysis ML.Rmd" and
# "sentiment analysis & EDA.Rmd"). Changes are limited to what is needed to make
# the code run end to end; each one is marked with "# REBUILD:".
#
# Run scripts from the repo root, e.g. `Rscript sentiments/01_approach1_binary.R`.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(readxl)
  library(tm)
  library(textstem)
  library(splitTools)
  library(caret)
  library(e1071)
  library(randomForest)
  library(pROC)
  library(syuzhet)
})

# ---- Paths -------------------------------------------------------------------
# REBUILD: replaces the hard-coded ~/PycharmProjects/thesis/... paths.
REPO_ROOT <- if (file.exists("sentiments/functions.R")) "." else ".."
DATA_DIR <- Sys.getenv("THESIS_DATA_DIR",
                       file.path(REPO_ROOT, "..", "honors-thesis-original-data"))
SAMPLE_DIR <- file.path(DATA_DIR, "raw", "coded_samples")   # hand-coded training samples
OLD_SENTI_DIR <- file.path(DATA_DIR, "sentiments", "_archive") # 2023 scored files
OUT_DIR <- file.path(DATA_DIR, "sentiments")                  # rebuild outputs
out_path <- function(name) file.path(OUT_DIR, name)

SEED <- 2023

# ---- Lexicon scores (sentiment analysis & EDA.Rmd) ----------------------------
get_senti <- function(df) {
  df <- df %>% mutate(afinn_sentiment = get_sentiment(text, method = "afinn"),
                      bing_sentiment = get_sentiment(text, method = "bing"))
  return(df)
}

# ---- Text processing ----------------------------------------------------------
vectorizer_tfidf <- function(df) {
  # REBUILD: warnings ("transformation drops documents", "empty document(s)")
  # are silenced; the steps themselves are unchanged.
  corpus <- suppressWarnings(
    Corpus(VectorSource(df$text)) %>%
      tm_map(content_transformer(function(x) removeWords(x, stopwords("en")))) %>% # removes stopwords
      tm_map(lemmatize_strings) # lemmatizes words
  )

  corpus_dtm <- suppressWarnings(
    DocumentTermMatrix(corpus) %>% # creates document-term matrix
      weightTfIdf() # tf-idf
  ) %>% as.matrix()

  # REBUILD (note only): `-zero_var_cols` negates a logical vector, so this line
  # only ever drops the first term column. Kept as-is to preserve the original
  # feature set; the real trimming is the colSums(...) > 3 step (k = 3).
  zero_var_cols <- nearZeroVar(corpus_dtm, saveMetrics = TRUE)$nzv
  corpus_dtm <- corpus_dtm[, -zero_var_cols]

  return(corpus_dtm)
}

# ---- Train-test split ---------------------------------------------------------
# Original notebook defines prepare_ml twice. Version 1 goes with approaches 1
# and 2 (single three-way label); version 2 goes with approach 3 (two binary
# labels). REBUILD: given separate names so both can coexist.
prepare_ml_single <- function(dtm, original_data) {
  group_index <- partition(original_data$senti_label, p = c(train = 0.8, test = 0.2))
  test_df <- original_data[group_index$test, ]
  train_data <- dtm[group_index$train, ]
  test_data <- dtm[group_index$test, ]
  train_label <- original_data$senti_label[group_index$train]
  test_label <- original_data$senti_label[group_index$test]
  list("train_data" = train_data, "test_data" = test_data,
       "train_label" = train_label, "test_label" = test_label,
       "test_df" = test_df)
}

prepare_ml_double <- function(dtm, original_data) {
  # Stratifying the data by labels
  group_index <- partition(original_data$pos_label, p = c(train = 0.8, test = 0.2))
  train_data <- dtm[group_index$train, ]
  test_data <- dtm[group_index$test, ]
  train_pos_label <- original_data$pos_label[group_index$train]
  test_pos_label <- original_data$pos_label[group_index$test]
  train_neg_label <- original_data$neg_label[group_index$train]
  test_neg_label <- original_data$neg_label[group_index$test]
  test_df <- original_data[group_index$test, ]
  list("train_data" = train_data, "test_data" = test_data,
       "train_label" = cbind(train_pos_label, train_neg_label),
       "test_label" = cbind(test_pos_label, test_neg_label),
       "test_df" = test_df)
}

add_senti_label <- function(df) {
  df$senti_label <- ifelse(df$pos_label == 'NP' & df$neg_label == 'NN', 'O',
                           ifelse(df$pos_label == 'P', 'P', 'N'))
  df
}

# ---- Hybrid score -------------------------------------------------------------
ensemble_average <- function(df) {
  # scaling lexicon-based senti labels
  df$afinn_sentiment <- as.numeric(scale(df$afinn_sentiment, center = TRUE, scale = TRUE))
  df$bing_sentiment <- as.numeric(scale(df$bing_sentiment, center = TRUE, scale = TRUE))
  # converting svm and rf labels to numeric
  df$svm.label <- ifelse(df$svm.label == "P", 1, ifelse(df$svm.label == "N", -1, 0))
  df$rf.label <- ifelse(df$rf.label == "P", 1, ifelse(df$rf.label == "N", -1, 0))
  # average of SVM, Bing Liu and RF
  df$hybrid <- (df$svm.label + df$bing_sentiment + df$rf.label) / 3
  return(df)
}

# ---- Applying trained models to new text --------------------------------------
# REBUILD: the column-alignment block of the original apply_ml(), pulled out so
# approach 3 (two models per method) can reuse it unchanged.
conform_dtm <- function(df.text, sample_dtm) {
  df.text <- df.text[, colSums(df.text != 0) > 3] # dimensionality reduction
  # Making the test dtm's dimensions conform to the learned dtm
  common_cols <- intersect(colnames(df.text), colnames(sample_dtm))
  df.text <- df.text[, common_cols]
  missing_cols <- setdiff(colnames(sample_dtm), colnames(df.text))
  if (length(missing_cols) > 0) {
    add_matrix <- matrix(0, nrow = nrow(df.text), ncol = length(missing_cols))
    colnames(add_matrix) <- missing_cols
    df.text <- cbind(df.text, add_matrix)
  }
  order <- match(colnames(sample_dtm), colnames(df.text))
  df.text[, order]
}

apply_ml <- function(df, df.text, sample_dtm, svm, randforest) {
  df.text <- conform_dtm(df.text, sample_dtm)
  df$svm.label <- predict(svm, df.text)        # applying SVM
  df$rf.label <- predict(randforest, df.text)  # applying Random Forest
  df <- get_senti(df)                          # using lexicon-based methods
  df <- ensemble_average(df)
  return(df)
}

# Original subset_dtm(): shuffles the corpus, splits it into two halves, and
# vectorizes + scores each half separately (to save memory).
# REBUILD: the original hard-coded the China models inside the function, so
# Congress was scored with China models. The scoring step is now an argument
# (`scorer(chunk, chunk_dtm)`), and the caller passes the matching country's models.
subset_dtm <- function(df, rows_kept, scorer) {
  df <- df[sample(nrow(df), rows_kept), ]
  n <- nrow(df)
  split_indices <- c(0, round(n * 0.5), n)
  subset_df <- lapply(seq_along(split_indices)[-1], function(i) {
    df[(split_indices[i - 1] + 1):split_indices[i], ]
  })
  df_dtm <- lapply(subset_df, vectorizer_tfidf)
  df_senti <- vector(mode = "list", length = 2)
  for (k in 1:2) df_senti[[k]] <- scorer(subset_df[[k]], df_dtm[[k]])
  do.call(rbind, df_senti)
}

# Scores all four corpora the way the original notebook did: Presidential
# Library in one pass; Congress, MFA and People's Daily via subset_dtm().
score_corpora <- function(corpora, us_scorer, china_scorer) {
  part <- function(src) corpora[corpora$source == src, ]
  pres <- part("pres")
  out <- list(
    pres = us_scorer(pres, vectorizer_tfidf(pres)),
    congress = subset_dtm(part("congress"), nrow(part("congress")), us_scorer),
    mofa = subset_dtm(part("mofa"), nrow(part("mofa")), china_scorer),
    peoplesdaily = subset_dtm(part("peoplesdaily"), nrow(part("peoplesdaily")), china_scorer)
  )
  bind_rows(out) %>%
    mutate(svm.label = as.numeric(svm.label), rf.label = as.numeric(rf.label)) %>%
    select(source, doc_id, date, svm.label, rf.label, afinn_sentiment, bing_sentiment, hybrid) %>%
    arrange(source, doc_id)
}

# ---- Evaluation ---------------------------------------------------------------
# Stratifies the continuous hybrid score into N/O/P using the true class shares,
# then builds a three-class confusion matrix (thesis footnote 35).
create_cm <- function(test_df) {
  test_df <- test_df %>% arrange(hybrid)
  n_count <- quantile(test_df$hybrid, probs = nrow(test_df[test_df$senti_label == "N", ]) / nrow(test_df))
  p_count <- quantile(test_df$hybrid, probs = 1 - nrow(test_df[test_df$senti_label == "P", ]) / nrow(test_df))
  hybrid <- cut(test_df$hybrid, breaks = c(-Inf, n_count, p_count, Inf), labels = c("N", "O", "P"))
  confusionMatrix(table(hybrid, factor(test_df$senti_label, levels = c("N", "O", "P"))),
                  positive = "P", mode = "everything")
}

binary_cm <- function(test_df) {
  pn <- test_df[test_df$senti_label %in% c("P", "N"), ]
  confusionMatrix(table(factor(ifelse(pn$hybrid > 0, "P", "N"), levels = c("N", "P")),
                        factor(pn$senti_label, levels = c("N", "P"))), positive = "P")
}

# Collects the Figure 6-8 statistics into one long table.
collect_metrics <- function(approach, country, three_class_df, binary_df) {
  cm3 <- create_cm(three_class_df)
  cm2 <- binary_cm(binary_df)
  f1 <- cm3$byClass[, "F1"]
  auc_for <- function(cls) as.numeric(auc(roc(ifelse(three_class_df$senti_label == cls, 1, 0),
                                               three_class_df$hybrid, quiet = TRUE)))
  tab2 <- as.data.frame(cm2$table)
  bind_rows(
    tibble(metric = "accuracy_3class", class = "all", value = cm3$overall[["Accuracy"]]),
    tibble(metric = "f1_3class", class = sub("Class: ", "", names(f1)), value = unname(f1)),
    tibble(metric = "accuracy_binary", class = "P/N only", value = cm2$overall[["Accuracy"]]),
    tibble(metric = "auc", class = c("P", "N", "O"), value = sapply(c("P", "N", "O"), auc_for)),
    tibble(metric = paste0("binary_cm_pred", tab2[[1]], "_true", tab2[[2]]), class = "count",
           value = tab2$Freq),
    tibble(metric = "n_eval_3class", class = c("N", "O", "P"),
           value = as.numeric(table(factor(three_class_df$senti_label, levels = c("N", "O", "P")))))
  ) %>% mutate(approach = approach, country = country, .before = 1)
}

# ---- Inputs written by 00_prepare_inputs.R -------------------------------------
read_training_sample <- function(which_country) {
  read_csv(out_path("00_training_sample.csv"), show_col_types = FALSE) %>%
    filter(country == which_country) %>%
    select(date, title, text, pos_label, neg_label) %>%
    as.data.frame()
}

read_corpora <- function() {
  read_csv(out_path("00_corpora.csv"), show_col_types = FALSE,
           col_types = cols(subhead = col_character(), title = col_character())) %>%
    as.data.frame()
}

# ---- Scored raw datasets written by 05_export_scored_datasets.R -----------------
# read_scored("mofa") returns one data frame; several sources return a named list
# (their raw columns differ). scored_only = TRUE drops rows that were never scored.
SCORED_FILES <- c(pres = "05_presidential_scored.csv", congress = "05_congress_scored.csv",
                  mofa = "05_mfa_scored.csv", peoplesdaily = "05_peoplesdaily_scored.csv")
read_scored <- function(sources = names(SCORED_FILES), scored_only = TRUE) {
  out <- lapply(sources, function(src) {
    # guess_max = Inf: score columns are empty for most unscored rows, which
    # would otherwise be guessed as logical.
    df <- read_csv(out_path(SCORED_FILES[[src]]), show_col_types = FALSE, guess_max = Inf)
    if (scored_only) df <- filter(df, scored)
    df
  })
  names(out) <- sources
  if (length(out) == 1) out[[1]] else out
}
