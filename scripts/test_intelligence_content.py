#!/usr/bin/env python3
"""Data-only intelligence contract tests: temporary fixtures, no game/model calls."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("intelligence_catalog", ROOT / "godot/tools/intelligence_catalog.py")
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class IntelligenceContent(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="youqi-test-intelligence-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.entries = {
            "speech": {"id": "idle-lines", "context": "ambient", "lines": ["我在这里陪你。", "慢慢来。"], "autonomy_output": False},
            "behavior": {"id": "idle-rest", "action": "rest", "conditions": {}, "cooldown_seconds": 40, "requires_target": True, "weight": 1, "aspect": "rest"},
            "traits": {"id": "gentle", "name": "温柔", "description": "以安静陪伴为主。", "speech_units": ["idle-lines"], "behavior_units": ["idle-rest"], "speech_multiplier": 1.0, "hunger_multiplier": 1.0, "activation": None, "weights": {"rest": 2, "nearby": 1}, "wish_weights": {"meal": 1}, "schedule_weights": {"camp": 1}},
            "presets": {"id": "gentle-local", "name": "温柔本地", "main_trait": "gentle", "context_traits": [], "speech_style": "轻声短句。", "mode": "local"},
        }
        for family, entry in self.entries.items():
            self.write(family, entry)

    def write(self, family, entry):
        path = self.root / catalog.FAMILIES[family] / (entry["id"] + ".json")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(entry, ensure_ascii=False), encoding="utf-8")
        return path

    def reject_entry(self, family, entry, pattern):
        with self.assertRaisesRegex(catalog.CatalogError, pattern):
            catalog.validate_entry(family, entry, "fixture")

    def contextual(self, id="hungry", **changes):
        value = copy.deepcopy(self.entries["traits"])
        value.update(id=id, activation={"hunger_at_least": "hungry"}, hunger_multiplier=1.8, speech_multiplier=1.2, weights={"nearby": 4})
        value.update(changes)
        return value

    def test_project_content_and_all_fixture_families_load(self):
        self.assertEqual(set(catalog.load_catalog(self.root)), set(catalog.FAMILIES))
        actual = catalog.load_catalog(ROOT / "godot/content/intelligence")
        self.assertTrue(all(actual.values()))

    def test_missing_and_unknown_fields_reject_every_family(self):
        for family, original in self.entries.items():
            with self.subTest(family=family):
                value = copy.deepcopy(original); value.pop("id")
                self.reject_entry(family, value, "missing fields id")
                value = copy.deepcopy(original); value["execute"] = "anything"
                self.reject_entry(family, value, "unknown fields execute")

    def test_numeric_booleans_rejected(self):
        for family, field in [("behavior", "cooldown_seconds"), ("behavior", "weight"), ("traits", "speech_multiplier"), ("traits", "hunger_multiplier")]:
            value = copy.deepcopy(self.entries[family]); value[field] = True
            with self.subTest(family=family, field=field):
                self.reject_entry(family, value, "finite number")

    def test_nonfinite_values_and_bad_ranges_rejected(self):
        for amount in [float("nan"), float("inf"), -float("inf"), -1, 100000]:
            value = copy.deepcopy(self.entries["behavior"]); value["cooldown_seconds"] = amount
            with self.subTest(amount=amount):
                self.reject_entry("behavior", value, "finite number")

    def test_integer_and_float_counts_equivalent(self):
        first = copy.deepcopy(self.entries["behavior"]); first["cooldown_seconds"] = 30
        second = copy.deepcopy(first); second["cooldown_seconds"] = 30.0
        self.assertEqual(catalog.validate_entry("behavior", first), catalog.validate_entry("behavior", second))

    def test_only_known_existing_behavior_actions(self):
        for action in ["take_from_chest", "teleport", "feed", "execute", {}, True]:
            value = copy.deepcopy(self.entries["behavior"]); value["action"] = action
            with self.subTest(action=action): self.reject_entry("behavior", value, "unknown local behavior")

    def test_controlled_aspects_and_weight_keys(self):
        value = copy.deepcopy(self.entries["behavior"]); value["aspect"] = "inventory"
        self.reject_entry("behavior", value, "unknown controlled aspect")
        value = copy.deepcopy(self.entries["traits"]); value["weights"] = {"harvest": 5}
        self.reject_entry("traits", value, "unknown local behavior")

    def test_speech_bool_lines_and_duplicates_are_strict(self):
        for lines in [[], [""], ["a", "a"], [1], ["x" * 161]]:
            value = copy.deepcopy(self.entries["speech"]); value["lines"] = lines
            with self.subTest(lines=lines): self.reject_entry("speech", value, "lines")
        value = copy.deepcopy(self.entries["speech"]); value["autonomy_output"] = 1
        self.reject_entry("speech", value, "boolean")

    def test_conditions_are_data_only_and_known(self):
        for condition in [{"eval": "world.take()"}, {"player_idle": 1}, {"nearby_count_at_least": True}, {"nearby_count_at_least": 2.5}, {"hunger_at_least": "starving"}, {"relationship_below": "lover"}, {"player_actions": ["take_from_chest"]}, {"phases": ["never"]}, {"weather": []}]:
            value = copy.deepcopy(self.entries["behavior"]); value["conditions"] = condition
            with self.subTest(condition=condition): self.reject_entry("behavior", value, "conditions")

    def test_supported_conditions_accept(self):
        value = copy.deepcopy(self.entries["behavior"])
        value["conditions"] = {"hunger_at_least": "hungry", "player_idle": True, "player_actions": ["fish", "gather_mushrooms"], "relationship_below": "close", "interaction_age_at_least": 1200, "nearby_count_at_least": 3, "phases": ["night"], "weather": ["rain", "fog"], "task_active": False}
        self.assertEqual(catalog.validate_entry("behavior", value), value)

    def test_main_null_and_context_nonempty_activation(self):
        self.assertIsNone(catalog.validate_entry("traits", self.entries["traits"])["activation"])
        value = self.contextual(activation={})
        self.reject_entry("traits", value, "activation must contain a condition")
        self.assertEqual(catalog.validate_entry("traits", self.contextual())["activation"], {"hunger_at_least": "hungry"})

    def test_local_preset_cannot_enable_autonomy(self):
        value = copy.deepcopy(self.entries["presets"]); value["autonomy_level"] = "ultra"
        self.reject_entry("presets", value, "only in model mode")

    def test_model_preset_requires_known_level(self):
        value = copy.deepcopy(self.entries["presets"]); value["mode"] = "model"
        for level in [None, "max", True, {}, []]:
            value["autonomy_level"] = level
            with self.subTest(level=level): self.reject_entry("presets", value, "model mode requires")
        for level in ["low", "medium", "high", "ultra"]:
            value["autonomy_level"] = level
            self.assertEqual(catalog.validate_entry("presets", value)["autonomy_level"], level)

    def test_all_reference_families_resolve(self):
        for family, field, missing in [("traits", "speech_units", ["missing-speech"]), ("traits", "behavior_units", ["missing-behavior"]), ("presets", "main_trait", "missing-trait"), ("presets", "context_traits", ["missing-context"])]:
            value = copy.deepcopy(self.entries[family]); value[field] = missing; self.write(family, value)
            with self.subTest(family=family, field=field), self.assertRaisesRegex(catalog.CatalogError, "unknown reference"):
                catalog.load_catalog(self.root)
            self.write(family, self.entries[family])

    def test_preset_main_and_context_roles_cannot_be_swapped(self):
        context = self.contextual(); self.write("traits", context)
        preset = copy.deepcopy(self.entries["presets"]); preset["main_trait"] = context["id"]
        self.write("presets", preset)
        with self.assertRaisesRegex(catalog.CatalogError, "main trait must have null"):
            catalog.load_catalog(self.root)
        preset["main_trait"] = "gentle"; preset["context_traits"] = ["gentle"]; self.write("presets", preset)
        with self.assertRaisesRegex(catalog.CatalogError, "context trait must have"):
            catalog.load_catalog(self.root)

    def test_duplicate_references_and_unsafe_identifiers_reject(self):
        value = copy.deepcopy(self.entries["traits"]); value["speech_units"] *= 2
        self.reject_entry("traits", value, "duplicate value")
        for id in ["../escape", "execute()", "", "A", "a" * 65, 5]:
            value = copy.deepcopy(self.entries["speech"]); value["id"] = id
            with self.subTest(id=id): self.reject_entry("speech", value, "identifier")

    def test_json_duplicate_keys_reject_with_filename(self):
        path = self.root / "units/speech/idle-lines.json"
        path.write_text('{"id":"idle-lines","id":"again"}')
        with self.assertRaisesRegex(catalog.CatalogError, "idle-lines.json.*duplicate JSON key id"):
            catalog.load_catalog(self.root)

    def test_json_nonfinite_and_syntax_fail_atomically(self):
        path = self.root / "units/speech/idle-lines.json"
        for source in ['{"id":NaN}', '{"id":Infinity}', '{', '[]']:
            path.write_text(source)
            with self.subTest(source=source), self.assertRaises(catalog.CatalogError): catalog.load_catalog(self.root)

    def test_missing_family_and_filename_mismatch_reject(self):
        path = self.root / "units/speech/idle-lines.json"; path.rename(path.with_name("different.json"))
        with self.assertRaisesRegex(catalog.CatalogError, "filename stem"):
            catalog.load_catalog(self.root)
        path.with_name("different.json").unlink()
        with self.assertRaisesRegex(catalog.CatalogError, "must contain 1"):
            catalog.load_catalog(self.root)

    def test_readonly_load_and_validation_deep_copy(self):
        source = copy.deepcopy(self.entries["traits"])
        validated = catalog.validate_entry("traits", source)
        validated["weights"]["rest"] = 99
        self.assertEqual(source["weights"]["rest"], 2)
        before = {path: path.read_bytes() for path in self.root.rglob("*.json")}
        loaded = catalog.load_catalog(self.root); loaded["traits"]["gentle"]["weights"]["rest"] = 99
        self.assertEqual({path: path.read_bytes() for path in self.root.rglob("*.json")}, before)
        self.assertEqual(catalog.load_catalog(self.root)["traits"]["gentle"]["weights"]["rest"], 2)

    def test_composition_without_context_retains_main(self):
        main = self.entries["traits"]
        self.assertEqual(catalog.combine_traits(main, [])["hunger_multiplier"], 1)
        self.assertEqual(catalog.combine_traits(main, [])["weights"], main["weights"])

    def test_composition_hunger_max_and_speech_multiplies(self):
        main = copy.deepcopy(self.entries["traits"]); main["hunger_multiplier"] = 1.2; main["speech_multiplier"] = 0.9
        a = self.contextual(); b = self.contextual(id="clingy", hunger_multiplier=0.85, speech_multiplier=1.5)
        result = catalog.combine_traits(main, [a, b])
        self.assertAlmostEqual(result["hunger_multiplier"], max(1.2, 1.8, 0.85))
        self.assertAlmostEqual(result["speech_multiplier"], 0.9 * 1.2 * 1.5)

    def test_context_overrides_only_declared_keys_with_priority(self):
        first = self.contextual(weights={"nearby": 5})
        second = self.contextual(id="clingy", weights={"nearby": 9, "watch": 4})
        self.assertEqual(catalog.combine_traits(self.entries["traits"], [first, second])["weights"], {"rest": 2, "nearby": 5, "watch": 4})

    def test_composition_max_two_distinct_contexts_and_no_input_mutation(self):
        main = self.entries["traits"]; context = self.contextual(); before = copy.deepcopy((main, context))
        catalog.combine_traits(main, [context])
        self.assertEqual((main, context), before)
        for values in [[context] * 3, [context] * 2, [main]]:
            with self.subTest(values=values), self.assertRaises(catalog.CatalogError): catalog.combine_traits(main, values)


if __name__ == "__main__":
    unittest.main()
