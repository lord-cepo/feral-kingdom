"""Fit a small outcome model from the MCTS pilot's completed games."""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def load_games(directory):
    games = []
    for shard in sorted(directory.glob("shard-*.jsonl")):
        with shard.open(encoding="utf-8") as stream:
            for line in stream:
                if not line.endswith("\n"):
                    break  # A worker may still be writing the final line.
                game = json.loads(line)
                if game["winner"] in (1, 2) and game["rows"] and not game.get("rejected"):
                    games.append(game)
    return sorted(games, key=lambda game: game["seed"])


def examples(games, max_positions=0):
    rows = []
    for game in games:
        positions = game["rows"]
        if max_positions and len(positions) > max_positions:
            indices = np.linspace(0, len(positions) - 1, max_positions, dtype=int)
            positions = [positions[index] for index in indices]
        rows.extend((row["features"], row["owner"] == game["winner"]) for row in positions)
    features, labels = zip(*rows)
    return np.asarray(features, dtype=np.float32), np.asarray(labels, dtype=np.float32)


def unique_trajectories(games):
    """Keep one example of an exactly repeated full-catalogue trajectory."""
    seen = set()
    for game in games:
        if game.get("pairing") == "full-catalogue":
            payload = json.dumps((game["winner"], game["rows"]), sort_keys=True, separators=(",", ":"))
            digest = hashlib.sha256(payload.encode()).digest()
            if digest in seen:
                continue
            seen.add(digest)
        yield game


def opposite_full_view(features):
    """Swap the player-relative blocks in the driver's 26-feature encoding."""
    swapped = features.copy()
    swapped[:, 0] = 3 - features[:, 0]
    swapped[:, 1] = 1 - features[:, 1]
    swapped[:, 3:12] = features[:, 12:21]
    swapped[:, 12:21] = features[:, 3:12]
    return swapped


def fit(games, xp, epochs, holdout_pairings=(), hidden_size=32, max_positions=0):
    rng = np.random.default_rng(42)
    if holdout_pairings:
        train_games = [game for game in games if game.get("pairing") not in holdout_pairings]
        validation_games = [game for game in games if game.get("pairing") in holdout_pairings]
    else:
        def group(game):
            # Full-catalogue seat swaps share a starting seed and random stream.
            seed = game["seed"]
            return seed - seed % 2 if game.get("pairing") == "full-catalogue" else seed

        groups = rng.permutation(sorted({group(game) for game in games}))
        validation_count = max(1, len(groups) // 5)
        validation_groups = set(groups[:validation_count])
        train_games = [game for game in games if group(game) not in validation_groups]
        validation_games = [game for game in games if group(game) in validation_groups]
    if not train_games or not validation_games:
        raise ValueError("Both training and holdout splits need completed games.")
    train_x, train_y = examples(train_games, max_positions)
    valid_x, valid_y = examples(validation_games)
    full_model = train_x.shape[1] == 26 and all(game.get("pairing") == "full-catalogue" for game in games)
    if full_model:
        train_x = np.concatenate([train_x, opposite_full_view(train_x)])
        train_y = np.concatenate([train_y, 1 - train_y])
    mean = train_x.mean(axis=0)
    deviations = train_x.std(axis=0)
    scale = np.maximum(deviations, 0.01)
    normalized_limit = 6.0 if full_model else np.inf

    def normalized(inputs):
        return xp.asarray(np.clip((inputs - mean) / scale, -normalized_limit, normalized_limit))

    x, y = normalized(train_x), xp.asarray(train_y)
    valid = normalized(valid_x)
    weights = xp.asarray(rng.normal(0, 0.1, (x.shape[1], hidden_size)).astype(np.float32))
    if full_model:
        weights[xp.asarray(deviations < 0.01)] = 0.0
    bias = xp.zeros(hidden_size, dtype=xp.float32)
    output = xp.asarray(rng.normal(0, 0.1, hidden_size).astype(np.float32))
    intercept = xp.zeros((), dtype=xp.float32)
    for _ in range(epochs):
        for batch in np.array_split(rng.permutation(len(train_x)), (len(train_x) + 255) // 256):
            inputs = x[batch]
            hidden = xp.tanh(inputs @ weights + bias)
            logits = xp.clip(hidden @ output + intercept, -30, 30)
            error = (1 / (1 + xp.exp(-logits)) - y[batch]) / len(batch)
            hidden_error = (error[:, None] * output) * (1 - hidden**2)
            weights -= 0.05 * (inputs.T @ hidden_error)
            bias -= 0.05 * hidden_error.sum(axis=0)
            output -= 0.05 * (hidden.T @ error)
            intercept -= 0.05 * error.sum()
    valid_logits = xp.tanh(valid @ weights + bias) @ output + intercept
    if full_model:
        opposite = normalized(opposite_full_view(valid_x))
        opposite_logits = xp.tanh(opposite @ weights + bias) @ output + intercept
        value = (xp.tanh(valid_logits * 0.5) - xp.tanh(opposite_logits * 0.5)) * 0.5
        valid_logits = 2 * xp.arctanh(xp.clip(value, -0.999999, 0.999999))
    validation_accuracy = float(((valid_logits >= 0) == xp.asarray(valid_y)).mean())
    validation_loss = float((xp.logaddexp(0, valid_logits) - xp.asarray(valid_y) * valid_logits).mean())
    prior = float(np.clip(train_y.mean(), 0.001, 0.999))
    prior_loss = float((-valid_y * np.log(prior) - (1 - valid_y) * np.log1p(-prior)).mean())
    to_numpy = np.asarray if xp is np else xp.asnumpy
    return dict(mean=mean, scale=scale, weights=to_numpy(weights), bias=to_numpy(bias),
                output=to_numpy(output), intercept=to_numpy(intercept),
                normalized_limit=normalized_limit,
                validation_accuracy=validation_accuracy, validation_loss=validation_loss,
                validation_prior_loss=prior_loss,
                validation_seeds=[game["seed"] for game in validation_games],
                validation_positions=len(valid_y), training_positions=len(train_y),
                validation_seat1_accuracy=float((valid_y == (valid_x[:, 0] == 1)).mean()),
                training_games=len(train_games),
                games=len(games))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shards", type=Path)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--hidden-size", type=int, default=32)
    parser.add_argument("--max-positions-per-game", type=int, default=0,
                        help="Limit training positions per game using evenly spaced positions; zero uses all.")
    parser.add_argument("--device", choices=("cpu", "cuda"), default="cpu")
    parser.add_argument("--export-json", type=Path,
                        help="Export the fitted weights for the Godot self-play driver.")
    parser.add_argument("--additional-shards", type=Path, action="append", default=[],
                        help="Add games from another training round with the same features.")
    parser.add_argument("--holdout-pairings", nargs="+", default=(),
                        help="Reserve complete matchup IDs such as 0-3 and 1-2.")
    args = parser.parse_args()
    if args.epochs < 1 or args.hidden_size < 1 or args.max_positions_per_game < 0:
        parser.error("Epochs and hidden size must be positive, and the position cap must be nonnegative.")
    backend = np
    if args.device == "cuda":
        import cupy as backend
    games_by_seed = {game["seed"]: game for folder in [args.shards, *args.additional_shards]
                     for game in load_games(folder)}
    games = list(unique_trajectories(sorted(games_by_seed.values(), key=lambda game: game["seed"])))
    if len(games) < 2:
        parser.error("At least two completed games are required for a game-level validation split.")
    try:
        checkpoint = fit(games, backend, args.epochs, args.holdout_pairings, args.hidden_size,
                         args.max_positions_per_game)
    except ValueError as error:
        parser.error(str(error))
    np.savez_compressed(args.checkpoint, **checkpoint)
    if args.export_json is not None:
        keys = ("mean", "scale", "weights", "bias", "output", "intercept")
        model = {key: np.asarray(checkpoint[key]).tolist() for key in keys}
        if np.isfinite(checkpoint["normalized_limit"]):
            model["normalized_limit"] = checkpoint["normalized_limit"]
        args.export_json.write_text(json.dumps(model, separators=(",", ":")), encoding="utf-8")
    print(f"Fit {checkpoint['games']} games on {args.device}. "
          f"Position accuracy on held-out games: {checkpoint['validation_accuracy']:.1%}. "
          f"Seat 1 baseline: {checkpoint['validation_seat1_accuracy']:.1%}. "
          f"Log loss: {checkpoint['validation_loss']:.3f} "
          f"(training-prior baseline {checkpoint['validation_prior_loss']:.3f}).")


if __name__ == "__main__":
    main()
