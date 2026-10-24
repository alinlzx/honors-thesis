# Clean the GovInfo presidential documents (raw/01_govinfo_presdocs.csv) into paragraphs
# attributed to speakers, so downstream steps can score only what the president said.
#
# In:  raw/01_govinfo_presdocs.csv  (one row per document, from scrape/01_scrape_govinfo_presdocs.py)
# Out: clean/01a_presdocs_paragraphs.csv  one row per paragraph, all speakers, with
#                                         speaker, is_president and China-mention flags
#      clean/01a_presdocs_docs.csv        one row per document: metadata, genre, counts,
#                                         and the president's text joined (for doc-level scoring)
#
# Choices, and why:
# - Paragraphs, not documents, are the unit kept here. A State of the Union with one
#   China sentence would otherwise be scored as domestic policy. Which paragraphs count
#   as "about China" is decided in build/, so the cleaned file keeps everything.
# - Non-president paragraphs (reporters, foreign leaders, cabinet members) are kept but
#   flagged. Reporters' questions are what make an answer like "We'll be tough on them"
#   China-relevant, and build/ needs them for that link.
# - Speakers come from the paragraph-initial labels GPO uses ("The President.", "Q.",
#   "Prime Minister Abe."). Unlabeled text at the start of a spoken document is the
#   president's. clean/01b checks the labels against DCPD's italic markup.
# - Written documents (proclamations, orders, letters, statements) have no speakers and
#   are all the president's. Joint statements are co-authored, so they are attributed
#   to "Joint" and not to the president. Administrative lists (digests, checklists,
#   nominations, acts approved, supplementary materials) are dropped.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
})
source("config.R")

docs <- read_csv(file.path(RAW_DIR, "01_govinfo_presdocs.csv"), show_col_types = FALSE)

# ---- Document metadata -------------------------------------------------------------

# Inauguration dates; documents dated on the day belong to the incoming president, which
# DCPD's own "Administration of" header confirms for the 2009-2025 transitions.
terms <- tibble(
  start = as.Date(c("2001-01-20", "2009-01-20", "2017-01-20", "2021-01-20", "2025-01-20")),
  president = c("Bush", "Obama", "Trump", "Biden", "Trump")
)
president_on <- function(d) terms$president[findInterval(d, terms$start)]

# Genre from the title, which both collections have (only DCPD has categories).
genre_of <- function(title, category) {
  case_when(
    str_detect(title, regex("^(Digest of Other White House|Checklist of White House|Nominations Submitted|Acts Approved|Contents|Index)", ignore_case = TRUE)) |
      coalesce(category, "") %in% c("Supplementary Materials", "Appointments and Nominations") ~ "administrative",
    str_detect(title, "Debate") ~ "debate",
    str_detect(title, "News Conference") ~ "news_conference",
    str_detect(title, "^Interview|Interview With") ~ "interview",
    str_detect(title, "Exchange With|Question-and-Answer|Town Hall") ~ "exchange",
    str_detect(title, "^Joint |Joint Statement|Joint Declaration|Fact Sheet") ~ "joint_statement",
    str_detect(title, "^Remarks|Toast") ~ "remarks",
    str_detect(title, "Address|Commencement|Eulogy|Farewell") ~ "address",
    str_detect(title, "^Statement") ~ "statement",
    TRUE ~ "written" # proclamations, orders, memoranda, letters, messages, notices
  )
}
SPOKEN <- c("debate", "news_conference", "interview", "exchange", "remarks", "address")

docs <- docs %>%
  mutate(
    president = president_on(date),
    genre = genre_of(title, category),
    spoken = genre %in% SPOKEN
  )

# ---- Paragraphs --------------------------------------------------------------------

# WCPD is fixed-width text: paragraphs start on an indented line or after a blank line,
# and "[[Page N]]" markers can fall mid-paragraph. DCPD paragraphs are blank-line
# separated (see extract_text in the scraper).
split_paras <- function(text, collection) {
  if (collection == "WCPD") {
    text <- str_replace_all(text, "\\n[ \\t]*\\n[ \\t]*\\[\\[Page \\d+\\]\\][ \\t]*\\n[ \\t]*\\n", "\n")
    text <- str_replace_all(text, "\\[\\[Page \\d+\\]\\]", "")
    str_split(text, "\\n(?=[ \\t]{2,}\\S)|\\n[ \\t]*\\n")[[1]]
  } else {
    str_split(text, "\\n\\n")[[1]]
  }
}

paras <- docs %>%
  select(doc_id, collection, president, genre, spoken, text) %>%
  mutate(text = mapply(split_paras, text, collection, SIMPLIFY = FALSE)) %>%
  unnest(text) %>%
  mutate(text = str_squish(text)) %>%
  filter(text != "") %>%
  group_by(doc_id) %>%
  mutate(para_src = row_number()) %>% # position in the raw text, used by clean/01b
  ungroup() %>%
  filter(!str_detect(text, "^\\d+$")) # page numbers

# Header: everything up to the standalone date line near the top ("May 9, 2019").
# Trailer: GPO's NOTE and index fields, the Federal Register filing line, and anything
# after them.
MONTHS <- "(January|February|March|April|May|June|July|August|September|October|November|December)"
date_line <- str_c("^", MONTHS, " \\d{1,2}, \\d{4}\\.?$")
trailer <- "^(NOTE:|Note:|Categories:|Names:|Subjects:|Locations:|DCPD Number:|\\[Filed with the Office of the Federal Register)"

paras <- paras %>%
  group_by(doc_id) %>%
  mutate(
    hdr_end = coalesce(first(which(str_detect(text, date_line) & para_src <= 8)), 0L),
    trl_start = coalesce(first(which(str_detect(text, trailer))), n() + 1L)
  ) %>%
  filter(para_src > hdr_end, para_src < trl_start) %>%
  ungroup() %>%
  filter(
    # header lines left in docs without a date line
    !str_detect(text, "^(\\[Weekly Compilation|\\[Pages? |\\[Online from|<R\\d+>|Administration of )"),
    # signature blocks of written documents
    !str_detect(text, "^The White House,"),
    !str_detect(text, "^(George W\\. Bush|Barack Obama|Donald J\\. Trump|Joseph R\\. Biden, Jr\\.)$"),
    !str_detect(text, "^[A-Z][A-Z .,'\\-]+$") | str_detect(text, "^Q\\.")
  ) %>%
  select(-hdr_end, -trl_start)

# Paragraphs that start in lower case were broken by a page break; rejoin them.
paras <- paras %>%
  group_by(doc_id) %>%
  mutate(block = cumsum(!str_detect(text, "^[a-z]"))) %>%
  group_by(doc_id, collection, president, genre, spoken, block) %>%
  summarise(para_src = first(para_src), text = str_c(text, collapse = " "), .groups = "drop") %>%
  select(-block)

# Stage directions inside a paragraph. Other inline brackets stay: GPO uses them for
# clarifying insertions such as "they [China]".
paras <- paras %>%
  mutate(text = str_squish(str_remove_all(text, regex("\\[(laughter|applause|inaudible|crosstalk|cross talk)[^\\]]*\\]", ignore_case = TRUE))))

# Newer DCPD pages sometimes run a topic heading or an interrupted sentence into the next
# speaker's paragraph ("Hong Kong/China/Human Rights Q. Thank you, Mr. President.").
# Split those so the label starts its own paragraph.
paras <- paras %>%
  mutate(text = str_replace(text, "^([^.?!]{1,100}?|.*——) (?=(?:Q|The President)\\. )", "\\1\n\n")) %>%
  mutate(text = str_split(text, "\n\n")) %>%
  unnest(text)

# ---- Speakers ----------------------------------------------------------------------

# A label is a short run of name-like words ending in ". " at the start of a paragraph.
# Candidates are cast wide, then accepted only if they open with a title or look like a
# personal name, so "Okay." or "Thank you." at the start of an answer is not a label.
HONORIFIC <- "(?:Mr|Mrs|Ms|Dr|Gov|Sen|Rep|Gen|Adm|Lt|Col|Maj|Sgt|Capt|Cmdr|Rev|Prof|Amb|Sec|St|Jr|Sr)\\."
WORD <- str_c("(?:", HONORIFIC, "|(?:[A-Z]\\.){2,}|[A-Z]\\.|[A-Z][\\p{L}'’\\-]*|of|the|de|da|del|di|van|von|der|al|bin|el|la|le|du|member|members|participant|reporter|reporters|speaker|student|students)")
# The lookbehind keeps a label from stopping at a middle initial ("Joseph R. Biden").
label_re <- str_c("^(Q|", WORD, "(?: ", WORD, "){0,7}?(?<! [A-Z]))\\.(?=\\s|$)")

TITLES <- c(
  "The", "President", "Vice", "Prime", "Premier", "Chancellor", "Secretary", "Press",
  "Senator", "Governor", "Representative", "Congressman", "Congresswoman", "Ambassador",
  "Director", "Senior", "Administrator", "Attorney", "Admiral", "General", "King", "Queen",
  "Crown", "Prince", "Princess", "Sheikh", "Emir", "Sultan", "Chairman", "Chairwoman",
  "Chair", "Acting", "Executive", "Staff", "Agent", "Commander", "Watch", "Inspector",
  "Detective", "Trooper", "Corporal", "Private", "Specialist", "Master", "Petty", "Airman",
  "Seaman", "Ensign", "Delegate", "Councilman", "Councilwoman", "Leader", "Speaker", "Majority", "Minority", "Mayor", "Minister", "Foreign",
  "Deputy", "Special", "Assistant", "Adviser", "Advisor", "Commissioner", "Chief",
  "Lieutenant", "Colonel", "Sergeant", "Captain", "Major", "Pastor", "Reverend", "Father",
  "Rabbi", "Bishop", "Archbishop", "Cardinal", "Pope", "Moderator", "Interviewer",
  "Interpreter", "Participant", "Participants", "Audience", "Student", "Students",
  "Questioner", "Reporter", "Reporters", "Unidentified", "First", "Former", "National",
  "Counselor", "Surgeon", "Commandant", "Coach", "Officer", "Sheriff", "Judge", "Justice",
  "Taoiseach", "Host", "Anchor", "Panelist", "Announcer", "Narrator", "Superintendent",
  "Principal", "Dean", "Sister", "Brother", "Imam", "Lady", "Sir", "Dame", "Lord",
  "Mr.", "Mrs.", "Ms.", "Dr.", "Gov.", "Sen.", "Rep.", "Gen.", "Adm.", "Lt.", "Col.",
  "Maj.", "Sgt.", "Capt.", "Cmdr.", "Rev.", "Prof.", "Amb.", "Sec."
)
# Capitalized words that open ordinary sentences and should never be read as names.
NOT_NAMES <- c(
  "Thank", "Thanks", "Good", "God", "Bless", "Merry", "Happy", "Okay", "OK", "Yes", "No",
  "All", "Right", "Well", "Great", "Very", "Absolutely", "Sure", "America", "American",
  "United", "States", "China", "Chinese", "Congratulations", "Welcome", "Hello", "Hi",
  "Exactly", "Correct", "True", "Wow", "Oh", "Fantastic", "Beautiful", "Amazing",
  "Incredible", "Wonderful", "Excellent", "Perfect", "Never", "Nobody", "Everybody",
  "Nothing", "Same", "Me", "Us", "We", "I", "It", "That", "This", "These", "Those", "And",
  "But", "So", "Now", "Then", "Here", "There", "Not", "Of", "Course", "Please", "Sorry",
  "Again", "Today", "Tomorrow", "Yesterday", "New", "Year", "Christmas", "Easter", "Day",
  "Morning", "Afternoon", "Evening", "Night", "Done", "Next", "Last", "Go", "Come", "Let",
  "Look", "See", "Watch", "Big", "Huge", "Tremendous", "Bad", "Sad", "Terrible", "Wrong",
  "Maybe", "Probably", "Definitely", "Certainly", "Totally", "Really", "Too", "Wait",
  "Yeah", "Nope", "Anyway", "Listen", "Quiet", "Both", "Dear", "Hey", "Ladies", "Folks",
  month.name
)

ROLES <- "^(Q|Audience members?|Participants?|Moderator|Interviewer|Interpreter|Students?|Reporters?|Questioner)$"

is_label <- function(lab) {
  words <- str_split(lab, " ")
  first_word <- vapply(words, `[`, "", 1)
  second_word <- vapply(words, function(w) if (length(w) > 1) w[2] else "", "")
  last_word <- vapply(words, function(w) w[length(w)], "")
  titled <- first_word %in% TITLES & (first_word != "The" | second_word %in% TITLES) &
    lengths(words) > 1 # a bare title ("Congressman.") is a vocative, not a label
  name_like <- vapply(words, function(w) {
    length(w) >= 2 && length(w) <= 4 && !any(w %in% NOT_NAMES) &&
      all(str_detect(w, "^([A-Z]|of$|de$|da$|del$|van$|von$|al$|bin$|el$|la$|le$|du$)"))
  }, TRUE)
  contraction <- vapply(words, function(w) any(str_detect(w, "['’](s|re|ve|ll|d|t)$")), TRUE)
  dangling <- str_detect(last_word, str_c("^", str_remove(HONORIFIC, "\\\\.$"), "$")) # "FDA Commissioner Dr" from "Dr. Makary"
  !is.na(lab) & (lab == "Q" | str_detect(lab, ROLES) | ((titled | name_like) & !contraction & !dangling))
}

# "[Secretary Azar continued his remarks, concluding as follows.]" hands the floor to
# Secretary Azar for the paragraphs that follow.
continued_re <- "^\\[(?:At this point, )?(.+?) continued (?:his|her|their) remarks"

# Some spoken documents have titles that do not say so ("Conversation With ..."), so a
# document also counts as spoken if it labels the president or a reporter.
paras <- paras %>%
  mutate(cand = str_match(text, label_re)[, 2]) %>%
  group_by(doc_id) %>%
  mutate(spoken = spoken | (genre != "joint_statement" &
    any(cand %in% c("Q", "The President", str_c("President ", president))))) %>%
  ungroup() %>%
  mutate(
    label = if_else(spoken & is_label(cand), cand, NA_character_),
    note = str_detect(text, "^\\[.*\\]\\.?$"),
    label = coalesce(label, if_else(spoken & note,
                                    str_replace(str_match(text, continued_re)[, 2], "^the President$", "The President"),
                                    NA_character_))
  ) %>%
  select(-cand)

# The president often greets people by name at the start of a paragraph ("Governor Ron
# DeSantis. Thank you very much, Ron."), which reads exactly like a label. Such a
# paragraph goes on to name the person again, which real speakers almost never do, so a
# named label whose paragraph repeats one of its names is not a label. The rest are
# believed if they speak more than once or the president visibly takes the floor back
# later; generic roles ("Q", "Audience member") are always believed.
names_in <- function(label) {
  w <- str_split(label, " ")[[1]]
  w[!w %in% TITLES & str_detect(w, "^[A-Z][a-z]{2,}")]
}
repeats_name <- function(label, text) {
  mapply(function(l, t) {
    if (is.na(l)) return(FALSE)
    nm <- names_in(l)
    rest <- str_trim(str_sub(t, str_length(l) + 2))
    length(nm) > 0 && any(str_detect(rest, str_c("\\b", nm, "\\b"))) &&
      !str_detect(rest, "President|My name|I'm |I am ")
  }, label, text, USE.NAMES = FALSE)
}
pres_label_re <- function(president) str_c("^(The President|President (.+ )?", president, ")$")
paras <- paras %>%
  group_by(doc_id) %>%
  mutate(
    lab_pres = coalesce(str_detect(label, pres_label_re(first(president))), FALSE),
    later_pres = rev(cumsum(rev(lab_pres))) - lab_pres > 0,
    lab_n = if_else(is.na(label), 0L, as.integer(table(label)[label])),
    false_greeting = !is.na(label) & !lab_pres & !str_detect(label, ROLES) & !note &
      repeats_name(label, text),
    label = if_else(false_greeting | (!is.na(label) & !lab_pres & !str_detect(label, ROLES) &
                                        !note & lab_n < 2 & !later_pres), NA_character_, label)
  ) %>%
  ungroup() %>%
  select(-lab_pres, -later_pres, -lab_n, -false_greeting) %>%
  mutate(
    text = if_else(!is.na(label) & !note, str_squish(str_sub(text, str_length(label) + 2)), text),
    # GPO's topic headings in news conferences ("China-U.S. Trade") have no end punctuation.
    heading = spoken & is.na(label) & !note & str_length(text) < 80 &
      !str_detect(text, "[.?!:;,\"”’')\\]—–-]$")
  )

paras <- paras %>%
  group_by(doc_id) %>%
  mutate(
    section = if_else(heading, text, NA_character_),
    speaker = case_when(
      genre == "joint_statement" ~ "Joint",
      !spoken ~ "The President",
      TRUE ~ label
    )
  ) %>%
  fill(section, speaker, .direction = "down") %>%
  ungroup() %>%
  mutate(speaker = coalesce(speaker, "The President")) %>% # unlabeled opening remarks
  filter(!heading, !note, text != "") %>%
  mutate(
    # Debates and some joint appearances label the president by name.
    is_president = str_detect(speaker, pres_label_re(president))
  ) %>%
  group_by(doc_id) %>%
  mutate(
    para_id = row_number(),
    turn_id = cumsum(speaker != lag(speaker, default = ""))
  ) %>%
  ungroup()

# ---- China mentions ----------------------------------------------------------------

# CHINA_CORE and CHINA_PERIPH are defined in config.R, shared with the briefings.

paras <- paras %>%
  mutate(
    china_core = str_detect(text, CHINA_CORE),
    china_any = china_core | str_detect(text, CHINA_PERIPH)
  )

# ---- Outputs -----------------------------------------------------------------------

para_out <- paras %>%
  select(doc_id, para_id, para_src, turn_id, speaker, label, is_president, section,
         china_core, china_any, text) %>%
  mutate(n_chars = str_length(text), .before = text)

doc_out <- docs %>%
  filter(genre != "administrative") %>%
  select(doc_id, collection, date, president, title, genre, category, location, url) %>%
  inner_join(
    paras %>%
      group_by(doc_id) %>%
      summarise(
        spoken = first(spoken),
        n_paras = n(),
        n_pres_paras = sum(is_president),
        n_pres_china_core = sum(is_president & china_core),
        n_pres_china_any = sum(is_president & china_any),
        has_qa = any(speaker == "Q"),
        n_speakers = n_distinct(speaker),
        text_president = str_c(text[is_president], collapse = "\n\n"),
        .groups = "drop"
      ),
    by = "doc_id"
  ) %>%
  mutate(pres_chars = str_length(text_president))

# The same document can appear in both WCPD and DCPD around the January 2009 switch.
n_before <- nrow(doc_out)
doc_out <- doc_out %>%
  arrange(desc(collection == "DCPD")) %>%
  distinct(date, title, .keep_all = TRUE) %>%
  arrange(date, doc_id)
para_out <- semi_join(para_out, doc_out, by = "doc_id")

write_csv(para_out, file.path(CLEAN_DIR, "01a_presdocs_paragraphs.csv"))
write_csv(doc_out, file.path(CLEAN_DIR, "01a_presdocs_docs.csv"))

message(sprintf(
  "%d raw documents -> %d kept (%d administrative dropped, %d cross-collection duplicates)",
  nrow(docs), nrow(doc_out), sum(docs$genre == "administrative"), n_before - nrow(doc_out)
))
message(sprintf(
  "%d paragraphs, %d by the president (%d mention China, %d with peripheral terms)",
  nrow(para_out), sum(para_out$is_president),
  sum(para_out$is_president & para_out$china_core), sum(para_out$is_president & para_out$china_any)
))
message(sprintf(
  "%d documents with no president paragraph mentioning China or periphery terms",
  sum(doc_out$n_pres_china_any == 0)
))
