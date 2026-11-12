# 02 — Approach 2: SVM and RF trained on positive, negative and a 75-document
# sample of ambiguous texts (three classes). The thesis reports this approach as
# the best performer (Figure 6) and its diagnostics in Figures 7-8.
#
# Identical to 01_approach1_binary.R except for one line in train_ml():
#   df <- rbind(df_p, df_n)        (approach 1)
#   df <- rbind(df_p, df_n, df_o)  (approach 2)
# This line was not in the 2023 notebook; it is reconstructed from the leftover
# 75-document subsample of "O" documents that approach 1 never uses.
#
# Exports (to honors-thesis-original-data/sentiments/):
#   02_metrics.csv, 02_test_predictions.csv, 02_scores.csv, 02_models.rds

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "functions.R")
set.seed(SEED)

train_ml <- function(df) {
  df <- add_senti_label(df)

  df_p <- df[df$senti_label == "P", ]
  df_n <- df[df$senti_label == "N", ]
  df_o <- df[df$senti_label == "O", ]
  df_o <- df_o[sample(nrow(df_o), 75), ]
  df <- rbind(df_p, df_n, df_o) # REBUILD: the one-line change for approach 2

  df.dtm <- vectorizer_tfidf(df) # creating the document-term matrix
  df.dtm <- df.dtm[, colSums(df.dtm != 0) > 3] # trimming columns that are nearly empty (k = 3)

  ml <- prepare_ml_single(df.dtm, df)
  train_data <- ml$train_data
  test_data <- ml$test_data
  train_label <- ml$train_label

  # Support Vector Machine
  senti.svm <- svm(x = train_data, y = as.factor(train_label),
                   kernel = "linear", type = "C-classification")
  df.test <- ml$test_df
  df.test$svm.label <- predict(senti.svm, test_data)

  # Random Forest (`tree = 35` is ignored by randomForest(); 500 trees, as in 2023)
  senti.randomforest <- randomForest(x = train_data, y = as.factor(train_label),
                                     mtry = 50, tree = 35)
  df.test$rf.label <- predict(senti.randomforest, test_data)

  # Lexicon & Hybrid
  df.test <- get_senti(df.test) %>% ensemble_average()

  list("dtm" = df.dtm, "df.test" = df.test, "svm" = senti.svm,
       "randforest" = senti.randomforest, "df_o" = df_o)
}

# ---- Train ----------------------------------------------------------------------
train_us <- train_ml(read_training_sample("US"))
train_china <- train_ml(read_training_sample("China"))

# ---- Evaluate ---------------------------------------------------------------------
# The test split already contains all three classes: three-class metrics and
# ROC on the full test split, binary metrics on its P/N documents (as in the
# notebook's "Model evaluation for China training data trinary categories").
us_test <- train_us$df.test
china_test <- train_china$df.test

metrics <- bind_rows(
  collect_metrics("02", "US", three_class_df = us_test, binary_df = us_test),
  collect_metrics("02", "China", three_class_df = china_test, binary_df = china_test)
)
write_csv(metrics, out_path("02_metrics.csv"))
print(as.data.frame(metrics), digits = 3)

pred_cols <- c("date", "title", "text", "pos_label", "neg_label", "senti_label",
               "svm.label", "rf.label", "afinn_sentiment", "bing_sentiment", "hybrid")
write_csv(bind_rows(
  us_test[, pred_cols] %>% mutate(country = "US", eval_set = "test split"),
  china_test[, pred_cols] %>% mutate(country = "China", eval_set = "test split")
), out_path("02_test_predictions.csv"))

# ---- Score the corpora --------------------------------------------------------------
us_scorer <- function(df, dtm) apply_ml(df, dtm, train_us$dtm, train_us$svm, train_us$randforest)
china_scorer <- function(df, dtm) apply_ml(df, dtm, train_china$dtm, train_china$svm, train_china$randforest)

scores <- score_corpora(read_corpora(), us_scorer, china_scorer)
write_csv(scores, out_path("02_scores.csv"))

saveRDS(list(us = list(vocab = colnames(train_us$dtm), svm = train_us$svm, rf = train_us$randforest),
             china = list(vocab = colnames(train_china$dtm), svm = train_china$svm, rf = train_china$randforest)),
        out_path("02_models.rds"))
cat("Done: approach 2\n")
