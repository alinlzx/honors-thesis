"""Spec D: fine-tuned NLI transformer for stance. The proposed primary measure.

Relevance comes from the shared transformer (build/02_relevance_transformer.py), which the
evaluation joins on.

In:  build/01_units.csv, build/01_labels.csv
Out: build/05_spec_d_oof.csv     held-out predictions for labeled rows
     build/05_spec_d_scores.csv  final model's predictions for all frame units

Choices, and why:
- The hypotheses name the target country, so the model is asked for attitude toward that
  country rather than general tone. That is the construct the labels measure.
- Stance reads the passage only, not its context: the codebook codes the stance in the text.
- Trained on rows labeled about the target only. Every held-out row still gets a prediction,
  so the end-to-end evaluation can score a row the relevance filter wrongly lets through.
"""
import numpy as np
import pandas as pd

from sentiment_common import (
    BUILD_DIR, N_FOLDS, STANCE_CLASSES, fit_nli, load_labels, load_units, predict_nli, release,
    stance_hypotheses,
)


def hypotheses(d: pd.DataFrame):
    return [stance_hypotheses(s) for s in d["source"]]


def fit(train: pd.DataFrame, name: str):
    y = [STANCE_CLASSES.index(v) for v in train["stance3"]]
    return fit_nli(train["text"].tolist(), hypotheses(train), y, log_prefix=name)


def with_summary(ids: pd.DataFrame, p: np.ndarray) -> pd.DataFrame:
    out = ids.reset_index(drop=True).copy()
    for j, name in enumerate(STANCE_CLASSES):
        out[f"p_{name}"] = p[:, j]
    out["pred_stance"] = np.array(STANCE_CLASSES)[p.argmax(axis=1)]
    out["net"] = out["p_pos"] - out["p_neg"]
    return out


labels = load_labels()
on_target = labels["about_target"] == "yes"
OOF_PATH = BUILD_DIR / "05_spec_d_oof.csv"
# Finished folds are kept, so an interrupted run resumes. Delete the file to start over.
done = pd.read_csv(OOF_PATH) if OOF_PATH.exists() else None
for fold in range(1, N_FOLDS + 1):
    held_out = labels["fold"] == fold
    if done is not None and labels.loc[held_out, "sample_id"].isin(done["sample_id"]).all():
        continue
    model, tokenizer = fit(labels[~held_out & on_target], f"fold {fold}")
    test = labels[held_out]
    p = predict_nli(model, tokenizer, test["text"].tolist(), hypotheses(test))
    done = pd.concat([done, with_summary(test[["sample_id"]], p)]).sort_values("sample_id")
    done.to_csv(OOF_PATH, index=False)
    release(model)
assert len(done) == len(labels)

model, tokenizer = fit(labels[on_target], "final")
units = load_units()
p = predict_nli(model, tokenizer, units["text"].tolist(), hypotheses(units), log_prefix="scoring")
with_summary(units[["unit_id", "source"]], p).to_csv(BUILD_DIR / "05_spec_d_scores.csv", index=False)
print(f"Scored {len(units)} units.")
