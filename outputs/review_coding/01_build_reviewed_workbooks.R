suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(writexl)
})

data_dir <- Sys.getenv("HONORS_DATA_DIR", "../honors-thesis-data")
input_dir <- file.path(data_dir, "clean", "04_sample_data", "provisional")
output_dir <- file.path(data_dir, "clean", "04_sample_data", "reviewed")
log_dir <- file.path("outputs", "review_coding")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

files <- c(
  briefings = "04_sample_briefings.xlsx",
  mfa = "04_sample_mfa.xlsx",
  presdocs = "04_sample_presdocs.xlsx"
)

blank <- function(x) is.na(x) | trimws(as.character(x)) == ""
norm <- function(x) ifelse(is.na(x), "", as.character(x))

summary_rows <- list()
transition_rows <- list()

for (source in names(files)) {
  input_path <- file.path(input_dir, files[[source]])
  log_path <- file.path(log_dir, sub("[.]xlsx$", "_review_log.csv", files[[source]]))
  output_path <- file.path(
    output_dir,
    sub("[.]xlsx$", "_reviewed.xlsx", files[[source]])
  )

  sample <- read_excel(input_path, sheet = "sample")
  codebook <- read_excel(input_path, sheet = "codebook")
  rules <- read_excel(input_path, sheet = "rules")
  review <- read.csv(log_path, na.strings = c("", "NA"), stringsAsFactors = FALSE)

  stopifnot(nrow(review) == nrow(sample))
  stopifnot(!anyDuplicated(review$sample_id))
  stopifnot(identical(review$sample_id, sample$sample_id))
  stopifnot(identical(norm(review$original_about_target), norm(sample$about_target)))
  stopifnot(identical(norm(review$original_stance), norm(sample$stance)))
  stopifnot(all(review$status %in% c("agree", "change", "ambiguous")))
  stopifnot(all(review$reviewer_about_target %in% c("yes", "no")))
  stopifnot(all(review$reviewer_stance[review$reviewer_about_target == "yes"] %in%
                  c("neg", "pos", "mixed", "neutral")))
  stopifnot(all(blank(review$reviewer_stance[review$reviewer_about_target == "no"])))
  stopifnot(all(
    norm(review$reviewer_about_target[review$status == "ambiguous"]) ==
      norm(review$original_about_target[review$status == "ambiguous"])
  ))
  stopifnot(all(
    norm(review$reviewer_stance[review$status == "ambiguous"]) ==
      norm(review$original_stance[review$status == "ambiguous"])
  ))
  changed_label <-
    norm(review$reviewer_about_target) != norm(review$original_about_target) |
    norm(review$reviewer_stance) != norm(review$original_stance)
  stopifnot(all(changed_label[review$status == "change"]))

  reviewed <- sample
  reviewed$notes <- as.character(reviewed$notes)
  change <- review$status == "change"
  ambiguous <- review$status == "ambiguous"
  reviewed$about_target[change] <- review$reviewer_about_target[change]
  reviewed$stance[change] <- review$reviewer_stance[change]

  for (i in which(ambiguous)) {
    flag <- paste0("Second-pass Luna review: ambiguous — ", review$rationale[i])
    reviewed$notes[i] <- if (blank(reviewed$notes[i])) {
      flag
    } else {
      paste(reviewed$notes[i], flag, sep = " | ")
    }
  }

  reviewed$status <- review$status
  reviewed <- reviewed %>%
    relocate(status, .before = notes)
  if (!"status" %in% codebook$column) {
    codebook <- bind_rows(
      codebook,
      tibble(
        column = "status",
        value = "agree / change / ambiguous",
        meaning = paste(
          "Result of the label-aware Luna review:",
          "agreement, a confident applied change, or an ambiguity retained for human adjudication."
        )
      )
    )
  }

  stopifnot(all(reviewed$about_target %in% c("yes", "no")))
  stopifnot(all(reviewed$stance[reviewed$about_target == "yes"] %in%
                  c("neg", "pos", "mixed", "neutral")))
  stopifnot(all(blank(reviewed$stance[reviewed$about_target == "no"])))
  fixed_cols <- c("about_target", "stance", "notes")
  unchanged_cols <- setdiff(names(sample), fixed_cols)
  stopifnot(identical(sample[unchanged_cols], reviewed[unchanged_cols]))
  stopifnot(identical(reviewed$status, review$status))

  write_xlsx(
    list(sample = reviewed, codebook = codebook, rules = rules),
    output_path
  )
  file.copy(log_path, file.path(output_dir, basename(log_path)), overwrite = TRUE)

  summary_rows[[source]] <- tibble(
    source = source,
    rows = nrow(review),
    agree = sum(review$status == "agree"),
    change = sum(change),
    ambiguous = sum(ambiguous)
  )
  transition_rows[[source]] <- review %>%
    filter(status == "change") %>%
    transmute(
      source = source,
      transition = paste0(
        original_about_target, "/", ifelse(is.na(original_stance), "blank", original_stance),
        " -> ", reviewer_about_target, "/",
        ifelse(is.na(reviewer_stance), "blank", reviewer_stance)
      )
    ) %>%
    count(source, transition, name = "rows")
}

summary <- bind_rows(summary_rows)
transitions <- bind_rows(transition_rows)
write.csv(summary, file.path(log_dir, "review_summary.csv"), row.names = FALSE)
write.csv(transitions, file.path(log_dir, "review_transitions.csv"), row.names = FALSE)
print(summary)
print(transitions)
