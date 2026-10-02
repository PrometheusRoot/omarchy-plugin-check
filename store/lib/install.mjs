// Install flow state machine (mockup dialogs: refused / confirm / progress / done) and the
// exact argv the store hands to the checker. Pure: Installer.qml owns the Process/Timer.
//
//   idle --start--> refused      (blocked: --force is never offered)
//                   unavailable  (checker missing / not installable)
//                   confirm      (caution, risky, unreviewed) --confirm--> running
//                   running      (safe)
//   running --progress(k)--> running --exit(0)--> done | --exit(!0)--> failed
//   any --close/cancel--> idle

export var CHECKER = "omarchy-plugin-check";
export var REPO_RE = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+?(\.git)?$/;

export function steps(p) {
  var repo = String(p.repo || p.id).replace("https://github.com/", "");
  return [
    "verify snapshot signature",
    "clone " + repo,
    "pin reviewed commit " + (p.commit ? String(p.commit).slice(0, 7) : "(none)"),
    "validate manifest",
    "enable in omarchy-shell",
    "log to ~/.config/omarchy/CHANGES.md"
  ];
}

// argv only, never a shell string. A repo that is not a plain GitHub URL is refused so a
// snapshot value can never turn into a checker flag (e.g. "--force").
export function command(p) {
  if (!p || !REPO_RE.test(String(p.repo || ""))) return null;
  return [CHECKER, "--add", "--pin", String(p.repo)];
}

export function removeCommand(p) {
  if (!p || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(String(p.id || ""))) return null;
  return ["omarchy-plugin-remove", String(p.id), "--yes"];
}

// env: {checker: bool, dev: bool, installed: bool}
export function start(p, env) {
  var base = { state: "idle", id: p ? p.id : null, verdict: p ? p.verdict : null, steps: [], step: 0, log: [], code: null, reason: "" };
  if (!p) return base;
  base.steps = steps(p);
  if (p.verdict === "blocked") return set(base, { state: "refused", reason: "blocked" });
  if (env && env.installed) return set(base, { state: "idle", reason: "installed" });
  if (!(env && (env.checker || env.dev))) return set(base, { state: "unavailable", reason: "checker not installed" });
  if (!command(p)) return set(base, { state: "unavailable", reason: "not installable from the store" });
  if (p.verdict === "safe") return set(base, { state: "running" });
  return set(base, { state: "confirm" });
}

export function set(s, patch) {
  var out = {};
  for (var k in s) out[k] = s[k];
  for (var j in patch) out[j] = patch[j];
  return out;
}

// Checker progress lines "[k/n] text" advance the step list; anything else is log.
export function progressFromLine(line) {
  var m = String(line).match(/^\s*\[(\d+)\/(\d+)\]/);
  return m ? Number(m[1]) : null;
}

export function reduce(s, ev) {
  if (!s || !ev) return s;
  switch (ev.type) {
    case "confirm":
      return s.state === "confirm" ? set(s, { state: "running", step: 0 }) : s;
    case "cancel":
    case "close":
      return set(s, { state: "idle" });
    case "progress":
      return s.state === "running" ? set(s, { step: Math.max(s.step, Math.min(ev.step, s.steps.length)) }) : s;
    case "line": {
      if (s.state !== "running") return s;
      var k = progressFromLine(ev.text);
      var log = s.log.concat([String(ev.text)]).slice(-8);
      return set(s, { log: log, step: k === null ? s.step : Math.max(s.step, Math.min(k, s.steps.length)) });
    }
    case "exit":
      if (s.state !== "running") return s;
      return ev.code === 0 ? set(s, { state: "done", step: s.steps.length, code: 0 }) : set(s, { state: "failed", code: ev.code });
    default:
      return s;
  }
}

// The dev runner replays this: one progress event per step, then exit 0.
export function fakeScript(p, stepMs) {
  var n = steps(p).length;
  var out = [];
  for (var k = 1; k <= n; k++) out.push({ at: k * stepMs, ev: { type: "progress", step: k } });
  out.push({ at: (n + 1) * stepMs, ev: { type: "exit", code: 0 } });
  return out;
}

// Installed row state from the installed HEAD and the reviewed commit.
// ok = HEAD is the reviewed commit; stale = HEAD differs (no verdict for the running code);
// unreviewed = nothing reviewed; blocked overrides all.
export function installState(sha, p) {
  if (p && p.verdict === "blocked") return "blocked";
  if (!p || !p.commit) return "unreviewed";
  if (!sha) return "unknown";
  return sha === p.commit || String(p.commit).indexOf(sha) === 0 ? "ok" : "stale";
}

export function buttonKind(verdict) {
  return { safe: "primary", caution: "caution", risky: "risky" }[verdict] || "";
}
