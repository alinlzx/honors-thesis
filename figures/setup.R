# Shared paths, plot theme and data loaders for the exhibit scripts.
#
# Run exhibit scripts from the repo root, e.g. `Rscript figures/06_sentiment_stats.R`.
# Inputs come from honors-thesis-original-data/sentiments/ (written by sentiments/0X_*.R);
# exhibits are written to figures/output/.

source(if (file.exists("sentiments/functions.R")) "sentiments/functions.R" else "../sentiments/functions.R")
suppressPackageStartupMessages(library(ggplot2))

FIG_DIR <- file.path(REPO_ROOT, "figures", "output")
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)
fig_path <- function(name) file.path(FIG_DIR, name)

APPROACHES <- c("01" = "Approach 1: positive and negative only",
                "02" = "Approach 2: all three classes",
                "03" = "Approach 3: two binary models")
APPROACH_SHORT <- c("01" = "Approach 1", "02" = "Approach 2", "03" = "Approach 3")
CLASS_LABELS <- c(N = "Negative", O = "Ambiguous", P = "Positive")
CLASS_COLORS <- c(Negative = "#B2182B", Ambiguous = "#8C8C8C", Positive = "#2166AC")
CLASS_LINETYPES <- c(Negative = "solid", Ambiguous = "dotted", Positive = "dashed")

theme_paper <- function(base_size = 9) {
  theme_bw(base_size = base_size, base_family = "serif") +
    theme(panel.grid.minor = element_blank(),
          strip.background = element_blank(),
          strip.text = element_text(face = "bold", size = base_size),
          legend.position = "bottom",
          legend.title = element_blank(),
          legend.key.width = unit(1.6, "lines"))
}

# Evaluation sets behind each approach's metrics, as used in sentiments/0X_*.R:
# approach 1 scores its three-class statistics on the P/N test split plus held-out
# ambiguous documents; approaches 2 and 3 use their test split directly.
read_eval_sets <- function() {
  bind_rows(lapply(names(APPROACHES), function(a) {
    preds <- read_csv(out_path(paste0(a, "_test_predictions.csv")), show_col_types = FALSE)
    three_class_set <- if (a == "01") "test split + held-out O, re-vectorized" else "test split"
    # Round away floating-point noise from the CSV round trip, so documents with
    # identical SVM, RF and Bing scores stay tied (as when 0X_metrics.csv was computed).
    preds %>% filter(eval_set == three_class_set) %>% mutate(approach = a, hybrid = round(hybrid, 10))
  }))
}
