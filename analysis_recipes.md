# Analysis recipes

Short notes on how each rebuilt stage was produced. Code lives in this repo; data
and outputs live in `../honors-thesis-original-data/`.

## Sentiment models (`sentiments/`)

**Goal.** Retrain the 2023 SVM + random forest + Bing Liu "hybrid" sentiment
classifier under all three train-test approaches in the thesis (Figure 6), with
the 2023 methodology unchanged, and rescore the four corpora.

**Run order** (from the repo root; each script writes `0X_*` files to
`honors-thesis-original-data/sentiments/`):

| Script | What it does | Exports |
|---|---|---|
| `functions.R` | Paths and the 2023 helper functions (`vectorizer_tfidf`, `ensemble_average`, `apply_ml`, `subset_dtm`, `create_cm`, ...) | none |
| `00_prepare_inputs.R` | Builds the hand-coded training sample and the corpora to score | `00_training_sample.csv`, `00_corpora.csv` |
| `01_approach1_binary.R` | Approach 1: train on P and N only | `01_metrics.csv`, `01_test_predictions.csv`, `01_scores.csv`, `01_models.rds` |
| `02_approach2_three_class.R` | Approach 2: train on P, N and 75 sampled O | `02_*` (same set) |
| `03_approach3_two_binary.R` | Approach 3: two binary models (pos/not, neg/not) per method | `03_*` (same set) |
| `04_compare_to_original.R` | Agreement with 2023 scores; headline Granger rerun (Figs 13–14) | `04_doc_agreement.csv`, `04_series_correlation.csv`, `04_granger_headline.csv` |
| `05_export_scored_datasets.R` | Attaches all scores to the raw datasets | `05_presidential_scored.csv`, `05_congress_scored.csv`, `05_mfa_scored.csv`, `05_peoplesdaily_scored.csv` |

```bash
Rscript sentiments/00_prepare_inputs.R
Rscript sentiments/01_approach1_binary.R
Rscript sentiments/02_approach2_three_class.R
Rscript sentiments/03_approach3_two_binary.R
Rscript sentiments/04_compare_to_original.R
Rscript sentiments/05_export_scored_datasets.R
```

**Inputs.**
- Training sample: the four 2023 hand-coded files, copied from
  `honors-thesis-data/clean/04_sample_data/archive/` into
  `honors-thesis-original-data/raw/coded_samples/`.
- Corpora: the documents scored in 2023, read from
  `sentiments/_archive/*_Senti.xlsx` (old scores dropped). `doc_id` is the row
  number in the archived file, so new and old scores join on `source + doc_id`.
  The relevance filter is not rebuilt; People's Daily uses the 2,484 articles
  that passed it in 2023.

**Changes made to get the code running (methodology unchanged).**
- Hard-coded `~/PycharmProjects/...` paths replaced with paths relative to the repo.
- The MFA sample's labels sit in `pos_label` alone (P / N / NN). They are recoded
  into the P/NP + N/NN scheme of the other samples. Otherwise the 103 ambiguous
  MFA documents count as negative. The thesis's China confusion matrix matches
  the recoded counts.
- Duplicate definitions given separate names: `prepare_ml_single` (approaches 1–2)
  and `prepare_ml_double` (approach 3). Each approach has its own `train_ml` in its own file.
- Approach 2: one added line, `df <- rbind(df_p, df_n, df_o)`.
- Approach 3: `train_ml` now also returns its random forests, and
  `apply_ml_double()` applies the two-model rule to new text. In 2023,
  approach 3 could not score the corpora.
- `subset_dtm()` hard-coded the China models, so Congress was scored with them.
  It now takes the scorer as an argument, and Congress uses the US models.
- Seeds set (`SEED = 2023`); the 2023 code had none, so numbers will not match exactly.

**Kept as-is even though they look unintended** (to be revisited on the methods branch):
- `corpus_dtm[, -zero_var_cols]` negates a logical vector, so it only drops the
  first term column. Real trimming is the k = 3 `colSums` step.
- `randomForest(..., tree = 35)`: `tree` is not an argument, so 500 trees are used.
- Approach 1 three-class evaluation adds all 75 held-out O documents for the US
  but only 25 for China, and re-vectorizes that set separately.
- Bing scores are standardized within each scored chunk (each half of Congress,
  MFA and People's Daily; all of the Presidential Library), so that component is
  centered at zero in each source.

**Results (run 2026-11-10, R 4.6.0; about 5 minutes per approach script).**

Test-set performance of the hybrid score (`0X_metrics.csv`). Test sets are only
about 55–110 documents, so a few points of difference are within split-to-split noise.

| | Thesis Fig 6 (China / US) | Rebuilt (China / US) |
|---|---|---|
| Approach 1, three-class accuracy | 59.0% / 48.5% | 75.9% / 44.6% |
| Approach 2, three-class accuracy | 74.7% / 62.2% | 69.9% / 68.6% |
| Approach 3, three-class accuracy | 62.1% / 56.5% | 68.4% / 57.9% |
| Approach 2, P/N-only accuracy (Figs 7–8 text) | 88% / 84% | 87.9% / 85.5% |
| Approach 2, AUC for positive (Figs 7–8) | 0.912 / 0.840 | 0.886 / 0.888 |

Agreement with the 2023 archived scores (`04_doc_agreement.csv`,
`04_series_correlation.csv`; correlations of `hybrid`):

| | Documents: MFA / People's Daily / Presidential / Congress | Weekly series: China / US |
|---|---|---|
| Approach 1 | 0.95 / 0.89 / 0.75 / 0.84 | 0.96 / 0.79 |
| Approach 2 | 0.94 / 0.87 / 0.73 / 0.79 | 0.94 / 0.77 |
| Approach 3 | 0.88 / 0.77 / 0.73 / 0.72 | 0.88 / 0.73 |

Bing correlates 0.996–1.000 with the archive, so the lexicon side reproduces;
the differences come from the retrained SVM/RF. Presidential Library agrees
least (SVM labels agree 70% under approach 1), and its rebuilt mean is more
negative (−0.33 vs −0.14 under approach 1).

Headline Granger tests (`04_granger_headline.csv`; weekly, lag 3, data after
each 1 January from 2002 to 2020):
- **US as response: holds.** Under every approach, US sentiment is Granger-caused
  by Chinese sentiment (p < 0.05) in 18 of 19 windows for both Fig 13 (MFA vs
  Presidential) and Fig 14 (all data). The exception is the post-2020 window,
  which is also not significant in the thesis.
- **China as response: weaker than printed.** The thesis shows p < 0.05 in 9–10
  of 19 windows. Rebuilt: 0–6, and these are almost all windows starting
  2002–2007 (full-period feedback); none start in 2008–2015. So the
  "unidirectional after ~2008" reading is, if anything, stronger.
- **The thesis's exact p-values do not reproduce** (e.g. Fig 14, China as
  response after 2010: 0.01 printed vs 0.18–0.62 rebuilt, archive 0.62), even
  with the 2023 archived scores. The printed tables probably came from
  console-state objects that were never saved.

**Scored raw datasets (`05_*_scored.csv`).** For downstream scripts, use
`read_scored("mofa")`, or `read_scored()` for all four sources as a named list
(from `functions.R`). Rows that were never scored are dropped unless
`scored_only = FALSE`.

What the files contain:
- Every row and column of the raw file, with Congress1 and Congress2 stacked into one file. The raw files' unnamed pandas index column is renamed `unnamed_index`.
- Added columns:
  - `source`, `raw_file`, `raw_row`.
  - `doc_id`: the join key to `00_corpora.csv` and `0X_scores.csv`.
  - `scored`.
  - `in_ts_sample`: the document is scored and dated; for Congress, also among the 2,000 drawn with `set.seed(123)`.
  - `{afinn,bing,svm,rf,hybrid}_{a1,a2,a3,2023}`.
- The lexicon columns are per approach. Bing and AFINN are standardized within the chunks each approach scored, and `subset_dtm()` shuffles those chunks differently each time. So `hybrid_aK = (svm_aK + bing_aK + rf_aK) / 3` holds within each approach.

How raw rows were matched to scored documents (on content, not row position):
- Presidential: title, date and cleaned text.
- Congress: title, date, text and subhead.
- MFA: link, question and answer.
- People's Daily: title, date and text, after removing Excel's escaped carriage returns (`_x000D_`) and normalizing whitespace. 784 archived texts differ from the raw file only in that respect.
- Exact duplicates are matched in order of appearance.
- All scored documents are found. The script checks that dates agree, and a separate check confirms every score equals `0X_scores.csv`.

Coverage:

| | Raw rows | Scored | Scored but undated | In time series |
|---|---|---|---|---|
| Presidential | 4,896 | 4,760 | 1,686 | 3,074 |
| Congress | 30,297 | 4,800 | 220 | 1,910 |
| MFA | 5,955 | 5,955 | 8 | 5,947 |
| People's Daily | 31,577 | 2,484 | 0 | 2,484 |

- **Undated Presidential documents.** 35% of scored Presidential documents have no date, in the raw file as well as the 2023 file, so they never enter the US series. Their titles often contain a year. Recovering dates is a data fix for the methods branch.
- **Unscored Presidential rows.** The 136 Presidential rows that were never scored have no cleaned text.

## Exhibits (`figures/`)

Each script reads the `0X_*` outputs above and writes to `figures/output/`.
`figures/setup.R` holds the shared paths, ggplot theme (serif, sized for a 6.5in
text width), class colors and the evaluation-set loader.

| Script | Thesis exhibit | Exports |
|---|---|---|
| `06_sentiment_stats.R` | Figure 6 (plus statistics quoted in the Figs 7–8 text) | `06_sentiment_stats.tex`, `06_sentiment_stats_preview.pdf` |
| `07_08_confusion_roc.R` | Figures 7 (China) and 8 (US) | `07_china_roc.pdf`, `07_china_confusion.pdf`, `08_us_roc.pdf`, `08_us_confusion.pdf` |

```bash
Rscript figures/06_sentiment_stats.R
Rscript figures/07_08_confusion_roc.R
```

- **Table (Fig 6).** A booktabs/threeparttable fragment for `\input{}`.
  - Panel A has the Figure 6 statistics: three-class F1 by class and accuracy.
  - Panel B adds one-vs-rest AUC by class and accuracy on positive/negative documents only, which the thesis quotes in the text.
  - The preview PDF is compiled in a temp directory, so no LaTeX auxiliary files land in the repo.
- **Figs 7–8.** For each country, one ROC figure and one confusion-matrix figure, with a panel per approach.
  - The thesis showed only approach 2, with a 2×2 positive/negative matrix. These show 3×3 matrices from `create_cm()` (quantile cut of the hybrid score). Cells give counts and the share of each true class.
  - The ROC curves use pROC defaults on the hybrid score, as the 2023 notebook did. pROC picks each class's direction automatically, which matters most for the ambiguous class.
- **Consistency check.** `07_08_confusion_roc.R` stops if its accuracies or AUCs drift from `0X_metrics.csv`.
  - Accuracies match exactly.
  - AUCs can differ by up to 0.002, because the loader rounds hybrid scores to 10 decimals. A few documents have identical SVM, RF and Bing scores but hybrid scores that differ by about 1e-17, and the rounding makes them ties.
  - The values agree at the two decimals that are printed.
