"""PokeAPI CSV access (common.POKEAPI_CSV) for the stage-1 data tools."""
import csv
import os
import sys
from collections import defaultdict

sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402

_cache = {}


def rows(name):
    if name not in _cache:
        with open(os.path.join(common.need(common.POKEAPI_CSV, "PokeAPI CSV data"), name), encoding="utf-8") as f:
            _cache[name] = list(csv.DictReader(f))
    return _cache[name]


def by_id(name, key="id"):
    return {r[key]: r for r in rows(name)}


def english(name, key, field="name"):
    return {r[key]: r[field] for r in rows(name) if r["local_language_id"] == "9"}


class PA:
    """The tables the data tools need, keyed by PokeAPI id strings."""

    def __init__(self):
        self.species = by_id("pokemon_species.csv")
        self.pokemon = by_id("pokemon.csv")
        self.pid_of = {r["identifier"]: r["id"] for r in rows("pokemon.csv")}
        self.species_name = english("pokemon_species_names.csv", "pokemon_species_id")
        self.type_name = {r["id"]: r["identifier"].capitalize() for r in rows("types.csv")}
        self.types = defaultdict(list)
        for r in rows("pokemon_types.csv"):
            self.types[r["pokemon_id"]].append((int(r["slot"]), self.type_name[r["type_id"]]))
        self.stats = defaultdict(dict)
        for r in rows("pokemon_stats.csv"):
            self.stats[r["pokemon_id"]][r["stat_id"]] = int(r["base_stat"])
        self.ability_name = {r["id"]: r["identifier"] for r in rows("abilities.csv")}
        self.abilities = defaultdict(list)       # pokemon id -> [(slot, identifier, hidden)]
        for r in rows("pokemon_abilities.csv"):
            self.abilities[r["pokemon_id"]].append((int(r["slot"]), self.ability_name[r["ability_id"]], r["is_hidden"] == "1"))
        self.move_name = english("move_names.csv", "move_id")
        self.move_by_name = {v: k for k, v in self.move_name.items()}
        self.moves = by_id("moves.csv")
        self.move_meta = by_id("move_meta.csv", "move_id")
        self.move_stat = defaultdict(list)
        for r in rows("move_meta_stat_changes.csv"):
            self.move_stat[r["move_id"]].append((int(r["stat_id"]), int(r["change"])))
        self.target = {r["id"]: r["identifier"] for r in rows("move_targets.csv")}
        self.ailment = {r["id"]: r["identifier"] for r in rows("move_meta_ailments.csv")}
        self.meta_cat = {r["id"]: r["identifier"] for r in rows("move_meta_categories.csv")}
        self.items = {r["id"]: r["identifier"] for r in rows("items.csv")}
        self.evolution = rows("pokemon_evolution.csv")

    def base_stats(self, pid):
        """[hp, atk, def, spa, spd, spe]"""
        return [self.stats[pid][s] for s in ("1", "2", "3", "4", "5", "6")]

    def type_list(self, pid):
        return [t for _, t in sorted(self.types[pid])]

    _levelup = None

    def levelup(self):
        """pokemon id -> version group id -> [(level, order, move name)] (level-up moves only)."""
        if self._levelup is None:
            out = defaultdict(lambda: defaultdict(list))
            for r in rows("pokemon_moves.csv"):
                if r["pokemon_move_method_id"] == "1":
                    out[r["pokemon_id"]][r["version_group_id"]].append(
                        (int(r["level"]), int(r["order"] or 0), self.move_name[r["move_id"]]))
            self._levelup = out
            _cache.pop("pokemon_moves.csv", None)
        return self._levelup
