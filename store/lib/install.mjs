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
  // why: the store has already shown its own confirm dialog and has no terminal for the
  // checker's prompt, so it passes --yes; --enable matches the "enable" step above (ADR-0033).
  // Blocked plugins are still refused by the checker: --yes never overrides a refusal.
  return [CHECKER, "--add", "--pin", "--yes", "--enable", String(p.repo)];
}

// Re-pin an installed plugin to its reviewed commit (update or roll back, ADR-0035). The id
// must be a plain plugin id so it can never become a checker flag.
export var ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
export function pinCommand(p) {
  if (!p || !ID_RE.test(String(p.id || "")) || String(p.id).indexOf("..") !== -1) return null;
  // why: like command(): the store already confirmed in its own dialog and has no terminal.
  return [CHECKER, "pin", "--yes", String(p.id)];
}

export function pinSteps(p) {
  var repo = String(p.repo || p.id).replace("https://github.com/", "");
  return [
    "verify snapshot signature",
    "fetch " + repo,
    "compare with the reviewed commit " + (p.commit ? String(p.commit).slice(0, 7) : "(none)"),
    "check out and verify commit + tree",
    "rescan omarchy-shell",
    "log to ~/.config/omarchy/CHANGES.md"
  ];
}

export function removeCommand(p) {
  if (!p || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(String(p.id || ""))) return null;
  return ["omarchy-plugin-remove", String(p.id), "--yes"];
}

// env: {checker: bool, dev: bool, installed: bool, repin: bool}
// repin (update / roll back an installed plugin): always the store's own confirm first.
export function start(p, env) {
  var repin = !!(env && env.repin);
  var base = { state: "idle", id: p ? p.id : null, verdict: p ? p.verdict : null, repin: repin, steps: [], step: 0, log: [], code: null, reason: "" };
  if (!p) return base;
  base.steps = repin ? pinSteps(p) : steps(p);
  if (p.verdict === "blocked") return set(base, { state: "refused", reason: "blocked" });
  if (repin) {
    if (!(env.checker || env.dev)) return set(base, { state: "unavailable", reason: "checker not installed" });
    if (!pinCommand(p)) return set(base, { state: "unavailable", reason: "not installable from the store" });
    return set(base, { state: "confirm" });
  }
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
  var n = steps(p).length; // pinSteps has the same length
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

// Installed row state from one `omarchy-plugin-check status --json` entry (identity, former
// repositories, commit and tree already decided by the checker, ADR-0034/0035):
// update = a newer reviewed commit to pin; stale = HEAD is past the review (roll back);
// ok = at the reviewed commit or its tree; else the checker's state.
export function statusState(e) {
  if (!e) return "unknown";
  if (e.state === "blocked") return "blocked";
  if (e.repin === "forward") return "update";
  if (e.repin === "back") return "stale";
  if (e.commitMatch === true || e.treeMatch === true) return "ok";
  if (e.state === "unlisted" || e.state === "retired" || e.state === "stale") return e.state;
  return "unreviewed";
}

export function buttonKind(verdict) {
  return { safe: "primary", caution: "caution", risky: "risky" }[verdict] || "";
}
