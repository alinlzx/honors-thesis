# Shared paths for the R side of the pipeline (the R twin of scrape/config.py).
# Run scripts from the repo root, e.g. `Rscript clean/01a_clean_presdocs.R`.

if (file.exists(".env")) readRenviron(".env")

# Raw data lives outside the repo; override with HONORS_DATA_DIR.
DATA_DIR <- normalizePath(Sys.getenv("HONORS_DATA_DIR", "../honors-thesis-data"), mustWork = TRUE)
# Each code folder writes to the data folder of the same name, except scrape/ -> raw/.
RAW_DIR <- file.path(DATA_DIR, "raw")
CLEAN_DIR <- file.path(DATA_DIR, "clean")
BUILD_DIR <- file.path(DATA_DIR, "build")
ANALYSIS_DIR <- file.path(DATA_DIR, "analysis")
