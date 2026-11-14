# CLAUDE.md

## Project goal

Measure how the US and China talk about each other, and test who reacts to whom.

1. Collect Chinese government and state-media rhetoric about the US, and US government
   and newspaper rhetoric about China.
2. Score each document's sentiment toward the other country.
3. Aggregate the scores into time series of US posture toward China and China's posture
   toward the US.
4. Use time series methods to test whether US posture lags Chinese posture, or the reverse.

This is a rebuild of an undergraduate honors thesis (`write-up/Lin_Alexander_IPOL_Honors_Thesis.pdf`).
The aim is a presentable writing sample in about 1.5 weeks (target: mid-November 2026). In this branch, our main goal is to replicate old exhibits and make them look presentable. Robustness checks and methodological fixes are carried out on the other branch. 

The goal should be to produce a viable writing sample for a poli sci phd program, not a working paper.

## Data organization

The data corresponding to this branch are located outside of this directory, under `Personal Projects/honors-thesis-original-data`. 

The `raw` folder contains raw documents. The `sentiments` folder contains documents with multiple types of sentiment scores, along with miscellaneous files created during analyses. 

### Figure replication

When replication figures, feel free to take creative liberties with formatting, but adhere to the data cleaning and processing steps as laid out in existing code or in the paper as closely as possible. If possible, export tables as tex files and charts as pdfs. This allows all figures to be easily and directly inserted into a new paper draft. 

The `figures` folder should contain all scripts generating figures for the replicated paper. There should ideally be one script per class of figures. Files are to be numbered corresponding to the two digit figure number. For example, the replication of figure 6 should be saved to 06_sentiment_stats.tex. 