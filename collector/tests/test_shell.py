import datetime as dt
import io
import json
import re
import shutil
import subprocess
import urllib.error
import urllib.request
from email.message import Message
from typing import Any

import pytest
from opc_spec import marketplace

from opc_collector import cli, github, inputs, net, sync
from opc_collector.ports import RateLimitedError, Response, TransientError
from opc_collector.query import RepoRef

NOW = dt.datetime(2026, 10, 2, 12, 0, tzinfo=dt.UTC)
SHA = "b" * 40


def node(stars=5):
    return {
        "stargazerCount": stars,
        "isArchived": False,
        "defaultBranchRef": {
            "name": "main",
            "target": {"oid": SHA, "recent": {"nodes": []}, "h90": {"totalCount": 0}},
        },
        "releases": {"totalCount": 0, "nodes": []},
        "openIssues": {"totalCount": 0},
        "recentIssues": {"nodes": []},
        "readme0": {"text": "![a](a.png)"},
    }


class FakeGQL:
    """Answers per alias from `repos` (owner/name → node or 'missing'); scripted failures first."""

    def __init__(self, repos, failures=(), remaining=4000, reset: str | None = "2026-10-02T12:10:00Z"):
        self.repos, self.failures, self.remaining, self.reset = repos, list(failures), remaining, reset
        self.queries = []

    def query(self, text):
        self.queries.append(text)
        if self.failures:
            f = self.failures.pop(0)
            if isinstance(f, Exception):
                raise f
            return f
        data: dict[str, Any] = {
            "rateLimit": {"cost": 1, "remaining": self.remaining, "resetAt": self.reset, "limit": 5000}
        }
        errors = []
        for alias, owner, name in re.findall(
            r'(r\d+): repository\(owner: "([^"]+)", name: "([^"]+)"\)', text
        ):
            v = self.repos.get(f"{owner}/{name}")
            if v == "missing":
                data[alias] = None
                errors.append({"type": "NOT_FOUND", "path": [alias], "message": "nope"})
            elif v is None:
                data[alias] = None
            else:
                data[alias] = v
        return {"data": data, "errors": errors} if errors else {"data": data}


def refs(n):
    return [RepoRef(f"o/r{i}", "o", f"r{i}") for i in range(n)]


def make(tmp_path, client, **opts):
    sleeps = []
    clock = {"now": NOW}
    coll = github.Collector(
        client,
        github.Cache(tmp_path),
        github.Options(pause=0, **opts),
        now=lambda: clock["now"],
        sleep=sleeps.append,
    )
    return coll, sleeps, clock


def test_collect_batches_cache_and_resume(tmp_path):
    repos = {f"o/r{i}": node(i) for i in range(5)} | {"o/r3": "missing", "o/r4": None}
    client = FakeGQL(repos)
    coll, _, _ = make(tmp_path, client, batch_size=2)
    seeds = {"o/r1": [(dt.date(2026, 9, 30), 0)]}
    rep = coll.run([*refs(5), RepoRef("bad", "o", 'x"y')], seeds)
    assert (rep.fetched, rep.missing, rep.failed, rep.queries, rep.points) == (3, 1, 2, 3, 3)
    assert rep.remaining == 4000
    cache = github.Cache(tmp_path)
    rec = cache.load(refs(5)[1]) or {}
    assert rec["history"] == [["2026-09-30", 0], ["2026-10-02", 1]]
    assert rec["stats"]["images"] == [f"https://raw.githubusercontent.com/o/r1/{SHA}/a.png"]
    assert (cache.load(refs(5)[3]) or {})["missing"] is True
    # resume: everything fetched is fresh; only the failed r4 is retried
    rep2 = coll.run(refs(5), {})
    assert (rep2.fresh, rep2.fetched, rep2.failed) == (4, 0, 1)
    assert len(client.queries) == 4
    out = github.stats_repos(refs(5), cache, dt.date(2026, 10, 2))
    assert set(out) == {"o/r0", "o/r1", "o/r2"}
    assert (out["o/r1"]["vel30"], out["o/r1"]["velDays"]) == (15, 2)
    (tmp_path / "github" / "o__r0.json").write_text("{not json")
    assert cache.load(refs(1)[0]) is None


def test_transient_errors_halve_then_skip(tmp_path):
    client = FakeGQL(
        {f"o/r{i}": node() for i in range(4)},
        failures=[
            TransientError("502"),
            TransientError("502"),
            {"errors": [{"message": "boom"}]},
            TransientError("502"),
        ],
    )
    coll, _, _ = make(tmp_path, client, batch_size=4)
    rep = coll.run(refs(4), {})
    # 4 -> 2 -> 1; r0 gets no data at size 1 (skipped), r1 a 502 at size 1 (skipped); r2, r3 succeed
    assert rep.failed == 2
    assert rep.fetched == 2
    assert rep.errors == ["o/r0: query failed", "o/r1: 502"]


def test_rate_limit_waits_or_stops(tmp_path):
    client = FakeGQL({"o/r0": node()}, failures=[RateLimitedError(30)])
    coll, sleeps, _ = make(tmp_path, client)
    assert coll.run(refs(1), {}).fetched == 1
    assert sleeps[0] == 30
    client = FakeGQL({"o/r0": node()}, failures=[RateLimitedError(5000)])
    coll, _, _ = make(tmp_path / "b", client)
    rep = coll.run(refs(1), {})
    assert (rep.stopped or "").startswith("rate limited")
    # budget: few points left, reset soon -> sleep; reset far -> stop
    client = FakeGQL({f"o/r{i}": node() for i in range(3)}, remaining=50, reset="2026-10-02T12:05:00Z")
    coll, sleeps, _ = make(tmp_path / "c", client, batch_size=1)
    assert coll.run(refs(2), {}).fetched == 2
    assert sleeps[0] == pytest.approx(305)
    client = FakeGQL({f"o/r{i}": node() for i in range(3)}, remaining=50, reset="2026-10-02T20:00:00Z")
    coll, _, _ = make(tmp_path / "d", client, batch_size=1)
    rep = coll.run(refs(3), {})
    assert (rep.fetched, rep.stopped is not None) == (1, True)
    client = FakeGQL({"o/r0": node()}, remaining=50, reset=None)
    coll, _, _ = make(tmp_path / "e", client, batch_size=1, max_repos=1)
    assert coll.run(refs(2), {}).stopped is not None


def test_inputs_refs_seeds_items():
    cat = {
        "generatedAt": "2026-09-30T00:00:00Z",
        "plugins": [
            {
                "id": "a",
                "repo": "https://github.com/O/R",
                "stars": 7,
                "category": "Widgets",
                "verificationStatus": "verified",
                "listedAt": "2026-09-01",
            },
            {"id": "b", "repo": "https://github.com/o/r", "manifestPath": "p/b/manifest.json", "stars": 9},
            {"id": "c", "repo": "https://gitlab.com/x/y"},
            {"id": "d", "repo": "https://github.com/z/z", "builtIn": True},
            {"id": "e", "stars": 1},
        ],
    }
    m = marketplace.parse(cat, None)
    r = inputs.repo_refs(m)
    assert r == [RepoRef("o/r", "O", "R", ("p/b",))]
    seeds = inputs.seeds(
        [
            cat,
            {"plugins": []},
            {
                "generatedAt": "2026-10-01T00:00:00Z",
                "plugins": [{"repo": "https://github.com/o/r", "stars": 3}],
            },
        ]
    )
    assert seeds["o/r"] == [(dt.date(2026, 9, 30), 9), (dt.date(2026, 10, 1), 3)]
    index = {"plugins": [{"id": "a", "verdict": "caution", "basis": "trusted"}]}
    items = {
        i.id: i
        for i in inputs.items(
            m, {"o/r": {"stars": 11, "vel30": 2, "respH": 3.5, "c90": 4}}, {"a": {"views": 9}}, index
        )
    }
    a = items["a"]
    assert (a.stars, a.vel30, a.resp_h, a.views, a.verified, a.verdict, a.trusted) == (
        11,
        2,
        3.5,
        9,
        True,
        "caution",
        True,
    )
    assert items["c"].stars == 0
    assert items["d"].state == "builtin"
    assert items["b"].verdict == "unknown"


class FakeHttp:
    def __init__(self, bodies):
        self.bodies = bodies
        self.calls = []

    def get(self, url, etag=None, last_modified=None):
        self.calls.append((url, etag))
        if etag and etag == "e1":
            return Response(304, None, etag, last_modified)
        return Response(200, self.bodies[url], "e1", "lm")


def test_sync_conditional_and_engagement(tmp_path):
    body = json.dumps(
        {"schemaVersion": 1, "plugins": {"a": {"views": 3, "copies": -1, "hearts": "x"}}}
    ).encode()
    http = FakeHttp(
        {sync.ENGAGEMENT_URL: body, "https://x/c.json": b'{"plugins": []}', "https://x/bad": b"<html>"}
    )
    f1 = sync.fetch_cached(http, "https://x/c.json", tmp_path / "m" / "c.json")
    f2 = sync.fetch_cached(http, "https://x/c.json", tmp_path / "m" / "c.json")
    assert (f1.downloaded, f2.downloaded) == (True, False)
    assert http.calls[-1] == ("https://x/c.json", "e1")
    with pytest.raises(ValueError, match="Expecting value"):
        sync.fetch_cached(http, "https://x/bad", tmp_path / "bad.json")
    eng, at = sync.engagement(http, tmp_path, NOW)
    assert eng == {"a": {"views": 3, "copies": 0, "hearts": 0}}
    assert at is not None
    n = len(http.calls)
    sync.engagement(http, tmp_path, dt.datetime.fromisoformat(at))
    assert len(http.calls) == n  # fresh: no request
    cat = {
        "generatedAt": "g",
        "plugins": [{"id": "a", "repo": "https://github.com/o/r"}, {"id": "b", "builtIn": True}],
    }
    s = sync.summary(cat, {"retiredPluginIds": ["z"]})
    assert (s["plugins"], s["listed"], s["builtin"], s["retiredIds"], s["repos"]) == (2, 1, 1, 1, 1)


# --- network adapters (urllib patched) ---------------------------------------------------------


class _Resp:
    def __init__(self, body, status=200, headers=None):
        self.body, self.status, self.headers = body, status, headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, n):
        return self.body


def _http_error(code, retry=None):
    h = Message()
    if retry:
        h["Retry-After"] = retry
    return urllib.error.HTTPError("https://api.github.com/graphql", code, "x", h, io.BytesIO(b""))


def test_gh_graphql_adapter(monkeypatch):
    seen = {}

    def ok(req, timeout):
        seen["auth"] = req.headers["Authorization"]
        return _Resp(b'{"data": {}}')

    monkeypatch.setattr(urllib.request, "urlopen", ok)
    assert net.GhGraphQL("tok").query("query { x }") == {"data": {}}
    assert seen["auth"] == "bearer tok"
    for exc, kind in [
        (_http_error(403, "7"), RateLimitedError),
        (_http_error(429, "zz"), RateLimitedError),
        (_http_error(502), TransientError),
        (TimeoutError("slow"), TransientError),
    ]:

        def boom(req, timeout, exc=exc):
            raise exc

        monkeypatch.setattr(urllib.request, "urlopen", boom)
        with pytest.raises(kind):
            net.GhGraphQL("tok").query("q")
    monkeypatch.setattr(urllib.request, "urlopen", lambda req, timeout: _Resp(b"<html>"))
    with pytest.raises(TransientError, match="invalid JSON"):
        net.GhGraphQL("tok").query("q")
    assert net._retry_after(_http_error(403)) == 60.0
    assert net._retry_after(_http_error(403, "7")) == 7.0


def test_urllib_http_adapter(monkeypatch):
    monkeypatch.setattr(urllib.request, "urlopen", lambda req, timeout: _Resp(b"{}", 200, {"ETag": "e"}))
    r = net.UrllibHttp().get("https://x/y", "e0", "lm")
    assert (r.status, r.body, r.etag) == (200, b"{}", "e")
    with pytest.raises(TransientError, match="non-https"):
        net.UrllibHttp().get("http://x/y")

    def not_modified(req, timeout):
        raise _http_error(304)

    monkeypatch.setattr(urllib.request, "urlopen", not_modified)
    assert net.UrllibHttp().get("https://x/y", "e0").body is None

    def gone(req, timeout):
        raise _http_error(404)

    monkeypatch.setattr(urllib.request, "urlopen", gone)
    with pytest.raises(TransientError, match="404"):
        net.UrllibHttp().get("https://x/y")

    def down(req, timeout):
        raise OSError("down")

    monkeypatch.setattr(urllib.request, "urlopen", down)
    with pytest.raises(TransientError, match="down"):
        net.UrllibHttp().get("https://x/y")


def test_gh_token(monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    with pytest.raises(net.TokenError, match="not found"):
        net.gh_token()
    monkeypatch.setattr(shutil, "which", lambda name: "/usr/bin/gh")
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a, 0, "tok\n", ""))
    assert net.gh_token() == "tok"
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a, 1, "", "no"))
    with pytest.raises(net.TokenError):
        net.gh_token()


# --- cli ---------------------------------------------------------------------------------------


def test_cli_flow(tmp_path, monkeypatch, capsys):
    cache = tmp_path / "cache"
    cat = {
        "generatedAt": "2026-09-30T00:00:00Z",
        "plugins": [
            {
                "id": "a",
                "repo": "https://github.com/o/r0",
                "stars": 1,
                "category": "Widgets",
                "listedAt": "2026-09-01",
            },
            {"id": "b", "repo": "https://github.com/o/r1", "stars": 2, "category": "Widgets"},
        ],
    }
    bodies = {
        sync.CATALOG_URL: json.dumps(cat).encode(),
        sync.REGISTRY_URL: b'{"retiredPluginIds": []}',
        sync.ENGAGEMENT_URL: b'{"plugins": {"a": {"views": 10, "copies": 1, "hearts": 1}}}',
    }
    monkeypatch.setattr(cli, "UrllibHttp", lambda: FakeHttp(bodies))
    assert cli.main(["--cache", str(cache), "sync"]) == 0
    assert json.loads(capsys.readouterr().out)["plugins"] == 2
    monkeypatch.setattr(cli, "gh_token", lambda: "tok")
    monkeypatch.setattr(cli, "GhGraphQL", lambda token: FakeGQL({"o/r0": node(3), "o/r1": node(9)}))
    old = tmp_path / "old.json"
    old.write_text(json.dumps(cat))
    assert cli.main(["--cache", str(cache), "github", "--pause", "0", "--seed-catalog", str(old)]) == 0
    assert json.loads(capsys.readouterr().out)["fetched"] == 2
    assert cli.main(["--cache", str(cache), "github", "--pause", "0", "--repo", "o/r1"]) == 0
    assert json.loads(capsys.readouterr().out)["fetched"] == 1  # fresh, but asked for explicitly
    assert cli.main(["--cache", str(cache), "stats", "--out", str(tmp_path / "stats.json")]) == 0
    st = json.loads((tmp_path / "stats.json").read_text())
    assert st["repos"]["o/r0"]["stars"] == 3
    assert st["engagement"]["a"]["views"] == 10
    index = tmp_path / "index.json"
    index.write_text(json.dumps({"plugins": [{"id": "b", "verdict": "blocked", "basis": "trusted"}]}))
    capsys.readouterr()
    assert (
        cli.main(
            [
                "--cache",
                str(cache),
                "rank",
                "--stats",
                str(tmp_path / "stats.json"),
                "--api-index",
                str(index),
                "--out",
                str(tmp_path / "ranking.json"),
            ]
        )
        == 0
    )
    rk = json.loads((tmp_path / "ranking.json").read_text())
    assert list(rk["plugins"]) == ["a"]
    assert rk["shelves"]["top"] == ["a"]
    assert (
        cli.main(["--cache", str(cache), "stats", "--no-engagement", "--out", str(tmp_path / "s2.json")]) == 0
    )

    def failing():
        raise TransientError("offline")

    monkeypatch.setattr(cli, "UrllibHttp", failing)
    assert cli.main(["--cache", str(cache), "stats", "--out", str(tmp_path / "s3.json")]) == 0
    assert "engagement skipped" in capsys.readouterr().err
    assert cli.main(["--cache", str(tmp_path / "empty"), "rank", "--stats", "x", "--out", "y"]) == 2
    monkeypatch.setattr(cli, "GhGraphQL", lambda token: FakeGQL({}, failures=[RateLimitedError(99999)]))
    assert cli.main(["--cache", str(cache), "github", "--ttl-hours", "0"]) == 3
