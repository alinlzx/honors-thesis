"""Shared relevance step for specs B and D: is the passage about the target country?

In:  build/01_units.csv, build/01_labels.csv
Out: build/02_relevance_oof.csv     held-out P(about) for labeled rows
     build/02_relevance_scores.csv  final model's P(about) for all frame units

The model reads the passage with its question or preceding paragraph, because the codebook
lets context settle what a passage refers to. Passing a threshold is left to the evaluation
and the series, so this step only writes probabilities.
"""
import pandas as pd

from sentiment_common import (
    BUILD_DIR, N_FOLDS, RELEVANCE_CLASSES, fit_nli, load_labels, load_units, predict_nli,
    relevance_hypotheses, relevance_premise, release,
)


def inputs(d: pd.DataFrame):
    premises = [relevance_premise(t, a) for t, a in zip(d["text"], d["aux"])]
    hypotheses = [relevance_hypotheses(s) for s in d["source"]]
    return premises, hypotheses


def fit(train: pd.DataFrame, name: str):
    premises, hypotheses = inputs(train)
    y = [RELEVANCE_CLASSES.index(v) for v in train["about_target"]]
    return fit_nli(premises, hypotheses, y, log_prefix=name)


labels = load_labels()
OOF_PATH = BUILD_DIR / "02_relevance_oof.csv"
# Finished folds are kept, so an interrupted run resumes. Delete the file to start over.
done = pd.read_csv(OOF_PATH) if OOF_PATH.exists() else pd.DataFrame(columns=["sample_id", "p_about"])
for fold in range(1, N_FOLDS + 1):
    held_out = labels["fold"] == fold
    if labels.loc[held_out, "sample_id"].isin(done["sample_id"]).all():
        continue
    model, tokenizer = fit(labels[~held_out], f"fold {fold}")
    p = predict_nli(model, tokenizer, *inputs(labels[held_out]))
    new = pd.DataFrame({"sample_id": labels.loc[held_out, "sample_id"], "p_about": p[:, 1]})
    done = pd.concat([done, new]).sort_values("sample_id")
    done.to_csv(OOF_PATH, index=False)
    release(model)
assert len(done) == len(labels)

model, tokenizer = fit(labels, "final")
units = load_units()
p = predict_nli(model, tokenizer, *inputs(units), log_prefix="scoring")
units[["unit_id", "source"]].assign(p_about=p[:, 1]).to_csv(BUILD_DIR / "02_relevance_scores.csv", index=False)
print(f"Scored {len(units)} units.")
