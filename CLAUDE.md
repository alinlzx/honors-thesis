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
The aim is a presentable writing sample in about one month (target: mid-November 2026).
Replicating the original pipeline is the easy part. The real work is **defending the
methodology**: adding robustness checks and fixing choices that were clearly misguided.
When a methodological choice is questionable, say so and propose an alternative instead of
quietly reproducing it.

## Data

Raw data lives **outside this repo** in the sibling folder `../honors-thesis-data/`.
Never copy raw data into this repo or commit it.

| File | Side | Source |
|---|---|---|
| `MFA_US.xlsx` | China | Chinese Ministry of Foreign Affairs press conference transcripts (Mochtak & Turcsanyi), filtered to US mentions |
| `PeoplesDailyUSA.xlsx` | China | People's Daily articles (Fisher et al.), filtered to US mentions |
| `Presidential_Library.xlsx` | US | Presidential documents mentioning China (original scrape) |
| `Congress1.xlsx`, `Congress2.xlsx` | US | Congressional documents mentioning China (original scrape) |
| `sample data/*_sample.xlsx` | both | Hand-labeled samples used to train and validate the sentiment classifiers |

Files live under `raw/` and `build/` in the data folder. `raw/CMFA_PressCon_v6.xlsx` is the
full MFA press-conference corpus (Mochtak & Turcsanyi v6, 2002–2025); rebuild the US filter
from it rather than reusing `MFA_US.xlsx` (which ends 2021).

Actual coverage of the old files: People's Daily 2007-07 → 2020-12, MFA_US to 2021-12, US
files 2000 → 2023-01. So the original four-source overlap was really 2007–2020.

### Data decisions (Oct 2026)

- The HeinOnline US files (`Presidential_Library`, `Congress1/2`) are **search-hit snippets**
  ("Turn to page …" plus one sentence), not documents. They also contain ToC/index entries,
  CRS reports, US Code, ~37% missing dates (Presidential) and heavy duplication. They are being
  replaced: presidential documents from the GovInfo CPD collection (`scrape/01_scrape_govinfo_presdocs.py`),
  Congress from the GovInfo Congressional Record collection.
- Main pairing is **President ↔ MFA** (executive to executive), extended to 2025 to use MFA v6.
  Congress is a secondary US series. People's Daily (to 2020) is a secondary China series.
  The State Department briefings were considered and dropped (sparse, scattered archives, video-only
  before Nov 2003). The difference in genre between the MFA's Q&A and presidential speeches goes in the
  qualitative section, checked by restricting to presidential news conferences or exchanges with reporters.
- Presidential volume is about 70–200 China-mentioning documents a year, so **monthly** is the
  primary frequency (weekly is too sparse).

## Original approach (for reference, not to be copied blindly)

The original code was R (tidytext, syuzhet, caret, vars) plus Python/Selenium notebooks for
scraping. It was removed on this branch and is still in `main`'s git history.

- Relevance filter on hand-labeled samples.
- Sentiment: Bing Liu and AFINN lexicons, plus SVM and random forest classifiers trained on
  the labeled samples. The final "hybrid" score was the mean of the z-scored Bing score and
  the SVM and RF labels.
- Aggregated to weekly and monthly mean sentiment per side, ADF tests, first-differenced,
  lag order chosen by `VARselect`, then pairwise `grangertest` in both directions.
- Headline finding: unidirectional Granger causality from China to the US. China seems to
  start rhetorical shifts and the US reacts, and the effect is stronger for negative
  sentiment.

## Known weak points to revisit

- Lexicons built for general English (Bing, AFINN) applied to diplomatic and translated text.
- The "hybrid" score averages quantities on different scales (z-scores and class labels).
- Small labeled samples, so classifier validity and generalization across sources are uncertain.
- Pooling heterogeneous sources (MoFA vs People's Daily, President vs Congress) into one
  series per country, plus uneven document counts per period.
- Granger causality on mean sentiment can be confounded by shared exogenous events (both
  sides reacting to the same news). Consider event controls, VAR/IRFs, and sensitivity to
  aggregation window, lag order, and differencing.

## Working conventions

- Code folders map to data folders: `scrape/` → `raw/`, and `clean/`, `build/`, `analysis/` →
  the data folders of the same name. Refer to the data directory with a single configurable
  path (`HONORS_DATA_DIR`, defaulting to `../honors-thesis-data`; see `scrape/config.py`).
  Don't hard-code absolute paths.

- Always number the code files and outputs in consecutive order, starting from "01." If the same cleaning task or analysis exercise requires multiple files, use alphabetical letters to index them (e.g., "01a," "01b," etc.)

- Keep the pipeline reproducible end to end: raw data → scored documents → series → models.
  Write intermediate outputs to the data folder or a git-ignored `outputs/`, not to tracked files.
- Every methodological change should come with a short note on why it's better and a
  robustness check showing whether the headline result survives.
- Log every cleaning and methodological decision in `analysis_recipes.md` (what, why, and
  the check), bolding the consequential ones. Update it in the same change as the code.
- Stack: **Python** for scraping and ML (venv in `.venv/`, pinned deps in
  `requirements.txt`, secrets such as `GOVINFO_API_KEY` in git-ignored `.env`);
  **R** for data cleaning, processing, time series, and visualization.
