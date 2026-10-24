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

## Known issues and loose ends

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
