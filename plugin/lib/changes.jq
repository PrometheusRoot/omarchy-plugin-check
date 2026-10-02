# Add one entry to ~/.config/omarchy/CHANGES.md in the file's own layout: date sections
# "## YYYY-MM-DD", newest first, after the first "---" rule; entries are "### ..." blocks.
#   jq -R -s -j --arg date 2026-10-02 --arg entry "### Plugin: ..." -f lib/changes.jq CHANGES.md
(split("\n")) as $lines
| ($entry | sub("\n+$"; "") | split("\n")) as $e
| ($lines | index("## " + $date)) as $day
| ($lines | index("---")) as $rule
| if $day != null then
    (if ($lines[$day + 1] // "") == "" then $day + 2 else $day + 1 end) as $at
    | $lines[:$at] + $e + [""] + $lines[$at:]
  elif $rule != null then
    $lines[:$rule + 1] + ["", "## " + $date, ""] + $e + $lines[$rule + 1:]
  else
    ($lines | if .[-1] == "" then .[:-1] else . end) + ["", "## " + $date, ""] + $e + [""]
  end
| join("\n")
