// First run and snapshot refresh (ADR-0042): the store verifies its bundle; when there is none
// yet, or it no longer verifies (expired, rolled back, damaged), it runs the bundled checker's
// `update` once (fetch + verify the signed snapshot with the shipped key) and verifies again.
// Failures become a friendly title + one line + a retry button; never a stack trace.
// Pure: Store.qml owns the processes and feeds their exits in as events.
//
//   verifying --verified(0)--> ready
//             --verified(!0), checker unknown--> waiting --checker(found)--> updating | failed
//             --verified(!0), checker found, not yet updated--> updating
//             --verified(!0), otherwise--> failed
//   updating  --updated(0)--> verifying (updated) --updated(!0)--> failed
//   failed    --retry--> updating (checker) | verifying

export function start(env) {
  env = env || {};
  var s = { state: env.dev ? "ready" : "verifying", updated: false, checker: null, auto: env.autoUpdate !== false, err: "", phase: "" };
  return s;
}

function set(s, patch) {
  var out = {};
  for (var k in s) out[k] = s[k];
  for (var j in patch) out[j] = patch[j];
  return out;
}

function afterFailedVerify(s) {
  if (s.updated || !s.auto) return set(s, { state: "failed", phase: "verify" });
  if (s.checker === null) return set(s, { state: "waiting" });
  if (s.checker) return set(s, { state: "updating" });
  return set(s, { state: "failed", phase: "checker" });
}

export function reduce(s, ev) {
  if (!s || !ev) return s;
  switch (ev.type) {
    case "checker": {
      var t = set(s, { checker: !!ev.found });
      return s.state === "waiting" ? afterFailedVerify(t) : t;
    }
    case "verified":
      if (s.state !== "verifying") return s;
      if (ev.code === 0) return set(s, { state: "ready", err: "" });
      return afterFailedVerify(set(s, { err: String(ev.err || ""), missing: ev.code === 3 }));
    case "updated":
      if (s.state !== "updating") return s;
      if (ev.code === 0) return set(s, { state: "verifying", updated: true, err: "" });
      return set(s, { state: "failed", phase: "update", err: String(ev.err || "") });
    case "retry":
      if (s.state !== "failed") return s;
      return s.checker ? set(s, { state: "updating", updated: false, err: "" }) : set(s, { state: "verifying", updated: false, err: "" });
    default:
      return s;
  }
}

// The last line a tool printed, without its "tool: " prefixes; never more than one line.
export function reason(err) {
  var lines = String(err || "").split("\n").map(function (l) { return l.trim(); }).filter(function (l) {
    return l !== "" && !/^at\s/.test(l) && !/^\s*[✓!]\s/.test(l);
  });
  var l = lines.length ? lines[lines.length - 1] : "";
  l = l.replace(/^(omarchy-plugin-check|store-verify|omarchy-plugin-store-verify):\s*/, "").replace(/^snapshot rejected:\s*/, "");
  l = l.replace(/\s*\(kept the last accepted one\)$/, "");
  return l.length > 160 ? l.slice(0, 157) + "…" : l;
}

// What the home tab shows while there is no catalog: {title, detail, busy, retry}.
export function view(s) {
  if (!s) return { title: "", detail: "", busy: false, retry: false };
  if (s.state === "verifying" || s.state === "waiting")
    return { title: s.updated ? "verifying the new snapshot…" : "verifying…", detail: "checking the snapshot signature (ssh-keygen) and every file's sha256", busy: true, retry: false };
  if (s.state === "updating")
    return { title: s.missing ? "getting the plugin catalog…" : "refreshing the plugin catalog…", detail: "downloading the signed snapshot and verifying it with the key shipped in this plugin", busy: true, retry: false };
  if (s.state !== "failed") return { title: "", detail: "", busy: false, retry: false };
  var r = reason(s.err);
  if (s.phase === "checker")
    return { title: "the checker is missing", detail: "omarchy-plugin-check should sit next to the store (bin/); reinstall omarchy-store", busy: false, retry: true };
  if (/could not fetch|resolve|timed out|connect|network|curl/i.test(r))
    return { title: "can't reach the snapshot server", detail: "check your connection, then retry" + (r ? " · " + r : ""), busy: false, retry: true };
  if (/expired/i.test(r))
    return { title: "the snapshot has expired", detail: "no newer one could be verified yet; retry later · " + r, busy: false, retry: true };
  if (/signature|sha256|does not match|differs|rollback|manifest|signing key|not a /i.test(r))
    return { title: "the snapshot did not verify", detail: "nothing from it was used · " + r, busy: false, retry: true };
  return { title: "couldn't load the plugin catalog", detail: r || "the checker exited without saying why", busy: false, retry: true };
}

// argv for the bundled checker's update (no PATH dependency; the path was validated by
// install.mjs checkerPath).
export function updateArgv(bin) {
  return typeof bin === "string" && /^\/[A-Za-z0-9_./-]+$/.test(bin) ? [bin, "update"] : null;
}
