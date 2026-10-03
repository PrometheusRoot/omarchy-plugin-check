// Opt-in extras from the status tab (ADR-0042): an Omarchy menu entry, a store keybind and the
// `omarchy-plugin-check` / `omarchy-store` terminal commands, through the checker's own
// `setup` (one plan feeds the dialog and the apply, so the dialog lists exactly what changes).
// Pure: Extras.qml owns the processes.
//
//   idle --open(undo?)--> planning --plan(pending)--> confirm --confirm--> running --exit(0)--> done
//                                  --plan(nothing)--> nothing                      --exit(!0)--> failed
//   any --close--> idle

var BIN_RE = /^\/[A-Za-z0-9_./-]+$/;

export function planArgv(bin, undo) {
  if (typeof bin !== "string" || !BIN_RE.test(bin)) return null;
  return undo ? [bin, "setup", "--uninstall", "--plan", "--json"] : [bin, "setup", "--plan", "--json"];
}

// why: the store showed the plan in its own confirm dialog and has no terminal for setup's
// prompt, so it passes --yes; setup recomputes the same plan from the same facts.
export function applyArgv(bin, undo) {
  if (typeof bin !== "string" || !BIN_RE.test(bin)) return null;
  return undo ? [bin, "setup", "--uninstall", "--yes", "--json"] : [bin, "setup", "--yes", "--json"];
}

var SIGN = { create: "+", edit: "+", replace: "~", remove: "−", keep: "=", skip: "·" };

// `setup --plan --json` stdout -> {ok, pending, keybind, changes: [{what, action, sign, text}], error}
export function parsePlan(text) {
  try {
    var p = JSON.parse(String(text || "").trim().split("\n").pop());
    if (!p || !Array.isArray(p.changes)) throw new Error("no changes");
    return {
      ok: true,
      pending: p.pending === true,
      keybind: typeof p.keybind === "string" ? p.keybind : "",
      changes: p.changes.map(function (c) {
        return { what: String(c.what || ""), action: String(c.action || ""), sign: SIGN[c.action] || "·", text: String(c.text || "") };
      }),
      error: ""
    };
  } catch (e) {
    return { ok: false, pending: false, keybind: "", changes: [], error: "could not read the setup plan" };
  }
}

// What is in place now, from the add plan (keep = present) for the status box.
export function summary(plan) {
  var has = function (what) {
    return !!plan && plan.ok && plan.changes.some(function (c) { return c.what === what && c.action === "keep"; });
  };
  var links = plan && plan.ok ? plan.changes.filter(function (c) { return c.what === "link"; }) : [];
  return {
    known: !!plan && plan.ok,
    menu: has("menu"),
    keybind: has("keybind") ? plan.keybind : "",
    command: links.length > 0 && links.every(function (c) { return c.action === "keep"; }),
    all: !!plan && plan.ok && !plan.pending
  };
}

export function start(undo) {
  return { state: "planning", undo: !!undo, plan: null, log: [], code: null };
}

export function idle() {
  return { state: "idle", undo: false, plan: null, log: [], code: null };
}

function set(s, patch) {
  var out = {};
  for (var k in s) out[k] = s[k];
  for (var j in patch) out[j] = patch[j];
  return out;
}

export function reduce(s, ev) {
  if (!s || !ev) return s;
  switch (ev.type) {
    case "plan": {
      if (s.state !== "planning") return s;
      var plan = parsePlan(ev.text);
      if (!plan.ok) return set(s, { state: "failed", plan: plan, log: [plan.error] });
      return set(s, { state: plan.pending ? "confirm" : "nothing", plan: plan });
    }
    case "confirm":
      return s.state === "confirm" ? set(s, { state: "running" }) : s;
    case "line":
      return s.state === "running" ? set(s, { log: s.log.concat([String(ev.text)]).slice(-6) }) : s;
    case "exit":
      if (s.state !== "running") return s;
      return set(s, { state: ev.code === 0 ? "done" : "failed", code: ev.code });
    case "close":
      return s.state === "running" ? s : idle();
    default:
      return s;
  }
}
