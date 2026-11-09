# Take composition out of the stance scores. A month's mean can move because of who spoke, or
# in what format, rather than because the government's posture changed. This step estimates
# those effects and writes an adjusted score next to spec D's.
#
# What counts as composition, by corpus:
#   MFA        spokesperson: one per press conference, several rotating within a month
#   President  genre: news conference, exchange, remarks, address, written, ...
#   Briefings  role: press secretary, other official, anonymous official
#
# In:  build/01_units.csv, build/02_relevance_scores.csv, build/05_spec_d_scores.csv,
#      clean/02_mfa_qa.csv (spokesperson)
# Out: build/06_adjusted_scores.csv  unit_id, source, speaker, net (spec D), net_adj
#      build/06_speaker_effects.csv  each speaker's estimated effect, with its passages
#
# Choices, and why:
# - Effects come from net ~ speaker + month fixed effects, fit within each corpus on the
#   passages the relevance filter keeps (the series population). The month fixed effects mean
#   a speaker's effect is identified only from rotation within months. Without them it would
#   absorb the era the speaker served in: Zhao Lijian's tenure coincided with the most hostile
#   period, and that hostility is real posture, not his personal style.
# - Only the speaker effects are subtracted; the month variation stays in. Effects are centred
#   on their passage-weighted mean, so the adjustment doesn't move the overall level.
# - Speakers with fewer than 30 kept passages are pooled as "other", so no effect rests on a
#   handful of passages. That pools the 30 MFA answers with no recorded spokesperson and the
#   presidential debates.
# - Every unit gets net_adj, including ones the filter drops, so the cut can still vary later.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})
source("config.R")

FILTER_CUT <- 0.2   # as in the analysis scripts
MIN_PASSAGES <- 30

read_build <- function(f) read_csv(file.path(BUILD_DIR, f), show_col_types = FALSE,
                                   col_types = cols(unit_id = col_character()))

spokesperson <- read_csv(file.path(CLEAN_DIR, "02_mfa_qa.csv"), show_col_types = FALSE) %>%
  transmute(unit_id = as.character(id), spokesperson)

units <- read_build("01_units.csv") %>%
  select(unit_id, source, date, genre) %>%
  left_join(spokesperson, by = "unit_id") %>%
  mutate(speaker = if_else(source == "mfa", spokesperson, genre),
         speaker = coalesce(speaker, "unknown"),
         month = format(as.Date(date), "%Y-%m")) %>%
  inner_join(select(read_build("05_spec_d_scores.csv"), unit_id, source, net), by = c("unit_id", "source")) %>%
  inner_join(select(read_build("02_relevance_scores.csv"), unit_id, source, p_about), by = c("unit_id", "source")) %>%
  mutate(kept = p_about > FILTER_CUT)
stopifnot(nrow(units) == nrow(read_build("01_units.csv")))

adjust <- function(d) {
  sizes <- count(filter(d, kept), speaker)
  small <- sizes$speaker[sizes$n < MIN_PASSAGES]
  d <- mutate(d, speaker = if_else(speaker %in% small | !speaker %in% sizes$speaker, "other", speaker))

  kept <- filter(d, kept)
  # The most common speaker is the reference level, so the other effects are measured
  # against a well-estimated baseline.
  levels <- names(sort(table(kept$speaker), decreasing = TRUE))
  kept$speaker <- factor(kept$speaker, levels)
  fit <- lm(net ~ speaker + factor(month), data = kept)
  without <- lm(net ~ factor(month), data = kept)
  joint <- anova(without, fit)

  est <- coef(summary(fit))
  effects <- tibble(speaker = levels) %>%
    mutate(term = paste0("speaker", speaker),
           raw = if_else(term %in% rownames(est), est[match(term, rownames(est)), "Estimate"], 0),
           se = if_else(term %in% rownames(est), est[match(term, rownames(est)), "Std. Error"], NA_real_)) %>%
    left_join(count(kept, speaker = as.character(speaker), name = "passages"), by = "speaker")
  centre <- weighted.mean(effects$raw, effects$passages)
  effects <- effects %>%
    mutate(effect = raw - centre,
           # Share of within-month variance the speakers explain, and whether they matter jointly.
           partial_r2 = (deviance(without) - deviance(fit)) / deviance(without),
           joint_f = joint$F[2], joint_p = joint$`Pr(>F)`[2]) %>%
    select(speaker, passages, effect, se, partial_r2, joint_f, joint_p)

  scores <- d %>%
    left_join(select(effects, speaker, effect), by = "speaker") %>%
    transmute(unit_id, source, speaker, net, net_adj = net - effect)
  list(scores = scores, effects = mutate(effects, source = d$source[1], .before = 1))
}

results <- lapply(split(units, units$source), adjust)
scores <- bind_rows(lapply(results, `[[`, "scores"))
effects <- bind_rows(lapply(results, `[[`, "effects"))
stopifnot(nrow(scores) == nrow(units), !anyNA(scores$net_adj))

write_csv(scores, file.path(BUILD_DIR, "06_adjusted_scores.csv"))
write_csv(effects, file.path(BUILD_DIR, "06_speaker_effects.csv"))

print(as.data.frame(mutate(effects, across(where(is.numeric), ~ signif(.x, 3)))))
