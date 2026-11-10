# Analysis recipes

How each dataset gets from raw to analysis-ready, and every decision made along the way,
with the reason for it. **Bold** marks decisions that could change results or that a reader
of the paper would want defended. Update this file whenever a step changes. Each entry
says what was done and why, and, where there is one, what the check showed.

Run everything from the repo root. Data paths come from `HONORS_DATA_DIR` (default
`../honors-thesis-data`); see `config.R` and `scrape/config.py`.

## Pipeline at a glance

| Step | Script | In | Out (in the data folder) |
|---|---|---|---|
| Scrape presidential docs | `scrape/01_scrape_govinfo_presdocs.py` | GovInfo API (cached in `raw/govinfo_cpd/`) | `raw/01_govinfo_presdocs.csv` |
| Clean presidential docs | `clean/01a_clean_presdocs.R` | `raw/01_govinfo_presdocs.csv` | `clean/01a_presdocs_paragraphs.csv`, `clean/01a_presdocs_docs.csv` |
| Check speaker attribution | `clean/01b_check_presdocs_speakers.R` | DCPD HTML cache, 01a outputs | `clean/01b_presdocs_speaker_check.csv` |
| Clean MFA press conferences | `clean/02_clean_mfa.R` | `raw/03_CMFA_PressCon_v6.xlsx` | `clean/02_mfa_qa.csv` |
| Scrape White House briefings | `scrape/02_scrape_app_briefings.py` | American Presidency Project (cached in `raw/app_briefings/`) | `raw/02_app_briefings.csv` |
| Clean White House briefings | `clean/03_clean_briefings.R` | `raw/02_app_briefings.csv` | `clean/03_briefings_paragraphs.csv`, `clean/03_briefings_pairs.csv` |
| Draw hand-coding samples | `clean/04_sample_data.R` | 01a, 02, 03 outputs; `clean/04_sample_data/mofa_sample.xlsx` | `clean/04_sample_data/04_sample_{presdocs,mfa,briefings}.xlsx`, `04_sample_key.csv` |
| Build frame and labels | `build/01_build_units.R` | 01a, 02, 03 outputs; `clean/04_sample_data/04_sample_*_reviewed.xlsx` | `build/01_units.csv`, `build/01_labels.csv` |
| Relevance model (for B and D) | `build/02_relevance_transformer.py` | build 01 outputs | `build/02_relevance_oof.csv`, `build/02_relevance_scores.csv` |
| Spec A: lexicons | `build/03_spec_a_lexicon.R` | build 01 outputs | `build/03_spec_a_labeled.csv`, `build/03_spec_a_scores.csv` |
| Spec B: TF-IDF | `build/04_spec_b_tfidf.py` | build 01 outputs | `build/04_spec_b_oof.csv`, `build/04_spec_b_scores.csv` |
| Spec D: transformer | `build/05_spec_d_transformer.py` | build 01 outputs | `build/05_spec_d_oof.csv`, `build/05_spec_d_scores.csv` |
| Speaker-adjusted scores | `build/06_adjust_composition.R` | build 01, 02, 05 outputs; `clean/02_mfa_qa.csv` | `build/06_adjusted_scores.csv`, `build/06_speaker_effects.csv` |
| Compare the specs | `analysis/01_evaluate_specs.R` | build 01–05 outputs | `analysis/01_*.csv`, `analysis/01{a,b,c}_*.png` |
| Measurement quality by period | `analysis/02_measurement_by_period.R` | build 01, 02, 04, 05 outputs | `analysis/02_*_by_period.csv`, `analysis/02_table_measurement.tex` |
| Composition check | `analysis/03_composition_check.R` | build 01, 02, 05, 06 outputs | `analysis/03_reliability_adjusted.csv`, `analysis/03_adjustment_effect.csv` |
| Time series figures | `analysis/04_plot_time_series.R` | build 01, 02, 05, 06 outputs | `analysis/04_monthly_series.csv`, `analysis/04{a,b}_*.png` |
| Forward-dated Granger tests, monthly | `analysis/05a_forward_dated_granger.R` | build 01, 02, 05, 06 outputs | `analysis/05a_granger_forward.csv`, `analysis/05a_stationarity.csv`, `analysis/05a_table_granger_forward.tex` |
| Forward-dated Granger tests, weekly | `analysis/05b_forward_dated_granger_weekly.R` | build 01, 02, 05, 06 outputs | `analysis/05b_granger_weekly.csv`, `analysis/05b_weekly_coverage.csv`, `analysis/05b_table_granger_weekly.tex` |

`analysis/series_common.R` (unnumbered, like `build/sentiment_common.py`) holds what the series
analyses share: the periods, the relevance cut, the kept passages and the split-half reliability.

```bash
.venv/bin/python scrape/01_scrape_govinfo_presdocs.py
```
```bash
Rscript clean/01a_clean_presdocs.R
```
```bash
Rscript clean/01b_check_presdocs_speakers.R
```
```bash
Rscript clean/02_clean_mfa.R
```
```bash
Rscript clean/03_clean_briefings.R
```
```bash
Rscript clean/04_sample_data.R
```
```bash
Rscript build/01_build_units.R
```
```bash
.venv/bin/python build/02_relevance_transformer.py
```
```bash
Rscript build/03_spec_a_lexicon.R
```
```bash
.venv/bin/python build/04_spec_b_tfidf.py
```
```bash
.venv/bin/python build/05_spec_d_transformer.py
```
```bash
Rscript build/06_adjust_composition.R
```
```bash
Rscript analysis/01_evaluate_specs.R
```
```bash
Rscript analysis/02_measurement_by_period.R
```
```bash
Rscript analysis/03_composition_check.R
```
```bash
Rscript analysis/04_plot_time_series.R
```
```bash
Rscript analysis/05a_forward_dated_granger.R
```
```bash
Rscript analysis/05b_forward_dated_granger_weekly.R
```

The China term lists (`CHINA_CORE`, `CHINA_PERIPH`) live in `config.R`, so every US-side
script flags China the same way. They were moved there from 01a on Oct 23, 2026, and 01a's
counts were unchanged by the move.

The scraper reads from its cache, so a re-run after the first full scrape makes no API calls.

---

## 1. Presidential documents (US side, main series)

Source: GovInfo Compilation of Presidential Documents. WCPD (weekly, 2002 – Jan 2009) is
fixed-width plain text; DCPD (daily, 2009 on) is HTML converted from PDF. The search casts a
wide net (China, Chinese, Beijing, PRC, Taiwan, Hong Kong, Tibet, Xinjiang); relevance is
decided downstream.

### 1.1 Scrape-stage fixes (Oct 21, 2026)

- **Rebuilt DCPD paragraph breaks.** The first version of `extract_text` stripped tags in a
  way that ran each DCPD document into a single line, because the line breaks sat inside
  the `<P>` tags. Speaker turns start at paragraph breaks, so without this fix the president
  could not be separated from other speakers. DCPD text is now one paragraph per `<P>`,
  separated by blank lines. WCPD `<pre>` text is unchanged.
- Repaired mojibake. Some cached pages had been decoded as Latin-1 when they were UTF-8, so
  dashes and quotes came out as `â\x80\x94`. Text is re-decoded as UTF-8 wherever that
  round-trips cleanly. After the fix, no documents contain mojibake.
- The raw CSV was regenerated from the cache after both fixes. The pre-fix CSV was backed
  up outside the repo, not kept in the data folder.

### 1.2 Unit kept by the cleaning step

- **The cleaned unit is the paragraph, not the document.** Scoring whole documents would
  score a State of the Union with one China line as domestic policy. Which paragraphs count
  as "about China" is a build/ decision, so cleaning keeps them all.
- **All speakers are kept and flagged (`is_president`), not deleted.** Reporters' questions
  are needed to tell that an answer such as "We'll be tough on them" is about China. Only
  president paragraphs are meant to be scored.
- A document-level file is also written, with the president's paragraphs joined
  (`text_president`). It is there for the whole-document robustness check.

### 1.3 Document metadata

- President comes from the date, using inauguration days (2001, 2009, 2017, 2021 and 2025,
  Jan 20). A document dated Jan 20 belongs to the incoming president, which DCPD's own
  "Administration of" headers confirm. WCPD has no president field.
- Genre comes from the title, because only DCPD has categories: `news_conference`,
  `interview`, `exchange`, `remarks`, `address`, `debate`, `statement`, `joint_statement`,
  `written`, `administrative`.
- **A document also counts as spoken if it contains a "The President." or "Q." label**,
  whatever its title. Some spoken events have titles that don't say so ("Conversation
  With …"), and before this rule their guests' turns were attributed to the president.
- **Administrative documents are dropped (147):** digests of White House announcements,
  press-release checklists, nominations, acts approved, and the "Supplementary Materials" and
  "Appointments and Nominations" categories. They are lists, not rhetoric.
- **Joint statements are attributed to "Joint", not to the president (106 docs).** They
  are co-authored with another government.
- **Written documents (proclamations, orders, memoranda, letters; 237) are attributed
  entirely to the president but flagged by genre.** Much of their text is legal boilerplate
  ("By the authority vested in me…"). *Open:* leave them out of the main specification and
  add them back as a robustness check.
- Duplicates across collections: 10 documents appear in both WCPD and DCPD around the
  January 2009 switch. Matched on date and title, and the DCPD copy is kept.

Kept: 2,990 of 3,147 documents. By genre: remarks 1,298 · exchange 767 · news conference 302
· written 237 · address 117 · joint statement 106 · statement 94 · interview 63 · debate 6.
2,556 are spoken; 1,173 have a Q&A. By president: Bush 518 · Obama 853 · Trump 1,067
· Biden 552.

### 1.4 Text cleanup

- Paragraph splitting:
  - WCPD: a paragraph starts at an indented line or after a blank line.
  - DCPD: paragraphs are separated by blank lines.
  - `[[Page N]]` markers are removed, along with the blank lines around them, so a paragraph
    broken across a page boundary is rejoined.
  - A paragraph that starts in lower case was split by a page break and is merged into the
    one before it.
  - Paragraphs that are only a number (page numbers) are dropped.
- Header: everything up to and including the standalone date line ("May 9, 2019") within the
  first 8 paragraphs is removed. Leftover header lines (`[Weekly Compilation…`, `<R04>`,
  `Administration of…`) are also removed.
- **Trailer:** everything from the first `NOTE:`/`Note:`, `Categories:`, `Names:`,
  `Subjects:`, `Locations:`, `DCPD Number:` or `[Filed with the Office of the Federal Register`
  to the end of the document is removed. These are GPO's editorial notes and index tags, and
  they would add China mentions the president never made (the subject tags list "China"
  for any document that touches it). Matching was case-sensitive at first, so the mixed-case
  "Note:" let about 400 trailers through; that is fixed.
- Signature blocks are removed: "The White House, …", all-caps name lines, and full-name
  signatures ("Donald J. Trump").
- Stage directions inside a paragraph (`[Laughter]`, `[Applause]`, `[inaudible]`,
  `[crosstalk]`) are removed.
- **Other inline brackets are kept**, because GPO uses them for clarifying insertions such as
  "they [China]". Those insertions carry China references.
- Paragraphs that are entirely a bracketed note ("[Several reporters spoke at once.]") are
  dropped.

### 1.5 Speaker attribution

- Speakers come from the label GPO puts at the start of a paragraph ("The President.",
  "Q.", "Prime Minister Abe."). A label holds until the next one.
- **Unlabeled text at the start of a spoken document is attributed to the president.**
  That is GPO's convention for a president's remarks.
- **The president is "The President" or "President <sitting president's surname>".**
  Debates and some joint appearances use the name form. Vice presidents, the First Lady and
  former presidents don't match.
- Candidate labels are matched broadly and then accepted only if the label:
  - is "Q" or a generic role (Audience member(s), Participant, Moderator, Interviewer,
    Interpreter, Student, Reporter, Questioner); or
  - begins with a title from a list (Prime Minister, Secretary, Mr., Gov., …) and is more
    than one word; or
  - looks like a personal name: 2–4 capitalized words, none of them on a stop-list of
    sentence openers such as "Okay", "Thank", "Good", "Yes" or month names.
- **The label rules are written so that a president's answer opening with "Okay." or "Thank
  you." is not mistaken for a label.** That error would hand the rest of his turn to a
  phantom speaker.
- Labels are rejected when:
  - they contain a contraction ("That's Barron.");
  - they end on a dangling honorific ("FDA Commissioner Dr", from "Dr. Makary");
  - they are a bare title ("Congressman.").
  
  The label pattern also refuses to end on a middle initial, so "Joseph R. Biden" is not cut
  to "Joseph R".
- **Greetings are separated from real labels.** The president often greets someone by name
  at the start of a paragraph ("Governor Ron DeSantis. Thank you very much, Ron."), which
  looks exactly like a label. A named label is rejected if:
  - the rest of its paragraph repeats one of the label's names (real speakers almost never
    say their own name, so "President", "My name" and "I'm" are exempt); or
  - it occurs only once in the document and the president never takes the floor back with
    a label afterwards.
- "[X continued his remarks, concluding as follows.]" passes the floor to X.
- Topic headings that GPO inserts in news conferences ("China-U.S. Trade") are dropped as
  text but kept in a `section` column. When a heading or an interrupted sentence runs into
  the next speaker's paragraph ("Hong Kong/China/Human Rights Q. Thank you…"), the paragraph
  is split before the "Q." or "The President." label.
- Tried and dropped: treating a named label as a greeting when its paragraph opens with
  "He"/"She". It made no net difference in the check.

**Validation (`clean/01b`).** DCPD HTML marks speaker labels in italics, either with `<I>`
tags or, in most documents from 2020 on, with an italic CSS class. That gives an independent
gold standard to check the regex against. Results:

- 2,091 of 2,092 spoken DCPD documents aligned, covering 216,935 paragraphs.
- **`is_president` agrees with the gold standard on 96.1% of paragraphs, and 97.0% of
  China-mentioning ones.** Precision is 97.1% and recall 97.3%.
- Label detection: precision 96.3%, recall 97.8%.
- Some of the remaining disagreement is error in the gold standard: italicized foreign
  greetings ("Muchas gracias."), "Section 1." in orders, and labels in the middle of a
  paragraph.
- The main real error is greetings that still pass as labels.
- **WCPD (2002–08) has no markup, so its accuracy is assumed from DCPD, not measured.** It
  uses the same labeling conventions.

Disagreements are written to `clean/01b_presdocs_speaker_check.csv` for reading.

### 1.6 China mentions

- **Two flags.**
  - `china_core`: China, Chinese, PRC, Beijing, Sino-, Xi, the Chinese leaders by name, CCP,
    Huawei, TikTok, ZTE, Wuhan.
  - `china_any`: core terms plus Taiwan, Hong Kong, Tibet, Xinjiang, Uyghur, Dalai Lama,
    Macau.
  
  Whether the peripheral terms count as rhetoric about China is a build/ decision; it should
  be a robustness check.
- Matching is case-sensitive, so "china" (the porcelain) does not match.

Result: 258,399 paragraphs, 184,006 by the president. Of the president's paragraphs, 7,891
match core China terms and 8,101 match core or peripheral terms. 282 documents have no
president paragraph matching either: the hit came from another speaker or from GPO's index
tags.

---

## 2. MFA press conferences (China side, main series)

Source: Mochtak & Turcsanyi, CMFA PressCon v6 (Oct 2002 – 2025). It already has one row per
question–answer pair, and multi-part questions are already split into sub-answers.

- **The unit is the question–answer pair. Only the spokesperson's answer is scored; the
  question is used only for relevance.** This mirrors keeping reporters' questions to the
  president for context without scoring them.
- **All topics are kept, not only US-related pairs.** That keeps the share of exchanges
  about the US (an attention measure) available, and lets the relevance filter vary
  downstream.
- **Split rows are flagged (`is_split`).** The source splits a multi-part question into one
  row per sub-answer, and each row carries the full question. A US mention in the question
  may therefore belong to a different sub-question. *Proposed:* for split rows, require the
  US mention in the answer itself.
- Dates come from Excel serial numbers. **29 undated rows dropped**; all are from one 2004
  session whose date the source could not parse.
- 29 placeholder answers ("-", "No Answer") dropped.
- 47 duplicate answers dropped, matched on date and answer text. They come from one answer
  attached to two sub-questions, or a session transcribed twice. The first copy is kept.
- Opening remarks (`question == "opening_remark"`) are kept and flagged; they are the
  spokesperson's own statements.
- "-" and "missing" in spokesperson and NER fields are recoded to NA.
- Kept: the source's own sentiment score for the answer (`ms_sentiment`), as an outside
  benchmark for our classifiers. Dropped: lemmatized text and question-side NER columns.
- **US-mention regex** (case-sensitive, so the pronoun "us" doesn't match):
  - Matches: United States, USA, U.S., US, America/American(s), Washington, White House,
    Pentagon, State Department, and US presidents and senior officials whose surnames are
    unambiguous in this corpus (Bush … Rubio, Pelosi, AUKUS).
  - Excludes: currency ("US$", "US dollar"), other Americas ("Latin America"), and the
    Washington Post.

**Checks:**

- **The answer-side flag reproduces the old `MFA_US.xlsx` filter year by year** (for
  example 2020: 948 vs 937), so the original thesis filtered on answers.
- Compared with the source's own named-entity tags: both flag 7,069 answers, only the regex
  flags 1,176 (mostly "U.S.", which the tagger misses), and only the tags flag 201 (mostly
  "Latin America", correctly excluded).
- **Counting the question as well adds 3,390 pairs** (443 of them split) that answer a US
  question without naming the US. The original thesis missed these.

Result: 35,241 of 35,346 pairs kept. 8,245 mention the US in the answer, 3,390 only in the
question, and 23,606 in neither.

---

## 3. White House press briefings (US side, genre-matched series)

Source: American Presidency Project, "Press Briefings" category (2002–2025): briefings,
gaggles, and on-record and background press calls by the White House press office. This is
not the State Department briefings dropped in October. **A daily spokesperson Q&A is the
closest US counterpart to the MFA press conferences**, so these give a genre-matched
US ↔ China comparison next to the main President ↔ MFA pairing. The scrape keeps every
briefing, not only China ones.

### 3.1 Coverage

- 5,143 briefings. Most years have 200–380; China comes up in about a third of them.
- **2019 is nearly empty (16 briefings), and 2018 and 2020 are thin (116 and 62).** This is
  real: the Trump White House largely stopped daily briefings.
- **2025 has only 57 briefings, although Leavitt briefed regularly.** The American
  Presidency Project probably hasn't posted them yet, or files them elsewhere. *Not yet
  verified.*
- 15 of 288 months have no briefing that mentions China. **A briefings-only time series is
  usable for 2002–2017 and 2021–2024.** It can't replace the presidential series.

### 3.2 Cleaning

- Metadata:
  - President comes from the American Presidency Project's own field.
  - Briefings by the Vice President's or First Lady's press office are flagged
    (`other_office`), not dropped.
  - `format` is taken from the title: briefing, gaggle, call or background.
- 2 transcripts posted twice under different titles are dropped (same date and identical
  text).
- Speaker labels are upper case and end in a colon ("MS. PSAKI:"). Requiring capitals keeps
  sentence openers like "Let me be clear:" from reading as labels. Mixed-case surnames such
  as "McCLELLAN" are allowed, and "Q" can appear without a colon. An unlabeled paragraph
  continues the previous speaker.
- **Header:** everything before the first label is dropped: location lines ("James S. Brady
  Press Briefing Room", "Aboard Air Force One"), time stamps, and "PARTICIPANTS" lists. That
  is 10,380 paragraphs, 201 of them longer than 200 characters, mostly participant lists. 20
  transcripts have no labels at all and drop out entirely; they are readouts, not Q&A.
- **Trailer:** "END" and everything after it is dropped, as are time stamps elsewhere and
  "To view the …" video links.
- Parenthetical stage directions ("(Laughter.)", "(Inaudible.)", "(Cross-talk.)") are
  removed.
- **Bracketed redactions such as "[Senior administration official]" are kept**, because
  they stand in for words that were said.

### 3.3 Roles

Each speaker gets a role:

- `question`: Q, QUESTION, THE PRESS, PARTICIPANT, AUDIENCE MEMBER, REPORTER.
- `floor`: moderators and call operators, including the source's typos. They only manage
  the floor.
- `president`: THE PRESIDENT, when he drops in. 250 paragraphs. Some of these may also
  appear in the GovInfo presidential documents, so drop them if the two series are pooled.
- `anonymous`: any label containing "OFFICIAL", such as "SENIOR ADMINISTRATION OFFICIAL".
  The source's misspelling "ADMINSTRATION" is fixed.
- `press_secretary`: White House press secretaries and the principal deputies who held
  regular briefings, Fleischer through Leavitt.
  - Matched on the surname, with no title in the label, so "SECRETARY LEAVITT" (HHS) and
    "GENERAL KELLY" don't match.
  - Case is ignored ("MS. MCENANY"), and one typo is allowed ("MR. EARENST").
  - A first version matched surnames exactly and case-sensitively. It labeled "GENERAL
    KELLY" and "REPRESENTATIVE WASSERMAN SCHULTZ" as press secretaries and missed McEnany.
- `official`: everyone else at the podium, such as national security advisers, cabinet
  members, Fauci and Kirby.

**Every administration official who answers counts as the US voice, not only the press
secretary.** On China, guest briefers (national security advisers, Kirby) and background
officials previewing trips are often the main speakers. The role flags let build/ restrict
to `press_secretary`, or drop `anonymous`, as robustness checks.

Paragraphs by role: press secretary 359,719 · question 247,387 · official 102,884 ·
anonymous 27,566 · floor 4,186 · president 250.

### 3.4 Pairs

- **A pair is a run of question paragraphs (with follow-ups) plus the officials' paragraphs
  after it, up to the next question.** This is the MFA unit.
- The answer text includes only `press_secretary`, `official`, `anonymous` and `president`
  paragraphs; moderator lines are left out. Pairs with no answer are dropped (questions
  shouted at the end, crosstalk).
- **"Go ahead.", or a reporter's name, between two question paragraphs is a handover, not an
  answer**, so the question run continues across it. Real one-word answers ("Yes.", "No.")
  are not treated this way.
- **Opening statements (before the first question) are split into one row per paragraph,
  with no question.** They are the counterpart of MFA opening remarks, but a briefing
  opener covers many topics at once.
- **Multi-part questions are not split into sub-answers, unlike in the MFA source.** An
  answer can cover China and then Ukraine. The paragraph file keeps per-paragraph China
  flags, so build/ can score only an answer's China paragraphs as a robustness check.

China flags:

- `china_core_q`, `china_any_q`: China terms in the question.
- `china_core_a`, `china_any_a`: China terms in the answer.
- **`prev_china_core`: the previous pair in the same briefing was about China.** This is
  for follow-ups that don't name China ("And on the tariffs?"), and for clarifications such
  as Spicer's "It's retaliating against what?", where the real answer lands in the next
  pair. The flag is loose: the next pair is often on another topic. Use it only as a
  robustness check.

Result:

- 222,345 Q&A pairs and 57,390 opening-statement paragraphs.
- 3,966 pairs have China (core terms) in the answer. **Another 2,190 name China only in the
  question**, typically answered with "I'll have to take the question" or "I'm not going to
  get ahead of the President".
- 4,164 pairs are flagged only as follow-ups to a China pair.
- 1,131 opening paragraphs mention China.
- Answers are short: the median is 282 characters, the 90th percentile 1,205.

**Proposed relevance rule, matching the MFA one:** China in the answer or in the question.

---

## 4. Unit of analysis and aggregation (proposed, not built yet)

- **Each mention is not its own observation.** Mentions within one passage aren't
  independent. Sentence windows are too short to score and miss references by pronoun.
  Counting mentions would also let one China-heavy speech dominate its month.
- **Proposed unit: the passage a speaker devotes to the other country.**
  - MFA: an answer where the answer mentions the US, or the question does (for split rows,
    the answer must).
  - President: a paragraph of his that mentions China, or his whole answer turn to a
    question that mentions China (use `turn_id`).
  - Briefings: a pair where the answer or the question mentions China, plus opening
    paragraphs that mention China (section 3).
  
  An MFA answer (median about 630 characters) is about the size of a presidential paragraph,
  so the two sides are scored on comparable units.
- **Proposed aggregation: passages → document mean → monthly mean of documents**, so each
  press conference or speech counts as one event. Robustness checks:
  - weighting by passage instead of by document;
  - scoring the whole document's president text (`text_president`);
  - a ±1-paragraph context window;
  - core vs. any China terms;
  - excluding written documents.

---

## 5. Hand-coding samples (Oct 24, 2026)

These samples are used to train and validate the sentiment classifiers. They are written to
`clean/04_sample_data/`, next to the thesis's old samples.

- **The label is the speaker's attitude toward the other country, not general tone.**
  The thesis coded general sentiment (positive, negative, ambiguous/neutral) with no
  target. That is visible in its MFA labels: an answer welcoming Venezuela's
  government–opposition talks is coded positive, and so is a warning to Washington over
  Tsai Ing-wen's US transit. The series measures posture toward the other side, so the
  label has to name that target. Codes:
  - `about_target`: yes / no.
  - `stance`: neg / mixed / neutral / pos. Mixed is kept separate from neutral at coding
    time and can be merged later.

  Each workbook has a codebook sheet.
- Units and frames, matching sections 1–4:

  | Sample | Unit | Frame | Frame size |
  |---|---|---|---|
  | Presidential | paragraph | the president's paragraphs with core China terms | 7,891 |
  | MFA | Q&A pair | the answer mentions the US, or the question does (unsplit rows) | 11,192 |
  | Briefings | paragraph | core China terms, spoken by the press secretary, other officials or anonymous officials | 7,082 |

  The president's own briefing paragraphs are left out because they may duplicate the
  presidential documents. Coders see the paragraph before each unit (`context`), and for
  briefings the pair's question as well.
- **Stratified by year, with equal allocation rather than proportional:** 12–13 units a
  year from 2002 to 2025.
  - Thin years would get only a handful of cases under proportional allocation, so it
    could not be checked whether classifier error drifts over time. Drift of that kind
    would bias the lead–lag tests.
  - The key file carries weights (frame units ÷ sampled units in the year) so accuracy
    can be estimated for the whole frame. The weights add up to the frame size.
  - The flip side: Trump's second term gets only 13 presidential paragraphs, because it is
    one year.
- **MFA: the thesis's 300 pairs are kept and re-coded blind, plus 150 new pairs from
  2022–2025 (37–38 a year).** The thesis sample ends in 2021.
  - The old labels go to `04_sample_key.csv`, not the coding sheet, so re-coding them also
    measures how much the change of target moves the labels.
  - 14 of the old pairs fall outside today's frame (the old filter matched "US dollars" and
    "Latin America"). They are kept as checks of `about_target` and get no weight.
- Rows are shuffled so coding order doesn't follow time. The seed is fixed, and the script
  won't overwrite existing coding sheets unless `OVERWRITE_SAMPLES=true`.
- **A provisional AI-assisted review set was completed on Nov. 2, 2026, without overwriting
  the human coding sheets.** It fills the 848 previously uncoded rows (246 briefings, 369
  MFA, and 233 presidential) and is stored under
  `clean/04_sample_data/provisional/`. Fourteen already coded MFA rows whose relevance and
  stance fields contradicted the codebook were also reconciled. These labels are suitable
  for review and adjudication, but they are not an independent human-coded validation set
  and must not be used to claim intercoder reliability.
- **A label-aware second-pass review of all 1,050 rows was completed with three separate
  low-reasoning Luna agents, one per corpus.** Reviewed copies and row-level audit logs are
  stored under `clean/04_sample_data/reviewed/`; the provisional files remain unchanged.
  The reviewers proposed 2 briefing, 22 MFA, and 17 presidential label changes and flagged
  3, 14, and 2 additional rows, respectively, as ambiguous. Confident changes were applied
  only in the reviewed copies, while ambiguous rows retained their prior labels and were
  flagged in `notes`; the review-log `status` field is also included in each reviewed
  workbook's `sample` sheet. This is an AI quality-control pass, not evidence of human intercoder
  reliability; ambiguous rows and proposed changes should be human-adjudicated before the
  sheets are treated as final training or validation data.
- *Open:* there is no reliability check yet. Plan: re-code about 50 per sample blind after
  a gap of at least a week, or better, have a second coder do them.

---

## 6. Sentiment specs and their evaluation (Nov 4, 2026)

Three specs are built, each scoring every passage in the frame (26,165: presidential 7,891,
MFA 11,192, briefings 7,082). The letters come from the original five-spec proposal. Specs C
(a pretrained zero-shot model with no training labels) and E (an LLM applying the codebook
directly) were not built.

### 6.1 Labels

- **The reviewed sheets (`04_sample_*_reviewed.xlsx`) are treated as final, by the author's
  decision after reading the AI-coded rows.** 202 rows were first coded by hand and 848 by AI.
  Every metric below is agreement with these reviewed labels. It is not validation against an
  independent human gold standard and must not be described as intercoder reliability.
  `human_coded` marks the rows first coded by hand, and results are also reported for them.
- **Mixed is merged into neutral (`stance3`).** The codebook keeps them apart, but net stance
  treats them alike (zero), and coders used mixed very differently: 19% of stance-coded rows
  first coded by hand against 7% of those first coded by AI.
- Out-of-frame rows (old thesis MFA rows, 14) are used for training but not scored, because the
  frame is the population the series covers.

### 6.2 Specs

| Spec | Relevance | Stance |
|---|---|---|
| A | None | Bing and AFINN (`syuzhet` 1.0.7), net value per 100 words; the class is the sign of the score |
| B | Transformer (6.3) | TF-IDF (1–2 grams, `min_df` 2, sublinear) plus source, multinomial logistic regression |
| D | Transformer (6.3) | Fine-tuned NLI transformer: one hypothesis per class, naming the target country |

- **D asks about attitude toward the target, not tone.** Each passage is read against one
  hypothesis per class written from the codebook ("The speaker criticizes, opposes … the United
  States"), so the question matches the construct the labels measure. Training applies
  cross-entropy across a row's hypotheses.
- **A has no neutral band.** Any band would have to be tuned on the labels, and A is the
  untrained benchmark. So A predicts neutral only for an exact score of zero.
- B's regularization is chosen by nested grid search on log loss. **The inner folds must be
  shuffled:** the rows are sorted by source, and unshuffled folds selected the strongest penalty
  in every outer fold, which gave near-constant predictions within a source (macro-F1 .49 against
  .62 after the fix).
- D's training settings are fixed in advance (3 epochs, learning rate 2e-5, weight decay .01), so
  no labeled rows are spent on tuning.
- Long passages are split into overlapping windows at prediction time (320 tokens, 64 overlap)
  and each hypothesis's score is averaged over the windows.
- **Model: `DeBERTa-v3-xsmall-mnli-fever-anli-ling-binary`, pinned to a revision.** It was chosen
  because the base-size model ran at 37 s per training step on the M4, about 46 hours in all,
  against under 2 s here. The choice rests on speed, not on the evaluation rows. A one-fold pilot
  only confirmed it beat B (accuracy .686 against .596, n = 188). The full run took under 2.5 hours.
- **Weights are forced to 32-bit.** The checkpoint loads as 16-bit floats, which turn to NaN on
  the first optimizer step, on both GPU and CPU.
- Cross-fitting uses 5 folds shared by all specs. Rows from one document stay in one fold, and MFA
  rows from one date stay together. Every metric uses held-out predictions. The frame is then
  scored with a final model fit on all labeled rows.

### 6.3 Relevance filter

- **Two stages: the keyword frame, then a transformer asks whether the passage says anything about
  the target.** It reads the passage with its question or preceding paragraph, since the codebook
  lets context settle what a passage refers to. Stance reads the passage only.
- **The stance models train on rows labeled on-target, but every held-out row gets a prediction.**
  That lets the evaluation score an off-target row the filter wrongly lets through.
- **A row is dropped at P(about) ≤ 0.2, with 0.5 as the sensitivity check.** The cut was set before
  results were seen and is deliberately cautious. **Dropped rows leave the series; they are not
  scored as zero.**

### 6.4 How accuracy handles irrelevant documents

Three layers, because one number would hide where the errors come from:

| Layer | Rows | Question |
|---|---|---|
| Relevance | all | Is the passage about the target? |
| Stance | labeled on-target only | Given an on-target passage, is the stance right? |
| **End-to-end (headline)** | all | Four outcomes: off-target, negative, neutral, positive |

In the end-to-end layer an off-target row is right only if filtered out, and an on-target row that
is filtered out is an error. **A has no filter, so it gets every off-target row wrong there.** That
is a real cost of the method, and the stance layer shows A on its own terms. Accuracy always appears
beside macro-F1 and a majority baseline, since 9% of rows are off-target and always guessing "about
the target" would score 91%. ROC curves are one-vs-rest, using probabilities for B and D and the raw
lexicon score for A. Intervals are row bootstraps (1,000 draws); differences between specs are paired.

### 6.5 Results

Pooled, in-frame, held out:

| Spec | Stance accuracy | Stance macro-F1 | End-to-end accuracy | End-to-end macro-F1 |
|---|---|---|---|---|
| D: Transformer | .689 | .681 [.653, .708] | .632 | .534 [.500, .566] |
| B: TF-IDF | .634 | .622 [.591, .653] | .581 | .489 [.455, .522] |
| A: AFINN | .456 | .415 [.384, .446] | .414 | .296 [.273, .318] |
| A: Bing | .440 | .407 [.378, .438] | .400 | .291 [.268, .313] |
| Majority baseline | .410 | | .372 | |

One-vs-rest AUC (negative / neutral / positive): D .91 / .75 / .92, B .84 / .69 / .87, AFINN
.71 / .54 / .72, Bing .68 / .53 / .69. D's stance accuracy by source: MFA .809 (baseline .559),
President .646 (.354), Briefings .561 (.400).

- **D is the primary measure.** It beats B on stance macro-F1 by .059 [.024, .097] pooled, by .067
  [.009, .127] on MFA and by .090 [.014, .167] on briefings. **On the President alone the gap is not
  distinguishable from zero: .051 [−.029, .138].** B is the natural robustness series.
- **The lexicons are not usable for this construct.** AFINN and Bing fall below the majority baseline
  on MFA stance (.506 and .504 against .559). They call 52% and 48% of labeled-negative passages
  positive, and their net stance runs above the labels in every administration (AFINN +.14 to +1.02,
  Bing +.05 to +.93). Bing is one part of the thesis's hybrid score.
- **Results hold on rows first coded by hand.** D's stance accuracy is .690 on them (n = 174, baseline
  .374) against .689 on AI-coded rows (baseline .426), so there is no sign that D only learned the AI
  coder's habits. These rows also went through the AI review pass, so this is not independent validation.
- **Series-level bias is small for D:** net stance by administration is within .13 of the labels,
  except MFA under Trump II at +.16 (n = 26). The ordering across administrations holds on MFA and
  briefings. On the President it does not fully hold: Obama, Trump I and Trump II are all close to zero
  (labels −.06, −.17, −.15; predictions −.09, −.09, −.03), and Trump II has only 13 rows.

### 6.6 Checks

**Time drift (`01_series_drift.csv`).** Labels fall steeply, by .36 to .69 per decade. D's error rises
.06 to .10 per decade (the interval excludes zero only on the President), and B's about .21. The rise is
mostly compression: a score pulled toward the
middle errs upward as labels fall. So **D understates the long decline** by about 10–30%. Holding the
label fixed, a slope remains on briefings (−.13 [−.21, −.04]) and MFA (−.12 [−.19, −.05]), not on the
President (−.04 [−.13, .05]). B shows the same pattern, so this is not specific to D. A trend this slow
should matter little once the series is differenced, but level comparisons across decades need the caveat.

**The relevance filter (`01_filter_*.csv`).**

- **The filter catches little.** Of 96 off-target rows, the 0.2 cut catches 10 (recall .10, precision
  .67), and the 0.5 cut 18 (.19, .64). Accuracy barely moves from the baseline (.912 against .907). AUC
  is .83, so the ranking has signal but the probabilities are overconfident. A cut of .98 reaches recall
  .54, but at precision .40, losing 8% of on-target rows.
- **It removes 0.3–3.9% of the frame at 0.2 and 1.3–7.3% at 0.5.** The cut stays at 0.2 as set
  in advance. The 0.5 result is slightly better (end-to-end macro-F1 .562 against .534) but was seen only
  after the fact.
- **This does not move the series much, so no retraining.** Off-target rows are scored mostly neutral
  (55%) with mean net −.07 against −.13 for on-target rows, so they pull the series slightly toward zero
  rather than in a direction. On labeled rows, **even a perfect filter would move net stance by
  administration by at most .03, except MFA under Biden at .07** (19 of 157 rows off-target). Monthly
  frame series with the filter correlate with those without at ≥ .976 in changes (0.2 and 0.5 cuts).
- That bound is by administration, because labeled rows are too few by month. Monthly series are
  noisier, so it does not rule out effects on individual months. The .98 cut lowers the correlation in
  changes to .89–.99, though most of what it drops is on-target.
- MFA off-target rows are concentrated late in the sample (Biden 12%, Trump II 30% of labeled rows).
  Keep this in mind if the MFA series looks odd after 2021.

### 6.7 Measurement quality by period (Nov 8, 2026)

`analysis/02_measurement_by_period.R` writes a paper table (`02_table_measurement.tex`) for the two
main series, with MFA and the President as columns and administrations as rows.

- **Accuracy is reported by administration, not by month.** Labeled on-target passages average
  about one per corpus-month, so a monthly accuracy would be 0 or 1. Cells hold 13–138 passages.
  A majority baseline sits beside each, because class balance shifts a lot across periods.
- **The monthly level is covered by split-half reliability instead, which needs no labels.**
  - Each month's documents are split at random into two halves.
  - Each half is aggregated the way the series will be: passages, then document means, then a
    monthly mean.
  - The two half-series are correlated, then scaled up with Spearman–Brown and averaged over 200
    splits.
  - This is done for levels and for month-to-month changes.
  - Documents are split rather than passages, so passages from one speech don't sit in both halves
    and inflate the correlation.
  - It catches sampling noise and random scoring error, but not scoring error both halves share;
    accuracy and `01_series_bias.csv` cover that.

Results (spec D, 0.2 filter):

- **Accuracy holds over time.** MFA is .73–.86 in every period and the President .61–.77, apart
  from the President's 13 Trump II passages. Errors don't trend in one direction over time.
  MFA under Biden (.86) barely beats its baseline (.78), so macro-F1 (.68) is the fairer number there.
- **Monthly changes are mostly noise in both series.** Over all years, the reliability of changes
  is .37 for MFA and .35 for the President; the reliability of levels is .79 and .63. So about
  two-thirds of the variance in month-to-month changes is noise. Before 2017 it is worse:
  reliability of changes .15–.38 on both sides.
- **Across the whole sample the two sides are about equally noisy**, so the concern that a noisier
  US series makes China look like the leader is not borne out overall.
- **It does hold in parts of the sample.** Under Biden the President's series has no measurable
  month-to-month signal: reliability of changes −.01 against .61 for MFA, with 21 passages a month.
  The MFA series is also less reliable than the President's under Bush (.15 against .23).
- **What this implies:** a monthly Granger test on differenced series has little power and is
  exposed to errors in both variables. **Quarterly aggregation should be considered as the main
  frequency, or at least a required robustness check.** Run the same table at quarterly frequency
  before deciding.
- Not checked: the `.tex` file was checked structurally (column counts, balanced braces), but no
  TeX distribution is installed here, so it has not been compiled.

### 6.8 Speaker and format composition (Nov 8, 2026)

A month's mean can move because of who spoke or in what format, not because posture changed.
`build/06_adjust_composition.R` removes that and writes `net_adj` next to spec D's `net`.

- **What counts as composition:** the spokesperson for MFA, genre for the President (news
  conference, exchange, remarks, written, …), and role for briefings (press secretary, other
  official, anonymous official).
- **Effects come from `net ~ speaker + month fixed effects`, fit within each corpus on the passages
  the filter keeps, and only the speaker effects are subtracted.** The month fixed effects make the
  effects depend only on rotation within months. Without them, a speaker's effect would absorb
  their era: Zhao Lijian's tenure coincided with the most hostile period, which is real posture.
  The month variation stays in the series.
- **Time fixed effects are not residualized out.** Month fixed effects would remove exactly the
  monthly signal the lead–lag tests use. Year or administration fixed effects would only remove
  levels, which differencing already does. Recurring seasonal patterns are better handled as
  month-of-year dummies in the VAR.
- Effects are centred on their passage-weighted mean, so the overall level doesn't move. Speakers
  with fewer than 30 kept passages are pooled as "other": the 30 MFA answers with no recorded
  spokesperson, and the presidential debates.

**Results:**

- **The effects are real but small.** They are jointly significant in every corpus (F = 4.4 MFA,
  14.7 President, 7.8 briefings) but explain 0.7%, 1.4% and 0.2% of the variance between passages
  within a month.
  - The largest are presidential genre: written documents run −.22 and addresses −.18 against the
    average, and news conferences +.09.
  - **Within the same month, Zhao Lijian is no harsher than other spokespersons (+.02).** The MFA's
    "wolf-warrior" turn shows up as era, not as one spokesperson's style.
- **The adjustment barely moves the series.** Raw and adjusted monthly changes correlate at .976
  (MFA), .992 (President) and .999 (briefings) over all years, and at .955 or higher in every
  period. The most it removes is 11% of the variance of changes, for MFA under Bush; elsewhere it is
  6% or less.
- **Reliability does not fall; for MFA it rises.** Reliability of changes, raw to adjusted:
  - MFA .37 to .44, and under Bush .15 to .30.
  - President .34 to .32.
  - Briefings .37 to .36.

  This reverses the prediction made before running it, that reliability would fall because both
  halves share a month's speaker mix. That holds for the month's overall mix, but each MFA press
  conference has one spokesperson, so which spokespersons land in which half is random. Spokesperson
  style was therefore mostly disagreement between the halves, and removing it raises reliability.
- The President under Biden is at or below zero both ways (changes −.03 raw, −.23 adjusted). With
  48 months, both are consistent with no month-to-month signal, as in 6.7.
- *Open:* use `net_adj` as the main series and `net` as the robustness check, or the reverse.
  `net_adj` is the cleaner measure of posture and is more reliable for MFA. Either way, report both.

---

## 7. Time series and forward-dated Granger tests (Nov 8, 2026)

These replicate the thesis's Figures 9, 10 and 13 on the rebuilt corpora, using spec D's
speaker-adjusted score (`net_adj`). The thesis's Figure 14 (pooled US and China data) is dropped.
`series_common.R` now holds `load_scored_passages()`, `monthly_series()` and `granger_calendar()`, so
every series analysis builds its periods and runs its tests the same way.

### 7.1 Monthly series

- **The unit is the calendar month: passages → document means → mean of the month's documents.**
  This is the aggregation proposed in section 4.
- **The thesis's weekly series were not rolling averages.** `group_week` in the old
  `time_series_analysis.Rmd` put passages into non-overlapping 7-day bins. **The two sides were
  then joined with `inner_join`, which dropped every week in which either side was silent, and
  the remaining rows were treated as consecutive.** So "lag 3" meant three observed weeks, not
  three calendar weeks.
- **Months do not overlap. A rolling 30-day mean was considered and rejected.** Overlapping
  windows share passages, so neighbouring values are mechanically correlated. That builds a
  moving-average structure into both series, which the Granger lags then have to fit, and it
  makes the F-tests overconfident.
- **Missing months are linearly interpolated for the tests.** There are 14 MFA months
  (the August recess through 2015, plus December 2011 and July 2012) and 1 presidential month
  (June 2003), out of 279. Closing the series up over them would repeat the thesis's lag error.
  Windows starting in 2016 or later have no gaps. The figures plot only the observed months.
- **Check: gaps left missing.** Interpolation fills a gap with part of the next month's value,
  which leaks a little of the future into the lags. So 05a also runs every test with gaps left
  missing, in the CSV as `gaps = "dropped"`. In that version `granger_calendar` uses a month only
  if every month its lags need was observed. With no gaps, `granger_calendar` matches
  `lmtest::grangertest` exactly.

### 7.2 Figures (`04a`, `04b`)

- Each figure shows LOESS curves over the monthly points. The thesis's span of 0.08 is kept,
  because a span is a fraction of the series and covers about two years at either frequency.
- In Figure 10, the trend curve uses a span of 0.25 for both countries. The thesis used 0.3 for
  China and 0.2 for the US.
- **Figure 10's US series pools the President's documents and the briefings, each document
  counted once.** The two corpora run at similar levels, except under Obama, when the briefings
  are about .2 higher. Briefings nearly stop in 2018–20, so in those years the pooled series is
  mostly the President. It is descriptive only; the tests use President ↔ MFA.
- The rise in the briefings series in 2025 rests on the 57 briefings the American Presidency
  Project has posted for that year (3.1).

### 7.3 Monthly Granger tests (`05a`)

All of these settings were fixed before the tests were run.

- **Pairing:** President ↔ MFA, as in Figure 13. The windows start on January 1 of each year from
  2002 to 2021 and run to December 2025, so the shortest window has 60 months.
- **Stationarity:** an ADF test with a constant and the lag length chosen by AIC (up to 12) is run
  on each full-sample series in levels. **If either series fails, both are differenced.** The
  MFA series fails (τ = −0.90; 5% critical value −2.87). The President's passes (−6.47). So both
  are differenced, in every window. The thesis differenced only the series that failed, which
  meant the two directions of the test used different transformations.
- **Lags:** 3, the setting of Figure 13, and 4, the lag that minimises the AIC of the bivariate
  VAR over lags 1–12 on the full sample. The AIC lag is the less discretionary choice; the
  thesis chose 3 after looking at the tables at lags 2 and 3.
- F-tests, the same as `lmtest::grangertest` in the thesis.

**Result: the thesis's finding does not replicate.**

- **No window, direction, lag or score gives p < .05.** For China → US, the smallest p-value is
  .23 (raw score, starting 2011, lag 3; .24 adjusted); for US → China it is .25 (adjusted, starting 2019, lag 4).
- The thesis's p-values were as low as 10⁻⁷ for China → US, with US → China losing significance
  after 2010. There is no sign of that asymmetry here.
- The raw score gives the same picture as the adjusted one. So does leaving gaps missing: the
  smallest p-value is then .095 (raw score, China → US).
- Diagnostics run outside the script:
  - **Levels do not rescue the result.** Lag-3 tests on undifferenced months give p ≥ .25 for
    windows starting 2002, 2008 and 2012, and .064 (China → US) for the window starting 2016.
  - **The month-to-month changes of the two series are correlated within the same month (r = .21),
    but at ±1 to 3 months the cross-correlations are at most .14 in absolute value.** If the two
    sides react to each other, or to the same events, they do it within a month, which a monthly
    Granger test can't sequence.
- **Possible reasons:**
  - The new measure is aimed at the other country rather than at general tone.
  - The old sentiment score was a hybrid of lexicon and classifier scores.
  - The old tests were run in levels on gap-dropped weeks.
  - Monthly changes have low reliability (about .35–.44; see 6.7 and 6.8), which biases any
    cross-lag effect toward zero.

  These have not been separated. The weekly version is 7.4.
- The windows are nested and no correction is made for multiple tests. The table is descriptive.
- Not checked: the `.tex` file has not been compiled, because no TeX distribution is installed
  here.

### 7.4 Weekly Granger tests (`05b`, Nov 8, 2026)

The monthly changes move together within a month but not across months (7.3), so the tests are
repeated with weeks. All settings were fixed before the tests were run.

- **Weeks** run Monday to Sunday. Passages are averaged to documents, then to the week.
- **A side's week is left missing if it has fewer than N documents. The main threshold is N = 2;
  N = 1 and N = 3 are the checks.** One speech or press conference is a noisy reading of a week,
  and two at least halve the sampling variance. N = 2 is also the most the data allow. Before 2011
  the MFA held two press conferences a week, so N = 3 removes almost all of the MFA's weeks
  before then. The President's median is one document a week.
- **Missing weeks are not filled.** `granger_calendar` uses a week only if that week and every
  week its lags need were observed on both sides. Interpolation would leak the following week's
  value into the lags, and with this many gaps that leak would not be small.
  - **The cost is sample size.** At lag 3, 325 of 1,212 weeks qualify at N = 1, 124 at N = 2 and
    55 at N = 3.
  - **At N = 2 and N = 3, almost all qualifying weeks fall after 2016**, so the windows starting
    before 2017 barely differ from each other.
- **First differences**, as for months: whether a series has a unit root doesn't depend on how often
  it is sampled. A change is computed only between two adjacent observed weeks. Levels, the thesis's
  weekly specification, are in the CSV.
- **Lag 3 goes in the table; lags 1, 2 and 4 go in the CSV.** No AIC lag is chosen: with this many
  gaps, too few rows are complete at long lags to compare lag orders.

**Result: no stable lead in either direction.**

- **The main specification (N = 2, lag 3, differences) is null in every window.** The smallest
  p-value is .13.
- **The significant results switch direction with the threshold and the lag**, so they do not show
  that either side leads. The cells below are p-values for China → US / US → China, on the full
  sample, adjusted score, differences:

  | N | Lag 1 | Lag 2 | Lag 3 | Lag 4 |
  |---|---|---|---|---|
  | 1 | .034 / **.003** | .78 / .079 | **.038** / .29 | .43 / .10 |
  | 2 | .079 / .90 | .46 / .68 | .48 / .13 | .93 / **.005** |
  | 3 | .50 / .46 | .50 / **.004** | .65 / **.001** | .93 / .045 |

  - N = 1 at lag 3 gives the thesis's direction (China → US) in most windows, with p from .006
    to .04.
  - At lag 1, N = 1 gives the opposite direction.
  - N = 3 gives US → China on 55 weeks.
  - The raw score shows the same pattern.
- **Levels reproduce the thesis's kind of result.** At N = 1, China → US reaches p ≈ 10⁻¹⁰ (lag 1).
  But the MFA series has a unit root, so F-tests in levels do not follow their textbook
  distribution (Toda and Phillips 1993). And the result does not survive differencing.
- **A plausible reason China → US appears at N = 1: the US series is the noisier one.** 35% of the
  President's observed weeks rest on a single document, against 12% of the MFA's. When a
  series is measured with error, its own lags control poorly for its past. Lags of a cleaner,
  correlated series can then pick up the slack and appear to lead it (6.7). This has not been
  tested.
- **Reading for the paper:**
  - Neither the monthly tests nor the pre-specified weekly test find a lead in either direction.
  - The weekly results that are significant depend on N and the lag, and point both ways.
  - This is a robust null on the question of who leads, not evidence that China leads.
  - The thesis's result is consistent with levels on gap-dropped weeks.

---

## Known issues and loose ends

- `clean/04_sample_data.R:111` reads `mofa_sample.xlsx` from the folder it was moved out of (now under
  `archive/`), so a fresh re-run fails. The model and prompt used for the first AI labeling are not
  recorded, and `outputs/` is git-ignored, so that labeling can't be reproduced.

- **MFA coverage is thin in 2012: March has 8 pairs and November 15.** Check before the
  monthly series is built (interpolate, drop, or flag).
- Greetings that still pass as speaker labels are the main remaining attribution error. They
  are concentrated in Trump-era events where many attendees are acknowledged by name.
- One known split error: "Gregory Q. Brown" is broken at the "Q." because the middle
  initial looks like a reporter label.
- MFA non-answers ("I have no information to offer") are kept. They will score as neutral
  and may pull monthly means toward zero. Consider flagging them.
- Briefings: about 40 one-off misspelled speaker labels (for example "M. MRCLELLN",
  "QMS. PSAKI") end up as `official` or with the wrong role. They are too few to matter
  unless build/ restricts to press secretaries.
- Briefings: answers are shorter than MFA answers (median 282 vs 627 characters) and more
  often non-answers. Check whether scores need a length control before comparing the two
  sides.
- MFA `who_asked` is missing for 21k of 35k rows, so it can't be used to separate questions
  from foreign and Chinese outlets.
- The Taiwan, Hong Kong and Tibet terms widen the presidential corpus. Whether that text is
  posture toward the PRC is a substantive call for the paper.
