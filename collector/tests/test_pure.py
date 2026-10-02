import dataclasses
import datetime as dt

import pytest
from hypothesis import given
from hypothesis import strategies as st

from opc_collector import query, rank, readme, stats

NOW = dt.datetime(2026, 10, 2, 12, 0, tzinfo=dt.UTC)
SHA = "a" * 40


# --- readme -----------------------------------------------------------------------------------


def test_image_urls_resolve_filter_and_dedupe():
    md = """
# Title
![badge](https://img.shields.io/badge/x-y-green.svg) ![ci](https://github.com/o/r/actions/workflows/ci.yml/badge.svg)
![shot](docs/shot.png "Main window") ![again](./docs/shot.png)
<img width="600" src="/assets/panel.webp" alt="panel">
![blob](https://github.com/o/r/blob/main/img/a.jpg?raw=true)
![att](https://github.com/user-attachments/assets/0f3c1d2e-aaaa-bbbb-cccc-111122223333)
![old](https://user-images.githubusercontent.com/1/2.png)
![svg](logo.svg) ![http](http://example.com/a.png) ![up](../outside.png) ![data](data:image/png;base64,AAA)
![private](https://private-user-images.githubusercontent.com/1/x.png?jwt=1) ![proto](//cdn.example/x.gif)
![dot](.) ![anchor](#top)
"""
    urls = readme.image_urls(md, "o", "r", SHA)
    assert urls == [
        f"https://raw.githubusercontent.com/o/r/{SHA}/docs/shot.png",
        f"https://raw.githubusercontent.com/o/r/{SHA}/assets/panel.webp",
        "https://raw.githubusercontent.com/o/r/main/img/a.jpg",
        "https://github.com/user-attachments/assets/0f3c1d2e-aaaa-bbbb-cccc-111122223333",
        "https://user-images.githubusercontent.com/1/2.png",
        "https://cdn.example/x.gif",
    ]


def test_image_urls_relative_to_plugin_dir_and_cap():
    md = "\n".join(f"![s{i}](s{i}.png)" for i in range(12))
    urls = readme.image_urls(md, "o", "r", SHA, "plugins/a")
    assert len(urls) == readme.MAX_IMAGES
    assert urls[0] == f"https://raw.githubusercontent.com/o/r/{SHA}/plugins/a/s0.png"
    assert readme.image_urls("![x](../b.png)", "o", "r", SHA, "plugins/a") == [
        f"https://raw.githubusercontent.com/o/r/{SHA}/plugins/b.png"
    ]


# --- query ------------------------------------------------------------------------------------


def test_batch_query_shape_and_safety():
    refs = [
        query.RepoRef("o/r", "o", "r", ("plugins/a", "", "bad/../x", "b")),
        query.RepoRef("x/y", "x", "y"),
    ]
    q = query.batch_query(refs, NOW)
    assert q.count("repository(owner:") == 2
    assert 'r0: repository(owner: "o", name: "r")' in q
    assert "rateLimit { cost remaining resetAt limit }" in q
    assert 'dir0: object(expression: "HEAD:plugins/a/README.md")' in q
    assert 'dir1: object(expression: "HEAD:b/README.md")' in q
    assert "bad/" not in q
    assert 'history(since: "2026-10-02T12:00:00Z")' in q
    assert "stargazers(" not in q
    assert query.readme_dirs(refs[0]) == ["plugins/a", "b"]
    assert query.RepoRef("k", "o", 'r") { evil }').valid() is False
    assert refs[0].valid()


# --- stats ------------------------------------------------------------------------------------


def _node(**kw):
    node = {
        "stargazerCount": 42,
        "isArchived": False,
        "pushedAt": "2026-10-01T00:00:00Z",
        "defaultBranchRef": {
            "name": "main",
            "target": {
                "oid": SHA,
                "recent": {
                    "nodes": [
                        {
                            "committedDate": "2026-10-01T10:00:00Z",
                            "author": {"email": "A@x", "user": {"login": "alice"}},
                        },
                        {
                            "committedDate": "2026-09-30T10:00:00Z",
                            "author": {"email": "a@x", "user": {"login": "alice"}},
                        },
                        {"committedDate": "2026-09-29T10:00:00Z", "author": {"email": "Bob@x", "user": None}},
                        {"committedDate": "2026-09-28T10:00:00Z", "author": None},
                    ]
                },
                "h90": {"totalCount": 17},
            },
        },
        "releases": {
            "totalCount": 3,
            "nodes": [
                {"publishedAt": "2026-09-01T00:00:00Z", "tagName": "v1.1"},
                {"publishedAt": "2025-01-01T00:00:00Z", "tagName": "v0.1"},
                {"publishedAt": None, "tagName": "draft"},
            ],
        },
        "openIssues": {"totalCount": 4},
        "recentIssues": {
            "nodes": [
                {
                    "createdAt": "2026-09-01T00:00:00Z",
                    "author": {"login": "u"},
                    "comments": {
                        "nodes": [
                            {"createdAt": "2026-09-01T01:00:00Z", "author": {"login": "u"}},
                            {"createdAt": "2026-09-01T10:00:00Z", "author": {"login": "alice"}},
                        ]
                    },
                },
                {
                    "createdAt": "2026-09-02T00:00:00Z",
                    "author": {"login": "v"},
                    "comments": {
                        "nodes": [
                            {"createdAt": "2026-09-02T02:00:00Z", "author": {"login": "alice"}},
                        ]
                    },
                },
                {"createdAt": "2026-09-03T00:00:00Z", "author": {"login": "w"}, "comments": {"nodes": []}},
                {"createdAt": "bad", "author": None, "comments": None},
            ]
        },
        "readme0": None,
        "readme1": {"text": "![s](shot.png)"},
        "dir0": {"text": "![p](p.png)"},
        "dir1": {"text": "no images"},
    }
    node.update(kw)
    return node


def test_repo_stats_fields():
    s = stats.repo_stats(_node(), NOW, owner="o", name="r", dirs=["plugins/a", "plugins/b"])
    assert s["stars"] == 42
    assert s["archived"] is False
    assert (s["branch"], s["head"], s["lastCommit"], s["c90"]) == ("main", SHA, "2026-10-01T10:00:00Z", 17)
    assert (s["contrib"], s["bus"]) == (3, 1)
    assert (s["rel180"], s["releases"], s["lastRelease"], s["issues"]) == (1, 3, "v1.1", 4)
    assert s["respH"] == 6.0  # median of 10h and 2h
    assert s["images"] == [f"https://raw.githubusercontent.com/o/r/{SHA}/shot.png"]
    assert s["dirImages"] == {"plugins/a": [f"https://raw.githubusercontent.com/o/r/{SHA}/plugins/a/p.png"]}


def test_repo_stats_empty_repo_is_unknown_not_zero():
    s = stats.repo_stats({"stargazerCount": 3, "defaultBranchRef": None}, NOW, owner="o", name="r")
    assert s["stars"] == 3
    assert s["lastCommit"] is None
    assert s["c90"] is None
    assert s["contrib"] is None
    assert s["bus"] is None
    assert s["rel180"] is None
    assert s["respH"] is None
    assert s["images"] == []
    assert stats.parse_time("2026-10-01T00:00:00") == dt.datetime(2026, 10, 1, tzinfo=dt.UTC)
    assert stats.parse_time(None) is None


def test_bus_factor():
    assert stats.bus_factor([]) is None
    assert stats.bus_factor(["a", "a", "b", "c"]) == 1
    assert stats.bus_factor(["a", "b", "c", "d"]) == 2


def test_history_and_velocity():
    h = stats.add_history([["2026-09-30", 10], ["bad"]], dt.date(2026, 10, 2), 16)
    assert h == [["2026-09-30", 10], ["2026-10-02", 16]]
    assert stats.add_history(h, dt.date(2026, 10, 2), 17)[-1] == ["2026-10-02", 17]
    assert len(stats.add_history([["2026-01-01", 1]], dt.date(2026, 10, 2), 2)) == 1
    today = dt.date(2026, 10, 2)
    assert stats.velocity(h, 16, today) == (90, 2)  # 6 stars in 2 days -> 90 / 30 days
    assert stats.velocity([["2026-10-02", 16]], 16, today) == (0, 0)
    assert stats.velocity([["2026-08-01", 10], ["2026-09-01", 13]], 16, today) == (3, 31)
    assert stats.velocity([["2026-09-20", 30]], 20, today) == (0, 12)


# --- rank -------------------------------------------------------------------------------------

ITEMS = st.builds(
    rank.Item,
    id=st.text(alphabet="abcdef", min_size=1, max_size=4),
    state=st.sampled_from(["listed", "listed", "listed", "retired", "builtin"]),
    category=st.sampled_from([None, "Widgets", "System"]),
    stars=st.integers(0, 100_000),
    vel30=st.integers(0, 5000),
    last_commit=st.one_of(
        st.none(),
        st.datetimes(
            min_value=dt.datetime(2020, 1, 1), max_value=dt.datetime(2026, 10, 2), timezones=st.just(dt.UTC)
        ),
    ),
    c90=st.one_of(st.none(), st.integers(0, 1000)),
    contrib=st.one_of(st.none(), st.integers(1, 100)),
    rel180=st.one_of(st.none(), st.integers(0, 50)),
    resp_h=st.one_of(st.none(), st.floats(0, 10_000)),
    views=st.integers(0, 10**6),
    verified=st.booleans(),
    verdict=st.sampled_from(["safe", "caution", "risky", "blocked", "unknown"]),
    trusted=st.booleans(),
    listed_at=st.one_of(st.none(), st.sampled_from(["2026-07-01", "2026-09-01"])),
    updated_at=st.one_of(st.none(), st.sampled_from(["2026-08-01", "2026-09-30"])),
)


@given(st.lists(ITEMS, max_size=30, unique_by=lambda i: i.id))
def test_rank_invariants(items):
    ranked = rank.rank(items, NOW)
    by = {i.id: i for i in items}
    assert [r.rank for r in ranked] == list(range(1, len(ranked) + 1))
    assert all(rank.eligible(by[r.id]) for r in ranked)
    assert all(0 <= r.score <= rank.MAX_SCORE for r in ranked)
    assert [r.score for r in ranked] == sorted((r.score for r in ranked), reverse=True)
    for r in ranked:
        assert all(0 <= c <= f.weight + 1e-9 for c, f in zip(r.fac, rank.FACTORS, strict=True))
    shelves = rank.shelves(items, ranked)
    ranked_ids = {r.id for r in ranked}
    for ids in (
        shelves["top"],
        shelves["trending"],
        shelves["new"],
        shelves["updated"],
        shelves["safePicks"],
    ):
        assert set(ids) <= ranked_ids
        assert len(ids) <= rank.SHELF_SIZE
    for ids in shelves["byCategory"].values():
        assert set(ids) <= ranked_ids
    assert all(by[i].trusted and by[i].verdict == "safe" for i in shelves["safePicks"])


@given(ITEMS, st.integers(1, 50_000))
def test_more_stars_never_lowers_score(item, extra):
    more = dataclasses.replace(item, stars=item.stars + extra)
    assert sum(rank.contributions(more, NOW)) >= sum(rank.contributions(item, NOW))


@given(ITEMS)
def test_gates_order(item):
    def ranked(verdict, trusted):
        return rank.rank([dataclasses.replace(item, verdict=verdict, trusted=trusted, state="listed")], NOW)

    def score(verdict, trusted) -> float:
        return ranked(verdict, trusted)[0].score

    assert ranked("blocked", True) == []
    assert score("safe", True) >= score("unknown", False) >= score("risky", True)
    assert score("caution", True) == score("safe", True)


def test_factor_table_and_examples():
    assert [f["weight"] for f in rank.factor_table()] == [22, 16, 11, 11, 8, 8, 8, 11, 5]
    assert rank.MAX_SCORE == 100
    a = rank.Item(
        "a",
        stars=2099,
        vel30=400,
        last_commit=NOW,
        c90=60,
        contrib=6,
        rel180=4,
        resp_h=1,
        views=100000,
        verified=True,
        verdict="safe",
        trusted=True,
    )
    r = rank.rank([a], NOW)[0]
    assert r.score == pytest.approx(100, abs=0.01)
    assert rank.gate_state(rank.Item("x", verdict="risky")) == "unreviewed"
    b = rank.Item("b")
    assert rank.contributions(b, NOW)[6] == 8 * rank.NEUTRAL  # unknown issue response is neutral
    assert rank._clamp(float("nan")) == 0
