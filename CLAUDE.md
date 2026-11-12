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