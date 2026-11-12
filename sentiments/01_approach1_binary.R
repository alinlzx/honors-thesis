# 01 — Approach 1: SVM and RF trained on positive and negative documents only.
#
# This is the second train_ml() in "senti analysis ML.Rmd" as it was left in
# 2023. The archived 2023 scores (svm.label / rf.label only ever -1 or +1) came
# from this approach.
#
# Exports (to honors-thesis-original-data/sentiments/):
#   01_metrics.csv            Figure 6-8 statistics (accuracy, F1, AUC, binary confusion matrix)
#   01_test_predictions.csv   evaluation documents with model outputs
#   01_scores.csv             scores for every document in 00_corpora.csv (join on source + doc_id)
#   01_models.rds             fitted models and training vocabulary

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "functions.R")
set.seed(SEED)

train_ml <- function(df) {
  df <- add_senti_label(df)

  df_p <- df[df$senti_label == "P", ]
  df_n <- df[df$senti_label == "N", ]
  df_o <- df[df$senti_label == "O", ]
  df_o <- df_o[sample(nrow(df_o), 75), ] # held out; used only to evaluate the "O" class
  df <- rbind(df_p, df_n)

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

  # Random Forest. NOTE: `tree` is not a randomForest() argument (it is `ntree`),
  # so this runs the default 500 trees, as in 2023. Kept as-is.
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
# The approach 1 test split has no ambiguous documents. As in the notebook
# ("Using the simple 80-20 split model to predict the 'O' class"), held-out
# ambiguous documents are added, the combined set is re-vectorized and scored
# with apply_ml(), and the three-class metrics come from that set.
# The notebook adds all 75 held-out "O" docs for the US but 25 for China
# (sample(70, 25)); kept as-is.
eval_cols <- c("date", "title", "text", "pos_label", "neg_label", "senti_label")

us_test <- train_us$df.test
us_test_expanded <- rbind(us_test[, eval_cols], train_us$df_o[, eval_cols])
us_test_expanded <- apply_ml(us_test_expanded, vectorizer_tfidf(us_test_expanded),
                             train_us$dtm, train_us$svm, train_us$randforest)

china_test <- train_china$df.test
china_sample_test <- china_test[china_test$senti_label == "P" | china_test$senti_label == "N", ]
china_test_expanded <- rbind(china_sample_test[, eval_cols], train_china$df_o[sample(70, 25), eval_cols])
china_test_expanded <- apply_ml(china_test_expanded, vectorizer_tfidf(china_test_expanded),
                                train_china$dtm, train_china$svm, train_china$randforest)

metrics <- bind_rows(
  collect_metrics("01", "US", three_class_df = us_test_expanded, binary_df = us_test),
  collect_metrics("01", "China", three_class_df = china_test_expanded, binary_df = china_sample_test)
)
write_csv(metrics, out_path("01_metrics.csv"))
print(as.data.frame(metrics), digits = 3)

pred_cols <- c(eval_cols, "svm.label", "rf.label", "afinn_sentiment", "bing_sentiment", "hybrid")
write_csv(bind_rows(
  us_test[, pred_cols] %>% mutate(country = "US", eval_set = "test split (P/N)"),
  us_test_expanded[, pred_cols] %>% mutate(country = "US", eval_set = "test split + held-out O, re-vectorized"),
  china_test[, pred_cols] %>% mutate(country = "China", eval_set = "test split (P/N)"),
  china_test_expanded[, pred_cols] %>% mutate(country = "China", eval_set = "test split + held-out O, re-vectorized")
), out_path("01_test_predictions.csv"))

# ---- Score the corpora --------------------------------------------------------------
us_scorer <- function(df, dtm) apply_ml(df, dtm, train_us$dtm, train_us$svm, train_us$randforest)
china_scorer <- function(df, dtm) apply_ml(df, dtm, train_china$dtm, train_china$svm, train_china$randforest)

scores <- score_corpora(read_corpora(), us_scorer, china_scorer)
write_csv(scores, out_path("01_scores.csv"))

saveRDS(list(us = list(vocab = colnames(train_us$dtm), svm = train_us$svm, rf = train_us$randforest),
             china = list(vocab = colnames(train_china$dtm), svm = train_china$svm, rf = train_china$randforest)),
        out_path("01_models.rds"))
cat("Done: approach 1\n")
