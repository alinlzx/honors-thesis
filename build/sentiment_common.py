"""Shared code for the sentiment specs: data loading and the NLI transformer engine.

The transformer reads each passage (the premise) against one hypothesis per class, written
from the codebook and naming the target country, and picks the hypothesis the passage best
supports. Training applies cross-entropy across a row's hypotheses, so the outputs are
probabilities over classes. Relevance (2 hypotheses) and stance (3) use the same code.
"""
import random
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    get_linear_schedule_with_warmup,
)

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scrape"))
from config import BUILD_DIR  # noqa: E402

# xsmall because the base-size model took 37 s per training step on the M4 (about 46 hours in
# all) against under 2 s here. analysis_recipes.md section 6 has the comparison.
MODEL_NAME = "MoritzLaurer/DeBERTa-v3-xsmall-mnli-fever-anli-ling-binary"
MODEL_REVISION = "b80e2b3219194b8685948dedfb73d594ed088732"

# Fixed in advance rather than tuned, so no labeled rows are spent on tuning.
EPOCHS = 3
LEARNING_RATE = 2e-5
WEIGHT_DECAY = 0.01
TRAIN_BATCH_ROWS = 8
MICRO_BATCH_ROWS = 2
MAX_TOKENS = 320  # per window; longer passages are split at prediction time
WINDOW_OVERLAP = 64
PREDICT_BATCH_PAIRS = 48
AUX_CHARS = 600  # keep the end of the context, the part closest to the text
N_FOLDS = 5
SEED = 20261104

STANCE_CLASSES = ["neg", "neutral", "pos"]
RELEVANCE_CLASSES = ["no", "yes"]


def target_of(source: str) -> str:
    return "the United States" if source == "mfa" else "China"


def stance_hypotheses(source: str) -> list[str]:
    t = target_of(source)
    return [
        f"The speaker criticizes, opposes, accuses, warns or makes demands of {t}, or presents it as a threat.",
        f"The speaker takes no clear overall stance toward {t}: a factual mention, or both criticism and praise.",
        f"The speaker praises or welcomes {t}, or stresses cooperation, agreement or goodwill with it.",
    ]


def relevance_hypotheses(source: str) -> list[str]:
    t = target_of(source)
    return [
        f"The text does not say anything about {t}: the mention is incidental, or it is about another country.",
        f"The text says something about {t}: its government, leaders, policies, actions, or relations with it.",
    ]


def relevance_premise(text: str, aux: str) -> str:
    aux = "" if pd.isna(aux) else str(aux)[-AUX_CHARS:]
    return f"Preceding text: {aux}\n\nText: {text}" if aux else f"Text: {text}"


def load_labels() -> pd.DataFrame:
    return pd.read_csv(BUILD_DIR / "01_labels.csv", dtype={"unit_id": str})


def load_units() -> pd.DataFrame:
    return pd.read_csv(BUILD_DIR / "01_units.csv", dtype={"unit_id": str})


def get_device() -> torch.device:
    return torch.device("mps" if torch.backends.mps.is_available() else "cpu")


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def load_tokenizer():
    return AutoTokenizer.from_pretrained(MODEL_NAME, revision=MODEL_REVISION)


def _load_model(device: torch.device):
    # These checkpoints can be stored as 16-bit floats, which turn to NaN on the first
    # optimizer step, so the type is set explicitly.
    model = AutoModelForSequenceClassification.from_pretrained(
        MODEL_NAME, revision=MODEL_REVISION, use_safetensors=True, dtype=torch.float32
    )
    return model.to(device)


def _entail_index(model) -> int:
    return {k.lower(): v for k, v in model.config.label2id.items()}["entailment"]


def fit_nli(premises, hypotheses, labels, seed=SEED, log_prefix="", max_steps=None):
    """Fine-tune on rows. hypotheses[i] lists row i's K hypotheses; labels[i] is the true one."""
    set_seed(seed)
    device = get_device()
    tokenizer = load_tokenizer()
    model = _load_model(device)
    model.train()
    entail = _entail_index(model)

    n = len(premises)
    k = len(hypotheses[0])
    steps_per_epoch = int(np.ceil(n / TRAIN_BATCH_ROWS))
    total_steps = steps_per_epoch * EPOCHS
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    scheduler = get_linear_schedule_with_warmup(optimizer, int(0.1 * total_steps), total_steps)
    labels = torch.tensor(np.asarray(labels), dtype=torch.long)

    step = 0
    for epoch in range(EPOCHS):
        order = np.random.permutation(n)
        running = 0.0
        for start in range(0, n, TRAIN_BATCH_ROWS):
            rows = order[start : start + TRAIN_BATCH_ROWS]
            # Gradients accumulate over small pieces, which is what fits in memory.
            for piece in np.array_split(rows, int(np.ceil(len(rows) / MICRO_BATCH_ROWS))):
                enc = tokenizer(
                    [premises[i] for i in piece for _ in range(k)],
                    [h for i in piece for h in hypotheses[i]],
                    truncation="only_first",
                    max_length=MAX_TOKENS,
                    padding=True,
                    return_tensors="pt",
                ).to(device)
                logits = model(**enc).logits[:, entail].reshape(len(piece), k)
                loss = torch.nn.functional.cross_entropy(logits, labels[piece].to(device))
                loss = loss * len(piece) / len(rows)
                loss.backward()
                running += loss.item()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            scheduler.step()
            optimizer.zero_grad()
            step += 1
            if max_steps and step >= max_steps:
                return model, tokenizer
        print(f"{log_prefix} epoch {epoch + 1}/{EPOCHS} loss {running / steps_per_epoch:.3f}", flush=True)
    return model, tokenizer


@torch.no_grad()
def predict_nli(model, tokenizer, premises, hypotheses, log_prefix=""):
    """Class probabilities, n rows by K hypotheses. A long passage is split into overlapping
    windows; each hypothesis's score is averaged over the windows."""
    device = next(model.parameters()).device
    model.eval()
    entail = _entail_index(model)
    n, k = len(premises), len(hypotheses[0])

    pairs = []  # (row, hypothesis, input_ids, attention_mask, token_type_ids)
    for start in range(0, n, 512):
        rows = range(start, min(start + 512, n))
        enc = tokenizer(
            [premises[i] for i in rows for _ in range(k)],
            [h for i in rows for h in hypotheses[i]],
            truncation="only_first",
            max_length=MAX_TOKENS,
            stride=WINDOW_OVERLAP,
            return_overflowing_tokens=True,
            padding=False,
        )
        for j, origin in enumerate(enc["overflow_to_sample_mapping"]):
            pairs.append((start + origin // k, origin % k, enc["input_ids"][j], enc["token_type_ids"][j]))

    # Similar lengths together, so batches carry little padding.
    pairs.sort(key=lambda p: len(p[2]))
    totals = np.zeros((n, k))
    counts = np.zeros((n, k))
    pad = tokenizer.pad_token_id
    for b in range(0, len(pairs), PREDICT_BATCH_PAIRS):
        batch = pairs[b : b + PREDICT_BATCH_PAIRS]
        width = max(len(p[2]) for p in batch)
        ids = torch.tensor([p[2] + [pad] * (width - len(p[2])) for p in batch], device=device)
        types = torch.tensor([p[3] + [0] * (width - len(p[3])) for p in batch], device=device)
        mask = (ids != pad).long()
        scores = model(input_ids=ids, attention_mask=mask, token_type_ids=types).logits[:, entail].cpu().numpy()
        for p, s in zip(batch, scores):
            totals[p[0], p[1]] += s
            counts[p[0], p[1]] += 1
        if log_prefix and b % (PREDICT_BATCH_PAIRS * 400) == 0:
            print(f"{log_prefix} {b}/{len(pairs)} pairs", flush=True)
    return torch.softmax(torch.tensor(totals / counts), dim=1).numpy()


def release(model) -> None:
    """Free GPU memory between folds."""
    del model
    if torch.backends.mps.is_available():
        torch.mps.empty_cache()
