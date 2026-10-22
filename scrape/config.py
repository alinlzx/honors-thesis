"""Shared paths and settings for the Python side of the pipeline."""
import os
from pathlib import Path

from dotenv import load_dotenv

REPO_DIR = Path(__file__).resolve().parent.parent
load_dotenv(REPO_DIR / ".env")

# Raw data lives outside the repo; override with HONORS_DATA_DIR.
DATA_DIR = Path(os.environ.get("HONORS_DATA_DIR", REPO_DIR.parent / "honors-thesis-data")).resolve()
# Each code folder writes to the data folder of the same name, except scrape/ -> raw/.
RAW_DIR = DATA_DIR / "raw"
CLEAN_DIR = DATA_DIR / "clean"
BUILD_DIR = DATA_DIR / "build"
ANALYSIS_DIR = DATA_DIR / "analysis"

# Free key from https://api.data.gov/signup/. DEMO_KEY allows ~10 requests/hour.
GOVINFO_API_KEY = os.environ.get("GOVINFO_API_KEY", "DEMO_KEY")
