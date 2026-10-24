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

# China terms, shared by every US-side cleaning script. Core terms name the PRC, its
# leaders or its government. Peripheral terms (Taiwan, Hong Kong, Tibet, Xinjiang) were
# in the scrape queries too; whether they count is a build/ decision. Case-sensitive so
# "china" (porcelain) does not match.
CHINA_CORE <- "\\b(China|Chinese|PRC|Beijing|Sino-|Xi|Xi Jinping|Hu Jintao|Jiang Zemin|Wen Jiabao|Li Keqiang|Li Qiang|CCP|Huawei|TikTok|ZTE|Wuhan)\\b"
CHINA_PERIPH <- "\\b(Taiwan|Taiwanese|Taipei|Hong Kong|Tibet|Tibetan|Xinjiang|Uyghurs?|Uighurs?|Dalai Lama|Macau|Macao)\\b"
