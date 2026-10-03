import assert from "node:assert/strict";
import { test } from "node:test";
import * as I from "./install.mjs";

const p = (verdict, extra = {}) => ({ id: "o.p", name: "P", verdict, repo: "https://github.com/o/p", commit: "26b1fa823756f164b472c7eab0d22f102044dc35", ...extra });
const env = { checker: true, dev: false, installed: false };

test("start picks the dialog by verdict", () => {
  assert.equal(I.start(p("blocked"), env).state, "refused");
  assert.equal(I.start(p("safe"), env).state, "running");
  for (const v of ["caution", "risky", "unreviewed"]) assert.equal(I.start(p(v), env).state, "confirm", v);
});

test("blocked is refused even without a checker or with --dev", () => {
  assert.equal(I.start(p("blocked"), { checker: false, dev: true }).state, "refused");
});

test("missing checker disables install; --dev enables the fake runner", () => {
  const s = I.start(p("safe"), { checker: false, dev: false });
  assert.equal(s.state, "unavailable");
  assert.equal(s.reason, "checker not installed");
  assert.equal(I.start(p("safe"), { checker: false, dev: true }).state, "running");
});

test("already installed is a no-op; non-GitHub repos are not installable", () => {
  assert.equal(I.start(p("safe"), { ...env, installed: true }).reason, "installed");
  const s = I.start(p("safe", { repo: "" }), env);
  assert.equal(s.state, "unavailable");
  assert.equal(s.reason, "not installable from the store");
});

test("command is argv with a validated GitHub URL (no flag injection)", () => {
  assert.deepEqual(I.command(p("safe")), ["omarchy-plugin-check", "--add", "--pin", "--yes", "--enable", "https://github.com/o/p"]);
  assert.deepEqual(I.command(p("safe", { repo: "https://github.com/o/p.git" })).slice(-1), ["https://github.com/o/p.git"]);
  for (const bad of ["--force", "https://github.com/o/p --force", "http://github.com/o/p", "https://evil.example/o/p", "https://github.com/o/p/../x", "https://github.com/o"])
    assert.equal(I.command(p("safe", { repo: bad })), null, bad);
  assert.deepEqual(I.removeCommand({ id: "o.p" }), ["omarchy-plugin-remove", "o.p", "--yes"]);
  assert.equal(I.removeCommand({ id: "-rf" }), null);
});

test("confirm -> running -> progress -> done", () => {
  let s = I.start(p("caution"), env);
  s = I.reduce(s, { type: "progress", step: 3 });
  assert.equal(s.step, 0, "progress ignored before confirm");
  s = I.reduce(s, { type: "confirm" });
  assert.equal(s.state, "running");
  s = I.reduce(s, { type: "progress", step: 2 });
  s = I.reduce(s, { type: "progress", step: 1 });
  assert.equal(s.step, 2, "progress never goes back");
  s = I.reduce(s, { type: "progress", step: 99 });
  assert.equal(s.step, s.steps.length);
  s = I.reduce(s, { type: "exit", code: 0 });
  assert.equal(s.state, "done");
  assert.equal(I.reduce(s, { type: "close" }).state, "idle");
});

test("checker lines drive progress; non-zero exit fails and keeps the log tail", () => {
  let s = I.start(p("safe"), env);
  s = I.reduce(s, { type: "line", text: "[3/6] pin reviewed commit" });
  assert.equal(s.step, 3);
  for (let i = 0; i < 12; i++) s = I.reduce(s, { type: "line", text: `noise ${i}` });
  assert.equal(s.log.length, 8);
  s = I.reduce(s, { type: "exit", code: 3 });
  assert.equal(s.state, "failed");
  assert.equal(s.code, 3);
  assert.equal(I.reduce(s, { type: "confirm" }).state, "failed");
  assert.equal(I.reduce(s, { type: "bogus" }), s);
  assert.equal(I.progressFromLine("nothing"), null);
});

test("cancel from confirm goes back to idle", () => {
  assert.equal(I.reduce(I.start(p("risky"), env), { type: "cancel" }).state, "idle");
});

test("fake script replays every step then exits 0", () => {
  const script = I.fakeScript(p("safe"), 100);
  let s = I.start(p("safe"), { dev: true });
  for (const { ev } of script) s = I.reduce(s, ev);
  assert.equal(s.state, "done");
  assert.ok(script.every((x, i) => i === 0 || x.at > script[i - 1].at));
});

test("installed row state", () => {
  assert.equal(I.installState("26b1fa8", p("caution")), "ok");
  assert.equal(I.installState("8b21e07", p("caution")), "stale");
  assert.equal(I.installState("8b21e07", p("blocked")), "blocked");
  assert.equal(I.installState("8b21e07", p("unreviewed", { commit: null })), "unreviewed");
  assert.equal(I.installState("", p("safe")), "unknown");
  assert.equal(I.buttonKind("safe"), "primary");
  assert.equal(I.buttonKind("unreviewed"), "");
});

test("steps name the repo and the reviewed commit", () => {
  const st = I.steps(p("safe"));
  assert.equal(st.length, 6);
  assert.ok(st[1].includes("o/p"));
  assert.ok(st[2].includes("26b1fa8"));
});

test("repin: always the store's confirm first, then `pin --yes <id>` as argv", () => {
  const r = { ...env, repin: true };
  for (const v of ["safe", "caution", "risky", "unreviewed"]) assert.equal(I.start(p(v), r).state, "confirm", v);
  assert.equal(I.start(p("blocked"), r).state, "refused");
  assert.equal(I.start(p("safe"), { ...r, checker: false }).reason, "checker not installed");
  assert.equal(I.start(p("safe"), { ...r, installed: true }).state, "confirm"); // installed is the point
  const s = I.start(p("safe"), r);
  assert.equal(s.repin, true);
  assert.equal(s.steps.length, I.steps(p("safe")).length);
  assert.match(s.steps[1], /^fetch o\/p$/);
  assert.deepEqual(I.pinCommand(p("safe")), ["omarchy-plugin-check", "pin", "--yes", "o.p"]);
  for (const id of ["--force", "../x", "a..b", "", "a b"]) assert.equal(I.pinCommand(p("safe", { id })), null, id);
  assert.equal(I.start(p("safe", { id: "--yes" }), r).state, "unavailable");
});

test("statusState maps a checker status entry to the installed row state", () => {
  assert.equal(I.statusState(null), "unknown");
  assert.equal(I.statusState({ state: "blocked", repin: null }), "blocked");
  assert.equal(I.statusState({ state: "stale", repin: "forward" }), "update");
  assert.equal(I.statusState({ state: "stale", repin: "back" }), "stale");
  assert.equal(I.statusState({ state: "safe", commitMatch: true }), "ok");
  assert.equal(I.statusState({ state: "caution", commitMatch: false, treeMatch: true }), "ok");
  assert.equal(I.statusState({ state: "unlisted" }), "unlisted");
  assert.equal(I.statusState({ state: "retired" }), "retired");
  assert.equal(I.statusState({ state: "stale", repin: null }), "stale");
  assert.equal(I.statusState({ state: "unreviewed" }), "unreviewed");
});

test("the checker is found next to the store, by absolute path (ADR-0042)", () => {
  const c = I.checkerCandidates("/home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/store");
  assert.deepEqual(c, [
    "/home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/bin/omarchy-plugin-check",
    "/home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/plugin/bin/omarchy-plugin-check"
  ]);
  assert.deepEqual(I.checkerCandidates("file:///w/repo/store/"), ["/w/repo/bin/omarchy-plugin-check", "/w/repo/plugin/bin/omarchy-plugin-check"]);
  assert.deepEqual(I.checkerCandidates("/home/my dir/store"), []);
  assert.deepEqual(I.checkerCandidates(""), []);
  const argv = I.probeArgv(c.concat(["/x/$(id)"]));
  assert.deepEqual(argv.slice(0, 2), ["sh", "-c"]);
  assert.deepEqual(argv.slice(3), ["sh"].concat(c));
  assert.equal(I.checkerPath(c[0] + "\n"), c[0]);
  assert.equal(I.checkerPath("/usr/bin/omarchy-plugin-check"), "/usr/bin/omarchy-plugin-check");
  assert.equal(I.checkerPath(""), "");
  assert.equal(I.checkerPath("/x/../bin/omarchy-plugin-check"), "");
  assert.equal(I.checkerPath("/x/evil"), "");
  const repo = { id: "a.b", repo: "https://github.com/a/b", verdict: "safe" };
  assert.deepEqual(I.command(repo, c[0]), [c[0], "--add", "--pin", "--yes", "--enable", "https://github.com/a/b"]);
  assert.deepEqual(I.pinCommand(repo, c[0]), [c[0], "pin", "--yes", "a.b"]);
  assert.equal(I.command(repo, "rm -rf")[0], "omarchy-plugin-check");
});
