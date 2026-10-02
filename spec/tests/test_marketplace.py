from opc_spec import marketplace

CATALOG = {
    "generatedAt": "2026-10-01T00:00:00.000Z",
    "plugins": [
        {"id": "a.clock", "name": "Clock", "repo": "https://github.com/a/clock"},
        {
            "id": "a.suite-x",
            "repo": "https://github.com/A/Suite.git",
            "manifestPath": "plugins/x/manifest.json",
        },
        {"id": "old.thing", "name": "Old", "repo": "https://github.com/old/thing"},
        {"id": "omarchy.weather", "repo": "https://github.com/omacom/omarchy", "sourceType": "builtin"},
        {"id": "omarchy.b", "repo": "https://github.com/omacom/omarchy", "builtIn": True},
        {"id": "x y"},
        {"name": "no id"},
        {"id": "n.repo", "repo": 5},
    ],
}
REGISTRY = {
    "retiredPluginIds": ["old.thing"],
    "repositoryMigrations": [
        {"fromRepository": "a/clock-old", "toRepository": "a/clock"},
        {"fromRepository": "a/same", "toRepository": "https://github.com/a/same"},
        {"fromRepository": 3},
    ],
    "sources": [
        {"repo": "https://github.com/a/clock", "repositoryIdentity": {"previousRepositories": ["a/ancient"]}},
        {"repo": "https://github.com/a/clock", "repositoryIdentity": {"previousRepositories": ["a/clock"]}},
        {"repo": None},
    ],
}


def test_parse_states_ids_and_repos():
    m = marketplace.parse(CATALOG, REGISTRY)
    assert set(m.plugins) == {"a.clock", "a.suite-x", "old.thing", "omarchy.weather", "omarchy.b", "n.repo"}
    assert m.plugins["old.thing"].state == "retired"
    assert m.plugins["omarchy.weather"].state == "builtin"
    assert m.plugins["omarchy.b"].state == "builtin"
    assert m.plugins["a.clock"].state == "listed"
    assert m.plugins["a.clock"].name == "Clock"
    assert m.plugins["a.suite-x"].name == "a.suite-x"
    assert m.plugins["a.suite-x"].repo == "https://github.com/A/Suite"
    assert m.plugins["a.suite-x"].repo_key == "a/suite"
    assert m.plugins["n.repo"].repo is None
    assert m.generated_at == "2026-10-01T00:00:00.000Z"


def test_migrations_canonical_and_by_repo():
    m = marketplace.parse(CATALOG, REGISTRY)
    assert m.canonical("a/clock-old") == "a/clock"
    assert m.canonical("a/ancient") == "a/clock"
    assert m.canonical("z/z") == "z/z"
    assert "a/same" not in m.migrations
    m.migrations["loop/a"] = "loop/b"
    m.migrations["loop/b"] = "loop/a"
    assert m.canonical("loop/a") in {"loop/a", "loop/b"}
    by = m.by_repo()
    assert by["a/clock"] == ["a.clock"]
    assert by["a/clock-old"] == ["a.clock"]
    assert by["omacom/omarchy"] == ["omarchy.b", "omarchy.weather"]
    assert "loop/a" not in by


def test_no_registry_and_helpers():
    m = marketplace.parse({}, None)
    assert m.plugins == {}
    assert m.generated_at is None
    assert marketplace.key_of(None) is None
    assert marketplace.key_of("o/r") == "o/r"
    assert marketplace.key_of("https://github.com/O/R") == "o/r"
    assert marketplace.manifest_dir({"manifestPath": "plugins/x/manifest.json"}) == "plugins/x"
    assert marketplace.manifest_dir({}) == ""


def test_former_repositories():
    m = marketplace.parse(CATALOG, REGISTRY)
    assert m.former("a/clock") == ["a/ancient", "a/clock-old"]
    assert m.former("z/z") == []
    # A previous name that is now another listing's repository belongs to that listing.
    m.migrations["old/thing"] = "a/clock"
    assert "old/thing" not in m.former("a/clock")
