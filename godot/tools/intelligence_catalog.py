"""Strict, read-only validation for authored intelligence content.

This module does not load a game, mutate a resident, or execute conditions.
"""
from __future__ import annotations

import copy
import json
import math
import re
from pathlib import Path

IDENTIFIER = re.compile(r"[a-z][a-z0-9_.-]{0,63}\Z")
ACTIONS = frozenset(("nearby", "wander", "rest", "facility", "garden", "watch", "stretch", "look", "flower_gift"))
ASPECTS = frozenset(("idle", "speech", "wishes", "schedules", "fishing", "gomoku", "flower", "social", "rest", "movement", "leisure"))
HUNGER_STATES = frozenset(("full", "peckish", "hungry", "very_hungry"))
RELATIONSHIP_STAGES = frozenset(("new", "familiar", "close", "attuned", "family"))
PHASES = frozenset(("morning", "afternoon", "dusk", "night"))
WEATHER = frozenset(("sunny", "cloudy", "rain", "fog"))
PLAYER_ACTIONS = frozenset(("idle", "move", "chop", "gather_wood", "gather_mushrooms", "forage", "fish", "cook", "plant", "water", "harvest", "build", "build_house", "homestead", "eat", "play_gomoku", "chat"))
LEVELS = frozenset(("low", "medium", "high", "ultra"))
FAMILIES = {"speech": "units/speech", "behavior": "units/behavior", "traits": "traits", "presets": "presets"}
MAX_FILE_BYTES = 512 * 1024


class CatalogError(ValueError):
    """A complete catalog cannot be used; message identifies its first error."""


def fail(path: str, message: str) -> None:
    raise CatalogError(f"{path}: {message}")


def keys(value: object, required: set[str], optional: set[str], path: str) -> dict:
    if not isinstance(value, dict):
        fail(path, "must be an object")
    if any(not isinstance(key, str) for key in value):
        fail(path, "object keys must be strings")
    missing = required - value.keys()
    unknown = value.keys() - required - optional
    if missing:
        fail(path, "missing fields " + ", ".join(sorted(missing)))
    if unknown:
        fail(path, "unknown fields " + ", ".join(sorted(unknown)))
    return value


def text(value: object, path: str, maximum: int = 160) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum or "\x00" in value:
        fail(path, f"must be nonempty text of at most {maximum} characters")
    return value


def identifier(value: object, path: str) -> str:
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        fail(path, "must be a lowercase identifier (1–64 characters)")
    return value


def number(value: object, path: str, minimum: float = 0.0, maximum: float = 3600.0) -> float:
    if type(value) not in (int, float) or not math.isfinite(value) or not minimum <= value <= maximum:
        fail(path, f"must be a finite number in [{minimum}, {maximum}]")
    return float(value)


def boolean(value: object, path: str) -> None:
    if type(value) is not bool:
        fail(path, "must be a boolean")


def string_list(value: object, path: str, *, maximum: int = 128, allowed: frozenset | None = None) -> list:
    if not isinstance(value, list) or len(value) > maximum:
        fail(path, f"must be an array of at most {maximum} identifiers")
    seen = set()
    for index, item in enumerate(value):
        identifier(item, f"{path}[{index}]")
        if item in seen:
            fail(f"{path}[{index}]", "duplicate value")
        if allowed is not None and item not in allowed:
            fail(f"{path}[{index}]", "unknown value " + item)
        seen.add(item)
    return value


def conditions(value: object, path: str, *, nonempty: bool = False) -> None:
    allowed = {"hunger_at_least", "player_idle", "player_actions", "relationship_below", "interaction_age_at_least", "nearby_count_at_least", "phases", "weather", "task_active"}
    data = keys(value, set(), allowed, path)
    if nonempty and not data:
        fail(path, "context activation must contain a condition")
    for key, entry in data.items():
        field = path + "." + key
        if key in ("player_idle", "task_active"):
            boolean(entry, field)
        elif key == "interaction_age_at_least":
            number(entry, field, 0, 86400)
        elif key == "nearby_count_at_least":
            if type(entry) is not int or not 0 <= entry <= 64:
                fail(field, "must be an integer in [0, 64]")
        elif key in ("hunger_at_least", "relationship_below"):
            options = HUNGER_STATES if key == "hunger_at_least" else RELATIONSHIP_STAGES
            if not isinstance(entry, str) or entry not in options:
                fail(field, "unknown state")
        else:
            options = {"player_actions": PLAYER_ACTIONS, "phases": PHASES, "weather": WEATHER}[key]
            if not string_list(entry, field, maximum=32, allowed=options):
                fail(field, "condition list cannot be empty")


def weights(value: object, path: str, *, actions_only: bool) -> None:
    if not isinstance(value, dict) or len(value) > 128:
        fail(path, "must be an object of at most 128 weights")
    for key, amount in value.items():
        identifier(key, path + ".key")
        if actions_only and key not in ACTIONS:
            fail(path + "." + key, "unknown local behavior")
        number(amount, path + "." + key, 0, 100)


def validate_gait(value: object, path: str = "gait") -> None:
    limits = {"step_scale": (.4, 2), "bounce": (0, 10), "squash": (0, .12), "sway": (0, 4), "lean": (-.12, .12), "dust": (0, 2), "spin_every": (0, 120), "spin_seconds": (.2, 2), "look_every": (0, 120), "look_seconds": (.2, 2), "full_boost": (1, 1.5), "hungry_scale": (.2, 1), "head_drop": (0, 6)}
    optional = {'run_bounce': [0, 16], 'run_sway': [0, 2], 'run_lean': [0, 0.3], 'run_stretch': [0, 0.12], 'run_dust': [0, 3], 'run_frames_per_step': [0.4, 2]}
    data = keys(value, set(limits), set(optional), path)
    for key, bounds in optional.items():
        if key in data:
            number(data[key], path + "." + key, *bounds)
    for key, bounds in limits.items():
        number(data[key], path + "." + key, *bounds)
    for key in ("spin_every", "look_every"):
        if data[key] != 0 and data[key] < 5:
            fail(path + "." + key, "must be zero or at least five seconds")


def validate_entry(family: str, value: object, path: str = "entry") -> dict:
    """Validate one entry without resolving references; return a deep copy."""
    if family == "speech":
        data = keys(value, {"id", "context", "lines", "autonomy_output"}, set(), path)
        identifier(data["context"], path + ".context")
        lines = data["lines"]
        if not isinstance(lines, list) or not 1 <= len(lines) <= 128:
            fail(path + ".lines", "must contain 1–128 authored lines")
        for index, line in enumerate(lines):
            text(line, f"{path}.lines[{index}]")
        if len(set(lines)) != len(lines):
            fail(path + ".lines", "duplicate lines")
        boolean(data["autonomy_output"], path + ".autonomy_output")
    elif family == "behavior":
        data = keys(value, {"id", "action", "conditions", "cooldown_seconds", "requires_target"}, {"weight", "aspect"}, path)
        if not isinstance(data["action"], str) or data["action"] not in ACTIONS:
            fail(path + ".action", "unknown local behavior")
        conditions(data["conditions"], path + ".conditions")
        number(data["cooldown_seconds"], path + ".cooldown_seconds", 0, 86400)
        boolean(data["requires_target"], path + ".requires_target")
        if "weight" in data:
            number(data["weight"], path + ".weight", 0, 100)
        if "aspect" in data and (not isinstance(data["aspect"], str) or data["aspect"] not in ASPECTS):
            fail(path + ".aspect", "unknown controlled aspect")
    elif family == "traits":
        data = keys(value, {"id", "name", "description", "speech_units", "behavior_units", "speech_multiplier", "hunger_multiplier", "activation"}, {"weights", "wish_weights", "schedule_weights", "favorite_foods", "gait", "eating_style", "voice", "return_visit"}, path)
        text(data["name"], path + ".name", 48)
        text(data["description"], path + ".description", 512)
        string_list(data["speech_units"], path + ".speech_units")
        string_list(data["behavior_units"], path + ".behavior_units")
        number(data["speech_multiplier"], path + ".speech_multiplier", 0.05, 10)
        number(data["hunger_multiplier"], path + ".hunger_multiplier", 0.05, 10)
        if "return_visit" in data:
            limits = {"interval_seconds": (300, 900), "far_distance": (16, 80), "far_seconds": (90, 600), "stay_seconds": (5, 40), "stagger_seconds": (15, 90), "route_timeout_seconds": (24, 300)}
            visit = keys(data["return_visit"], set(), set(limits), path + ".return_visit")
            for key, value in visit.items():
                number(value, path + ".return_visit." + key, *limits[key])
        if "voice" in data:
            v = keys(data["voice"], {"event", "pitch", "max_blips"}, set(), path + ".voice")
            if v["event"] not in ("voice.soft", "voice.bright", "voice.crisp", "voice.low"):
                fail(path + ".voice.event", "unknown presentation voice")
            number(v["pitch"], path + ".voice.pitch", .5, 2)
            number(v["max_blips"], path + ".voice.max_blips", 1, 1)
        if "eating_style" in data and data["eating_style"] not in ("default", "patient", "eager", "hearty", "quiet"):
            fail(path + ".eating_style", "unknown presentation style")
        if "gait" in data:
            validate_gait(data["gait"], path + ".gait")
        if "favorite_foods" in data:
            favorite = data["favorite_foods"]
            allowed_foods = {"*", "fish", "fruit", "vegetable", "mushroom", "dish", "blueberry-jam", "grilled-fish", "honey-berry-apple", "sea-land-skewers", "harvest-stew", "dark-truffle-soup"}
            if not isinstance(favorite, list) or len(favorite) > 8 or any(not isinstance(f, str) or f not in allowed_foods for f in favorite) or len(set(favorite)) != len(favorite):
                fail(path + ".favorite_foods", "invalid favorite food references")
        if data["activation"] is not None:
            conditions(data["activation"], path + ".activation", nonempty=True)
        for field in ("weights", "wish_weights", "schedule_weights"):
            if field in data:
                weights(data[field], path + "." + field, actions_only=field == "weights")
    elif family == "presets":
        data = keys(value, {"id", "name", "main_trait", "context_traits", "speech_style", "mode"}, {"autonomy_level"}, path)
        text(data["name"], path + ".name", 48)
        text(data["speech_style"], path + ".speech_style", 512)
        identifier(data["main_trait"], path + ".main_trait")
        string_list(data["context_traits"], path + ".context_traits", maximum=16)
        if data["mode"] not in ("local", "model"):
            fail(path + ".mode", "must be local or model")
        if data["mode"] == "local" and "autonomy_level" in data:
            fail(path + ".autonomy_level", "is allowed only in model mode")
        if data["mode"] == "model":
            if not isinstance(data.get("autonomy_level"), str) or data["autonomy_level"] not in LEVELS:
                fail(path + ".autonomy_level", "model mode requires low/medium/high/ultra")
    else:
        fail(path, "unknown catalog family")
    identifier(data["id"], path + ".id")
    return copy.deepcopy(data)


def _pairs(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key " + key)
        result[key] = value
    return result


def load_catalog(root: str | Path) -> dict:
    """Load an entire catalog atomically; no partial result escapes rejection."""
    root = Path(root)
    catalog = {family: {} for family in FAMILIES}
    for family, folder in FAMILIES.items():
        directory = root / folder
        paths = sorted(directory.glob("*.json")) if directory.is_dir() else []
        if not paths or len(paths) > 512:
            fail(str(directory), "must contain 1–512 JSON entries")
        for path in paths:
            try:
                if path.stat().st_size > MAX_FILE_BYTES:
                    fail(str(path), "JSON file exceeds 512 KiB")
                data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_pairs, parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON number " + value)))
            except (ValueError, OSError, UnicodeError) as error:
                fail(str(path), "invalid JSON: " + str(error))
            entry = validate_entry(family, data, str(path))
            if path.stem != entry["id"]:
                fail(str(path) + ".id", "must match the filename stem")
            if entry["id"] in catalog[family]:
                fail(str(path) + ".id", "duplicate identifier")
            catalog[family][entry["id"]] = entry
    for trait_id, trait in catalog["traits"].items():
        for field, family in (("speech_units", "speech"), ("behavior_units", "behavior")):
            for reference in trait[field]:
                if reference not in catalog[family]:
                    fail(f"traits.{trait_id}.{field}", "unknown reference " + reference)
    for preset_id, preset in catalog["presets"].items():
        main = catalog["traits"].get(preset["main_trait"])
        if main is None:
            fail(f"presets.{preset_id}.main_trait", "unknown reference " + preset["main_trait"])
        if main["activation"] is not None:
            fail(f"presets.{preset_id}.main_trait", "main trait must have null activation")
        for reference in preset["context_traits"]:
            context = catalog["traits"].get(reference)
            if context is None:
                fail(f"presets.{preset_id}.context_traits", "unknown reference " + reference)
            if context["activation"] is None:
                fail(f"presets.{preset_id}.context_traits", "context trait must have an activation condition")
    return copy.deepcopy(catalog)


def combine_traits(main: dict, active_contexts: list[dict]) -> dict:
    """Pure composition: priority-ordered contexts own only declared weight keys."""
    validate_entry("traits", main, "main")
    if main["activation"] is not None:
        fail("main.activation", "main trait must have null activation")
    if not isinstance(active_contexts, list) or len(active_contexts) > 2:
        fail("active_contexts", "at most two context traits may be active")
    result = {"speech_multiplier": float(main["speech_multiplier"]), "hunger_multiplier": float(main["hunger_multiplier"]), "weights": copy.deepcopy(main.get("weights", {})), "wish_weights": copy.deepcopy(main.get("wish_weights", {})), "schedule_weights": copy.deepcopy(main.get("schedule_weights", {}))}
    seen = {main["id"]}
    overridden = {field: set() for field in ("weights", "wish_weights", "schedule_weights")}
    for index, trait in enumerate(active_contexts):
        validate_entry("traits", trait, f"active_contexts[{index}]")
        if trait["id"] in seen or trait["activation"] is None:
            fail(f"active_contexts[{index}]", "must be a distinct contextual trait")
        seen.add(trait["id"])
        result["speech_multiplier"] *= float(trait["speech_multiplier"])
        result["hunger_multiplier"] = max(result["hunger_multiplier"], float(trait["hunger_multiplier"]))
        for field in overridden:
            for key, amount in trait.get(field, {}).items():
                if key not in overridden[field]:
                    result[field][key] = amount
                    overridden[field].add(key)
    return result


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1] / "content/intelligence")
    arguments = parser.parse_args()
    try:
        loaded = load_catalog(arguments.root)
    except CatalogError as error:
        parser.exit(1, str(error) + "\n")
    print("Intelligence content valid: " + ", ".join(f"{key}={len(value)}" for key, value in loaded.items()))
