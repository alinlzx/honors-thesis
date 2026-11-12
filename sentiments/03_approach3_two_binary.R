# 03 — Approach 3: the three-way label is recoded into two binary labels
# (positive vs not, negative vs not) and each method is trained twice. A document
# is P if the positive model says P and the negative model says NN, N if the
# reverse, and O otherwise.
#
# This is the first train_ml() in "senti analysis ML.Rmd" (paired with the
# second prepare_ml(), here prepare_ml_double()). Unlike approaches 1-2, it
# trains on every coded document (no 75-document "O" subsample).
#
# REBUILD changes needed to run it end to end:
#   - train_ml() now also returns the two random forests (the 2023 version
#     returned only the SVMs, so the corpora could not be scored with it).
#   - apply_ml_double() below is apply_ml() with the two-model combination rule
#     from train_ml(); the 2023 apply_ml() only handled one model per method.
#
# Exports (to honors-thesis-original-data/sentiments/):
#   03_metrics.csv, 03_test_predictions.csv, 03_scores.csv, 03_models.rds

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "functions.R")
set.seed(SEED)

combine_labels <- function(pos, neg) {
  ifelse(pos == "P" & neg == "NN", "P", ifelse(pos == "NP" & neg == "N", "N", "O"))
}

train_ml <- function(df) {
  df <- add_senti_label(df)

  df.dtm <- vectorizer_tfidf(df) # creating the document-term matrix
  df.dtm <- df.dtm[, colSums(df.dtm != 0) > 3] # trimming columns that are nearly empty (k = 3)

  ml <- prepare_ml_double(df.dtm, df)
  train_data <- ml$train_data
  test_data <- ml$test_data
  train_label <- ml$train_label

  # Support Vector Machine
  pos.svm <- svm(x = train_data, y = as.factor(train_label[, 1]),
                 kernel = "linear", type = "C-classification")
  neg.svm <- svm(x = train_data, y = as.factor(train_label[, 2]),
                 kernel = "linear", type = "C-classification")
  df.test <- ml$test_df
  df.test$svm.label <- combine_labels(predict(pos.svm, test_data), predict(neg.svm, test_data))

  # Random Forest (`tree = 35` is ignored by randomForest(); 500 trees, as in 2023)
  pos.randomforest <- randomForest(x = train_data, y = as.factor(train_label[, 1]),
                                   mtry = 50, tree = 35)
  neg.randomforest <- randomForest(x = train_data, y = as.factor(train_label[, 2]),
                                   mtry = 50, tree = 35)
  df.test$rf.label <- combine_labels(predict(pos.randomforest, test_data),
                                     predict(neg.randomforest, test_data))

  # Lexicon & Hybrid
  df.test <- get_senti(df.test) %>% ensemble_average()

  list("dtm" = df.dtm, "df.test" = df.test,
       "pos.svm" = pos.svm, "neg.svm" = neg.svm,
       "pos.rf" = pos.randomforest, "neg.rf" = neg.randomforest)
}

apply_ml_double <- function(df, df.text, sample_dtm, m) {
  df.text <- conform_dtm(df.text, sample_dtm)
  df$svm.label <- combine_labels(predict(m$pos.svm, df.text), predict(m$neg.svm, df.text))
  df$rf.label <- combine_labels(predict(m$pos.rf, df.text), predict(m$neg.rf, df.text))
  df <- get_senti(df)
  ensemble_average(df)
}

# ---- Train ----------------------------------------------------------------------
train_us <- train_ml(read_training_sample("US"))
train_china <- train_ml(read_training_sample("China"))

# ---- Evaluate ---------------------------------------------------------------------
us_test <- train_us$df.test
china_test <- train_china$df.test

metrics <- bind_rows(
  collect_metrics("03", "US", three_class_df = us_test, binary_df = us_test),
  collect_metrics("03", "China", three_class_df = china_test, binary_df = china_test)
)
write_csv(metrics, out_path("03_metrics.csv"))
print(as.data.frame(metrics), digits = 3)

pred_cols <- c("date", "title", "text", "pos_label", "neg_label", "senti_label",
               "svm.label", "rf.label", "afinn_sentiment", "bing_sentiment", "hybrid")
write_csv(bind_rows(
  us_test[, pred_cols] %>% mutate(country = "US", eval_set = "test split"),
  china_test[, pred_cols] %>% mutate(country = "China", eval_set = "test split")
), out_path("03_test_predictions.csv"))

# ---- Score the corpora --------------------------------------------------------------
us_scorer <- function(df, dtm) apply_ml_double(df, dtm, train_us$dtm, train_us)
china_scorer <- function(df, dtm) apply_ml_double(df, dtm, train_china$dtm, train_china)

scores <- score_corpora(read_corpora(), us_scorer, china_scorer)
write_csv(scores, out_path("03_scores.csv"))

saveRDS(list(us = c(list(vocab = colnames(train_us$dtm)), train_us[c("pos.svm", "neg.svm", "pos.rf", "neg.rf")]),
             china = c(list(vocab = colnames(train_china$dtm)), train_china[c("pos.svm", "neg.svm", "pos.rf", "neg.rf")])),
        out_path("03_models.rds"))
cat("Done: approach 3\n")
