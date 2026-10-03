# The plan of `omarchy-plugin-check setup [--uninstall]`: what would change, item by item,
# from the facts the CLI gathered (links, menu, keybind). Pure; the CLI applies from the same
# facts, so the plan the store shows in its confirm dialog is exactly what happens.
#   jq -L lib -f lib/setup.jq FACTS.json
# Output: {mode, pending, keybind, changes: [{what, action, path, text}]}; action is one of
# create replace edit remove keep skip.

def tilde($home): if startswith($home + "/") then "~" + ltrimstr($home) else . end;

.home as $home
| .mode as $mode
| [
    (.links[] | (.path | tilde($home)) as $p | (.target | tilde($home)) as $t
      | if $mode == "add" then
          if .state == "ours" then {what: "link", action: "keep", path: .path, text: "\($p) already links to \($t)"}
          elif .state == "foreign" then {what: "link", action: "replace", path: .path, text: "link \($p) → \($t) (the existing file is kept as \($p).bak.<time>)"}
          else {what: "link", action: "create", path: .path, text: "link \($p) → \($t)"} end
        elif .state == "ours" then {what: "link", action: "remove", path: .path, text: "remove the link \($p)"}
        else {what: "link", action: "skip", path: .path, text: "\($p) is not ours; left alone"} end),
    (.menu | (.path | tilde($home)) as $p
      | if .change | not then {what: "menu", action: "keep", path: .path, text: "menu \($p) already \(if $mode == "add" then "has" else "lacks" end) our entries"}
        elif $mode == "add" then {what: "menu", action: "edit", path: .path, text: "menu \($p): add \(.labels | join(", ")) (backup kept)"}
        else {what: "menu", action: "edit", path: .path, text: "menu \($p): remove our entries (backup kept)"} end),
    (.keybind | (.path | tilde($home)) as $p
      | ([.taken[] | "\(.key) is taken (\(.by))"] | join(", ")) as $taken
      | if .path == "" then {what: "keybind", action: "skip", path: "", text: "keybind: no ~/.config/hypr/bindings.lua or bindings.conf; bind omarchy-store yourself"}
        elif .reason != "" then {what: "keybind", action: "skip", path: .path, text: "keybind: \(.reason)"}
        elif $mode == "add" and .key == null then {what: "keybind", action: "skip", path: .path, text: "keybind: every candidate is taken (\($taken)); bind omarchy-store yourself"}
        elif .change | not then
          if $mode == "add" then {what: "keybind", action: "keep", path: .path, text: "keybind \(.key) → omarchy-store already in \($p)"}
          else {what: "keybind", action: "keep", path: .path, text: "keybind: none of ours in \($p)"} end
        elif $mode == "remove" then {what: "keybind", action: "remove", path: .path, text: "keybind \(.current) → omarchy-store: remove from \($p) (backup kept)"}
        else {what: "keybind", action: "edit", path: .path,
          # why: jq 1.7 takes only a term as an object value, so the sum is parenthesized
          text: ("keybind \(.key) → omarchy-store in \($p) (backup kept)"
            + (if $taken != "" then "; \($taken)" else "" end)
            + (if .checked then "" else "; Hyprland not running, conflicts not checked" end))} end)
  ] as $changes
| {mode: $mode, pending: ($changes | any(.action | IN("keep", "skip") | not)),
   keybind: (if .keybind.current != "" then .keybind.current else .keybind.key // "" end), changes: $changes}
