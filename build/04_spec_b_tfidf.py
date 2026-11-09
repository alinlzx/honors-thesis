"""Spec B: TF-IDF with regularized logistic regression for stance.

Relevance comes from the shared transformer (build/02_relevance_transformer.py), which the
evaluation joins on.

In:  build/01_units.csv, build/01_labels.csv
Out: build/04_spec_b_oof.csv     held-out predictions for labeled rows
     build/04_spec_b_scores.csv  final model's predictions for all frame units

Choices, and why:
- Sources are pooled, with a source indicator, because no one source has enough rows.
- Trained on rows labeled about the target only, since off-target text has no stance. Every
  held-out row still gets a prediction, so the end-to-end evaluation can score a row the
  relevance filter wrongly lets through.
- Regularization strength is chosen by inner cross-validation on log loss over the whole
  pipeline, so the vocabulary is refit in each inner fold. Inner folds must be shuffled: rows
  are sorted by source, and unshuffled folds hold out one source at a time, which picks the
  smallest C and gives near-constant predictions within each source.
- Classes are not reweighted, because the series uses the probabilities and reweighting
  distorts them.
"""
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV, StratifiedKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

from sentiment_common import BUILD_DIR, N_FOLDS, SEED, STANCE_CLASSES, load_labels, load_units


def make_model() -> GridSearchCV:
    features = ColumnTransformer([
        ("words", TfidfVectorizer(ngram_range=(1, 2), min_df=2, sublinear_tf=True, stop_words="english"), "text"),
        ("source", OneHotEncoder(handle_unknown="ignore"), ["source"]),
    ])
    pipeline = Pipeline([("features", features), ("classifier", LogisticRegression(max_iter=3000))])
    inner = StratifiedKFold(5, shuffle=True, random_state=SEED)
    return GridSearchCV(pipeline, {"classifier__C": np.logspace(-1, 2, 7)}, cv=inner, scoring="neg_log_loss")


def fit(train: pd.DataFrame) -> GridSearchCV:
    return make_model().fit(train[["text", "source"]], train["stance3"])


def probabilities(model: GridSearchCV, data: pd.DataFrame) -> pd.DataFrame:
    p = model.predict_proba(data[["text", "source"]])
    return pd.DataFrame(p, columns=model.classes_, index=data.index)[STANCE_CLASSES].add_prefix("p_")


def add_summary(d: pd.DataFrame) -> pd.DataFrame:
    probs = d[["p_neg", "p_neutral", "p_pos"]].to_numpy()
    d["pred_stance"] = np.array(STANCE_CLASSES)[probs.argmax(axis=1)]
    d["net"] = d["p_pos"] - d["p_neg"]
    return d


labels = load_labels()
on_target = labels["about_target"] == "yes"

oof = []
for fold in range(1, N_FOLDS + 1):
    held_out = labels["fold"] == fold
    model = fit(labels[~held_out & on_target])
    oof.append(pd.concat([labels.loc[held_out, ["sample_id"]], probabilities(model, labels[held_out])], axis=1))
    print(f"fold {fold}: C = {model.best_params_['classifier__C']:.2f}", flush=True)
oof = add_summary(pd.concat(oof).sort_values("sample_id"))
assert len(oof) == len(labels)
oof.to_csv(BUILD_DIR / "04_spec_b_oof.csv", index=False)

final = fit(labels[on_target])
units = load_units()
scores = pd.concat([units[["unit_id", "source"]], probabilities(final, units)], axis=1)
add_summary(scores).to_csv(BUILD_DIR / "04_spec_b_scores.csv", index=False)
print(f"Scored {len(scores)} units.")
