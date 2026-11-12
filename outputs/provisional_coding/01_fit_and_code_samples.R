suppressPackageStartupMessages({
  library(dplyr)
  library(e1071)
  library(readxl)
  library(writexl)
})

set.seed(20261101)

data_dir <- Sys.getenv("HONORS_DATA_DIR", "../honors-thesis-data")
sample_dir <- file.path(data_dir, "clean", "04_sample_data")
output_dir <- file.path(sample_dir, "provisional")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

files <- c(
  briefings = "04_sample_briefings.xlsx",
  mfa = "04_sample_mfa.xlsx",
  presdocs = "04_sample_presdocs.xlsx"
)

books <- lapply(files, function(f) {
  path <- file.path(sample_dir, f)
  list(
    sample = read_excel(path, sheet = "sample"),
    codebook = read_excel(path, sheet = "codebook"),
    rules = read_excel(path, sheet = "rules")
  )
})

blank <- function(x) is.na(x) | trimws(as.character(x)) == ""

# Resolve the fourteen MFA rows that had about_target=no but a populated stance. These
# decisions follow the workbook rule that question/context may resolve the referent, but
# the stance itself must be expressed in the answer.
mfa_fixes <- tibble::tribble(
  ~sample_id, ~about_target, ~stance,   ~note,
  "M001",     "yes",         "neutral", NA_character_,
  "M005",     "no",          NA,        NA_character_,
  "M007",     "yes",         "neg",     "Target inferred from the question and the answer's reference to sanctions, coercion, and interference; review.",
  "M011",     "yes",         "neutral", NA_character_,
  "M013",     "yes",         "neg",     "Target inferred from the question and the answer's reference to external forces; review.",
  "M024",     "yes",         "neg",     NA_character_,
  "M028",     "yes",         "neg",     NA_character_,
  "M034",     "no",          NA,        NA_character_,
  "M054",     "yes",         "pos",     NA_character_,
  "M055",     "yes",         "neg",     NA_character_,
  "M058",     "no",          NA,        NA_character_,
  "M059",     "yes",         "neutral", NA_character_,
  "M070",     "yes",         "neutral", "Target inferred from the question; the answer states a general position without evaluation; review.",
  "M081",     "yes",         "neg",     "Negative target reference is implicit in unilateralism and protectionism; review."
)

mfa <- books$mfa$sample
mfa$notes <- as.character(mfa$notes)
for (i in seq_len(nrow(mfa_fixes))) {
  j <- match(mfa_fixes$sample_id[i], mfa$sample_id)
  stopifnot(!is.na(j))
  mfa$about_target[j] <- mfa_fixes$about_target[i]
  mfa$stance[j] <- mfa_fixes$stance[i]
  if (!is.na(mfa_fixes$note[i])) mfa$notes[j] <- mfa_fixes$note[i]
}
books$mfa$sample <- mfa

rows <- bind_rows(lapply(names(books), function(source) {
  d <- books[[source]]$sample
  d$notes <- as.character(d$notes)
  auxiliary <- if (source == "mfa") {
    coalesce(as.character(d$question), "")
  } else if (source == "briefings") {
    paste(coalesce(as.character(d$question), ""), coalesce(as.character(d$context), ""))
  } else {
    coalesce(as.character(d$context), "")
  }
  tibble(
    source = source,
    row = seq_len(nrow(d)),
    sample_id = d$sample_id,
    side = if_else(source == "mfa", "mfa", "us"),
    text = coalesce(as.character(d$text), ""),
    auxiliary = auxiliary,
    about_target = as.character(d$about_target),
    stance = as.character(d$stance),
    originally_blank = blank(d$about_target)
  )
}))

tokenize <- function(x) {
  words <- regmatches(tolower(x), gregexpr("[a-z]+(?:'[a-z]+)?", tolower(x), perl = TRUE))[[1]]
  if (length(words) == 1L && words[1] == "") words <- character()
  words <- words[nchar(words) > 1L]
  if (length(words) < 2L) return(words)
  c(words, paste0(head(words, -1L), "__", tail(words, -1L)))
}

make_features <- function(texts, max_terms = 2500L) {
  toks <- lapply(texts, tokenize)
  df <- sort(table(unlist(lapply(toks, unique))), decreasing = TRUE)
  vocab <- names(df[df >= 2L])
  if (length(vocab) > max_terms) vocab <- vocab[seq_len(max_terms)]
  x <- matrix(0, nrow = length(texts), ncol = length(vocab), dimnames = list(NULL, vocab))
  for (i in seq_along(toks)) {
    counts <- table(toks[[i]])
    keep <- intersect(names(counts), vocab)
    if (length(keep)) x[i, keep] <- log1p(as.numeric(counts[keep]))
  }
  idf <- log((nrow(x) + 1) / (colSums(x > 0) + 1)) + 1
  x <- sweep(x, 2, idf, "*")
  norms <- sqrt(rowSums(x^2))
  norms[norms == 0] <- 1
  sweep(x, 1, norms, "/")
}

macro_f1 <- function(truth, pred) {
  lv <- union(unique(as.character(truth)), unique(as.character(pred)))
  mean(vapply(lv, function(k) {
    tp <- sum(truth == k & pred == k)
    fp <- sum(truth != k & pred == k)
    fn <- sum(truth == k & pred != k)
    if (tp == 0) return(0)
    2 * tp / (2 * tp + fp + fn)
  }, numeric(1)))
}

stratified_folds <- function(y, k = 5L) {
  folds <- integer(length(y))
  for (lev in unique(y)) {
    idx <- which(y == lev)
    folds[idx] <- sample(rep(seq_len(k), length.out = length(idx)))
  }
  folds
}

fit_predict <- function(x, y, train, predict_rows, task, side) {
  y_train <- factor(y[train])
  weights <- as.numeric(length(y_train) / (length(levels(y_train)) * table(y_train)))
  names(weights) <- names(table(y_train))
  costs <- c(0.5, 1, 2)
  folds <- stratified_folds(y_train)
  svm_cv <- lapply(costs, function(cost) {
    pred <- rep(NA_character_, length(y_train))
    for (fold in sort(unique(folds))) {
      tr <- which(folds != fold)
      te <- which(folds == fold)
      w <- as.numeric(length(tr) / (length(levels(y_train)) * table(droplevels(y_train[tr]))))
      names(w) <- names(table(droplevels(y_train[tr])))
      fit <- svm(
        x = x[train[tr], , drop = FALSE], y = droplevels(y_train[tr]),
        kernel = "linear", cost = cost, class.weights = w, scale = FALSE
      )
      pred[te] <- as.character(predict(fit, x[train[te], , drop = FALSE]))
    }
    tibble(method = "svm", parameter = cost, accuracy = mean(pred == y_train), macro_f1 = macro_f1(y_train, pred))
  }) %>% bind_rows()

  balanced_knn <- function(train_x, train_y, test_x, k) {
    lev <- levels(train_y)
    sim <- test_x %*% t(train_x)
    scores <- matrix(0, nrow(test_x), length(lev), dimnames = list(NULL, lev))
    for (j in seq_along(lev)) {
      class_cols <- which(train_y == lev[j])
      for (i in seq_len(nrow(test_x))) {
        s <- sort(sim[i, class_cols], decreasing = TRUE)
        scores[i, j] <- mean(head(s, min(k, length(s))))
      }
    }
    # Convert class-balanced similarity scores to review-oriented probabilities.
    exp_scores <- exp(12 * sweep(scores, 1, apply(scores, 1, max), "-"))
    probs <- exp_scores / rowSums(exp_scores)
    label <- lev[max.col(scores, ties.method = "first")]
    confidence <- probs[cbind(seq_len(nrow(probs)), match(label, lev))]
    list(label = label, confidence = confidence)
  }

  k_values <- c(1L, 3L, 5L, 7L)
  knn_cv <- lapply(k_values, function(k) {
    pred <- rep(NA_character_, length(y_train))
    for (fold in sort(unique(folds))) {
      tr <- which(folds != fold)
      te <- which(folds == fold)
      pred[te] <- balanced_knn(
        x[train[tr], , drop = FALSE], droplevels(y_train[tr]),
        x[train[te], , drop = FALSE], k
      )$label
    }
    tibble(method = "knn", parameter = k, accuracy = mean(pred == y_train), macro_f1 = macro_f1(y_train, pred))
  }) %>% bind_rows()

  cv <- bind_rows(svm_cv, knn_cv) %>% arrange(desc(macro_f1), desc(accuracy))
  best <- cv[1, ]
  if (best$method == "svm") {
    fit <- svm(
      x = x[train, , drop = FALSE], y = y_train, kernel = "linear", cost = best$parameter,
      class.weights = weights, probability = TRUE, scale = FALSE
    )
    pred <- predict(fit, x[predict_rows, , drop = FALSE], probability = TRUE)
    probs <- attr(pred, "probabilities")
    label <- as.character(pred)
    confidence <- probs[cbind(seq_len(nrow(probs)), match(label, colnames(probs)))]
  } else {
    pred <- balanced_knn(x[train, , drop = FALSE], y_train, x[predict_rows, , drop = FALSE], as.integer(best$parameter))
    label <- pred$label
    confidence <- pred$confidence
  }
  list(
    label = label, confidence = confidence,
    diagnostics = mutate(cv, task = task, side = side,
                         selected = method == best$method & parameter == best$parameter, .before = 1)
  )
}

diagnostics <- list()
rows$rel_conf <- NA_real_
rows$stance_conf <- NA_real_
for (side_name in c("us", "mfa")) {
  idx <- which(rows$side == side_name)

  # Relevance may use question/context only to resolve what the answer or paragraph refers to.
  rel_text <- paste(rows$text[idx], "contextref", rows$auxiliary[idx])
  rel_x <- make_features(rel_text)
  rel_train <- which(!blank(rows$about_target[idx]))
  rel_predict <- which(rows$originally_blank[idx])
  rel <- fit_predict(rel_x, rows$about_target[idx], rel_train, rel_predict, "about_target", side_name)
  diagnostics[[length(diagnostics) + 1L]] <- rel$diagnostics
  rel_global <- idx[rel_predict]
  rows$about_target[rel_global] <- rel$label
  rows$rel_conf[rel_global] <- rel$confidence

  # Stance is learned and predicted from the coded text only.
  stance_x <- make_features(rows$text[idx])
  stance_train <- which(rows$about_target[idx] == "yes" & !blank(rows$stance[idx]) & !rows$originally_blank[idx])
  stance_predict <- which(rows$originally_blank[idx] & rows$about_target[idx] == "yes")
  stance <- fit_predict(stance_x, rows$stance[idx], stance_train, stance_predict, "stance", side_name)
  diagnostics[[length(diagnostics) + 1L]] <- stance$diagnostics
  stance_global <- idx[stance_predict]
  rows$stance[stance_global] <- stance$label
  rows$stance_conf[stance_global] <- stance$confidence
  rows$stance[idx[rows$originally_blank[idx] & rows$about_target[idx] == "no"]] <- NA_character_
}

# Attach concise review flags only to provisional rows whose relevance or stance is uncertain.
for (source in names(books)) {
  d <- books[[source]]$sample
  d$notes <- as.character(d$notes)
  r <- filter(rows, source == !!source)
  stopifnot(identical(d$sample_id, r$sample_id))
  fill <- r$originally_blank
  d$about_target[fill] <- r$about_target[fill]
  d$stance[fill] <- r$stance[fill]
  for (i in which(fill)) {
    flags <- character()
    if (!is.na(r$rel_conf[i]) && r$rel_conf[i] < 0.65) {
      flags <- c(flags, sprintf("relevance p=%.2f", r$rel_conf[i]))
    }
    if (r$about_target[i] == "yes" && !is.na(r$stance_conf[i]) && r$stance_conf[i] < 0.55) {
      flags <- c(flags, sprintf("stance p=%.2f", r$stance_conf[i]))
    }
    if (length(flags)) d$notes[i] <- paste0("Low-confidence provisional label (", paste(flags, collapse = "; "), "); review.")
  }
  books[[source]]$sample <- d
}

# Replace the statistical first pass with the completed row-level review decisions.
# Require an exact one-to-one match to every row that was blank in the source files.
overrides <- read.csv(
  file.path("outputs", "provisional_coding", "manual_overrides.csv"),
  na.strings = c("", "NA"), stringsAsFactors = FALSE
)
stopifnot(!anyDuplicated(paste(overrides$source, overrides$sample_id, sep = "::")))
stopifnot(all(overrides$source %in% names(books)))
stopifnot(all(overrides$about_target %in% c("yes", "no")))
stopifnot(all(overrides$stance[overrides$about_target == "yes"] %in% c("neg", "pos", "mixed", "neutral")))
stopifnot(all(blank(overrides$stance[overrides$about_target == "no"])))

expected_overrides <- bind_rows(lapply(names(books), function(source) {
  original <- read_excel(file.path(sample_dir, files[[source]]), sheet = "sample")
  tibble(
    source = source,
    sample_id = original$sample_id[blank(original$about_target)]
  )
}))
expected_keys <- paste(expected_overrides$source, expected_overrides$sample_id, sep = "::")
override_keys <- paste(overrides$source, overrides$sample_id, sep = "::")
stopifnot(setequal(expected_keys, override_keys))

for (source in names(books)) {
  d <- books[[source]]$sample
  o <- overrides[overrides$source == source, , drop = FALSE]
  j <- match(o$sample_id, d$sample_id)
  stopifnot(!anyNA(j))
  d$about_target[j] <- o$about_target
  d$stance[j] <- o$stance
  d$notes[j] <- o$note
  books[[source]]$sample <- d
}

# Validate the codebook invariants and confirm non-coding fields are unchanged.
for (source in names(books)) {
  original <- read_excel(file.path(sample_dir, files[[source]]), sheet = "sample")
  coded <- books[[source]]$sample
  stopifnot(identical(names(original), names(coded)))
  fixed_cols <- c("about_target", "stance", "notes")
  stopifnot(identical(original[setdiff(names(original), fixed_cols)], coded[setdiff(names(coded), fixed_cols)]))
  stopifnot(!any(blank(coded$about_target)))
  stopifnot(all(coded$about_target %in% c("yes", "no")))
  stopifnot(all(coded$stance[coded$about_target == "yes"] %in% c("neg", "pos", "mixed", "neutral")))
  stopifnot(all(blank(coded$stance[coded$about_target == "no"])))

  write_xlsx(
    list(sample = coded, codebook = books[[source]]$codebook, rules = books[[source]]$rules),
    file.path(output_dir, files[[source]])
  )
}

diagnostics <- bind_rows(diagnostics)
write.csv(diagnostics, file.path("outputs", "provisional_coding", "model_diagnostics.csv"), row.names = FALSE)

summary <- bind_rows(lapply(names(books), function(source) {
  d <- books[[source]]$sample
  tibble(
    source = source,
    total_rows = nrow(d),
    provisional_rows = sum(rows$source == source & rows$originally_blank),
    about_yes = sum(d$about_target == "yes"),
    about_no = sum(d$about_target == "no"),
    neg = sum(d$stance == "neg", na.rm = TRUE),
    mixed = sum(d$stance == "mixed", na.rm = TRUE),
    neutral = sum(d$stance == "neutral", na.rm = TRUE),
    pos = sum(d$stance == "pos", na.rm = TRUE),
    review_flags = sum(!blank(d$notes))
  )
}))
write.csv(summary, file.path("outputs", "provisional_coding", "coding_summary.csv"), row.names = FALSE)
print(summary)
print(filter(diagnostics, selected))
