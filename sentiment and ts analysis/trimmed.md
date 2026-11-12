
Applying the function to sample data: 
```{r}
sample_tfidf <- vectorizer_tfidf(the_sample)
```


## Dimensionality Reduction

Very crude dimensionality reduction by dropping very infrequent words:
```{r}
sample_tfidf <- sample_tfidf[,colSums(sample_tfidf != 0) > 3]
```

Dimensionality reduction with PCA:
```{r}
the.pca <- prcomp(sample_tfidf, scale = T)
sample_tfidf <- the.pca$x[,1:200]
```


Applying the function to US data:
```{r}

ml <- ml_ready(sample_tfidf, the_sample)

train_data <- ml$train_data
test_data <- ml$test_data
train_label <- ml$train_label
test_label <- ml$test_label
group <- ml$group_index

```


## Naive Bayes

```{r}

the.nb <- naive_bayes(x=train_data, y = as.factor(train_label))
the.predict <- predict(the.nb, test_data)

the_sample_test <- the_sample[group$test,] 
the_sample_test$nb.label <- the.predict

```

Creating a confusion matrix for NB:
```{r}
table(the_sample_test$nb.label, test_label)
```

## SVM

```{r}

the.svm <- svm(x=train_data, y=as.factor(train_label), kernel = "linear", type = "C-classification")
the.predict <- predict(the.svm, test_data)

# the_sample_test <- the_sample[group$test,] 
the_sample_test$svm.label <- the.predict

```

Creating a confusion matrix for SVM:
```{r}
table(the_sample_test$svm.label, test_label)
```
## Random Forest

```{r}

the.randomforest <- randomForest(x=train_data, y=as.factor(train_label),
                                mtry=50, tree=35)
the.predict <- predict(the.randomforest, test_data)

the_sample_test$rf.label <- the.predict
```

Creating a confusion matrix for Random Forest:
```{r}
table(the_sample_test$rf.label, test_label)
```

```{r}

the.dt <- rpart(formula = as.factor(train_label) ~., data = as.data.frame(train_data))
the.predict <- predict(the.dt, as.data.frame(test_data))

the_sample_test$dt.label <- ifelse(the.predict[,1] < the.predict[,2], 1,-1)
```

Creating a confusion matrix for DT:
```{r}
table(the_sample_test$dt.label, test_label)
```
Comparing ML methods with lexicon methods: 
```{r}
the_sample_test <- get_senti(the_sample_test)
```

```{r}

the_sample_test$afinn_sentiment <- ifelse(scale(the_sample_test$afinn_sentiment) >= 0, 1,-1)
the_sample_test$bing_sentiment <- ifelse(scale(the_sample_test$bing_sentiment) >= 0, 1,-1)

table(the_sample_test$afinn_sentiment, test_label)
table(the_sample_test$bing_sentiment, test_label)

```

## Ensemble Averaging/Hybrid Methods


Applying the function: 
```{r}

ch_bytopic <- topic_filter(china_data, domestic_periphery_keywords, "month")
# us_bytopic <- topic_filter(us_data, trade_keywords, "month")

```

Plotting the time series filtered by topic: 
```{r}

ggplot() + geom_ma(data = china_month, aes(x = month, y = mean_sentiment), color = "red", alpha = 0.8) + 
  geom_ma(data = us_month, aes(x = month, y = mean_sentiment), color = "blue", alpha = 0.8) + 
  xlim(as.Date(c("2003-01-01","2022-01-01")))

```

ggplot(ch_topic) + geom_ma(aes(x = month, y = rel_count), color = "lightblue", ma_fun = SMA, n = 3, linetype = "solid") + 
  geom_ma(aes(x = month, y = mean_sentiment/2+0.25), color = "orange", ma_fun = SMA, n = 3, linetype = "dotted") + 
  geom_ma(aes(x = month, y = topic_mean_sentiment/2+0.25), color = "darkorange", ma_fun = SMA, n = 3, linetype = "dotted") +
  xlim(as.Date(c("2017-01-01","2022-01-01"))) + theme_minimal()
  
  
  Because the MoFA data is not stationary, we will use first-order differencing to stabilize the mean: 
```{r}
mofa_month_diff <- diff(mofa_month$mean_sentiment)
us_month_diff <- diff(us_month$mean_sentiment)
```

Creating new master dataset with stationary data from both US and China: 
```{r}

mofa_month_2 <- mofa_month[-1,]
mofa_month_2$senti_diff <- mofa_month_diff

us_month_2 <- us_month[-1,]
us_month_2$senti_diff <- us_month_diff

time_series <- full_join(mofa_month_2, us_month_2, by = "month")
colnames(time_series) <- c("date","senti_china","ndoc_china","sentidiff_china",
                            "senti_us","ndoc_us","sentidiff_us")

```
Between first order differences of MOFA and Presidential datasets grouped by month:
```{r}

gct <- grangertest(sentidiff_us ~ sentidiff_china, order = 1, 
                   data = time_series)
gct

```
topic_counts_us <- gather(rel_counts_us, key = "topic", value = "relative_counts",
                        trade_count, domestic_periphery_count, tw_count, multi_count, scs_count, 
                        intl_actors_count, russia_count, counterterrorism_count, 
                        cooperation_count, competition_count,
                        others_count, -month) 

topic_senti_us <- gather(rel_counts_us, key = "topic", value = "sentiment",
                         trade_sentiments, domestic_periphery_sentiments, tw_sentiments, 
                         multi_sentiments, scs_sentiments, mean_sentiment, -month) %>% select(c(1, 9:10))
                         
                         
                         train_ml <- function(df_complete) {
  
  df <- subset(df_complete, pos_label == 'P' | neg_label == 'N')
  df.dtm <- vectorizer_tfidf(df) #creating the document-term matrix
  df.dtm <- df.dtm[,colSums(df.dtm != 0) > 3] #dimensionality reduction
  
  ml <- prepare_ml(df.dtm, df)

  train_data <- ml$train_data
  test_data <- ml$test_data
  
  train_pos_label <- ml$train_pos_label
  test_pos_label <- ml$test_pos_label
  
  train_neg_label <- ml$train_neg_label
  test_neg_label <- ml$test_neg_label
  
  #Support Vector Machine
  pos.svm <- svm(x=train_data, y=as.factor(train_pos_label), 
                   kernel = "linear", type = "C-classification")
  pos.predict <- predict(pos.svm, test_data)
  pos.predict <- ifelse(pos.predict == "P", 1, 0)
  
  neg.svm <- svm(x=train_data, y=as.factor(train_neg_label),
                 kernel = "linear", type = "C-classification")
  neg.predict <- predict(neg.svm, test_data)
  neg.predict <- ifelse(neg.predict == "N", -1, 0)
  
  df.test <- ml$test_df
  df.test$pos.predict <- pos.predict
  df.test$neg.predict <- neg.predict
  df.test$svm.label <- pos.predict + neg.predict
  
  #Random Forest
  # senti.randomforest <- randomForest(x=train_data, y=as.factor(train_label),
                                   # mtry=50, tree=35)
  # senti.predict <- predict(senti.randomforest, test_data)
  # df.test$rf.label <- senti.predict
  
  #Naive Bayes
  # senti.nb <- naive_bayes(x=train_data, y = as.factor(train_label))
  # senti.predict <- predict(senti.nb, test_data)
  # df.test$nb.label <- senti.predict
  
  #DT
  # senti.dt <- rpart(formula = as.factor(train_label) ~., data = as.data.frame(train_data))
  # senti.predict <- predict(senti.dt, as.data.frame(test_data))
  # df.test$dt.label <- ifelse(senti.predict[,1] < senti.predict[,2], 1,-1)
  
  #Lexicon & Hybrid
  # df.test <- get_senti(df.test) %>% ensemble_average()
  
  return(list("dtm" = df.dtm, "df.test" = df.test,
              "pos.svm" = pos.svm, "neg.svm" = neg.svm))
              # "svm" = senti.svm, "randforest" = senti.randomforest))
  
}