# Pick the store's keybind: the key our managed block already uses, else the first candidate
# no other binding holds. Pure; input: `hyprctl binds -j` (an array) or null when Hyprland
# could not be asked (then nothing is known to be taken). Read-only: nothing here binds.
#   jq -L lib --arg current "SUPER + SHIFT + S"|"" -f lib/keybind.jq BINDS.json
# Output: {key (null when every candidate is taken), keep, checked, taken: [{key, by}]}

def candidates: ["SUPER + SHIFT + S", "SUPER + SHIFT + ALT + S", "SUPER + CTRL + SHIFT + S", "SUPER + CTRL + ALT + S"];
def modbit: {SUPER: 64, SHIFT: 1, CTRL: 4, CONTROL: 4, ALT: 8}[.] // 0;
def strip: sub("^\\s+"; "") | sub("\\s+$"; "");

# "SUPER + SHIFT + S" -> {mask: 65, key: "S"}
def combo: split("+") | map(strip | ascii_upcase) | {mask: (.[:-1] | map(modbit) | add // 0), key: .[-1]};

# Who holds this combo (top-level submap, not our own entry), or null.
def holder($binds; $k):
  ($k | combo) as $c
  | [$binds[]? | select(.modmask == $c.mask and ((.key // "") | ascii_upcase) == $c.key
      and ((.submap // "") == "") and .description != "omarchy-store")] | first
  | if . == null then null
    else [.description, .dispatcher] | map(select(type == "string" and . != "")) | first // "another binding" end;

. as $binds
| ($binds | type == "array") as $checked
| if $current != "" then {key: $current, keep: true, checked: $checked, taken: []}
  else
    [candidates[] | {key: ., by: holder($binds; .)}] as $all
    # the held candidates up to the first free one (all of them when none is free)
    | ([$all | to_entries[] | select(.value.by == null) | .key] | first // ($all | length)) as $i
    | {key: ($all[$i].key // null), keep: false, checked: $checked, taken: $all[:$i]}
  end
