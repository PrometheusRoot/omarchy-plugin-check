// Image cache naming + fetch queue policy. ImageCache.qml runs curl; this decides what,
// where and in which order. Cache dir: ~/.cache/omarchy-plugin-check/img/.

export var MAX_PARALLEL = 4;
export var ALLOWED = /^https:\/\/[A-Za-z0-9.-]+\//;

export function fnv(s, seed) {
  var h = seed >>> 0;
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}

export function hex8(n) {
  var s = (n >>> 0).toString(16);
  while (s.length < 8) s = "0" + s;
  return s;
}

// Stable file name for a URL: 64 bits of FNV-1a + the URL's image extension.
export function fileName(url) {
  url = String(url || "");
  var m = url.match(/\.(webp|png|jpe?g|gif|avif)(\?|#|$)/i);
  return hex8(fnv(url, 2166136261)) + hex8(fnv(url, 0x811c9dc5 ^ 0x5bd1e995)) + "." + (m ? m[1].toLowerCase() : "img");
}

export function filePath(dir, url) {
  return String(dir).replace(/\/+$/, "") + "/" + fileName(url);
}

// Only https URLs are fetched; anything else shows the initials tile.
export function fetchable(url) {
  return ALLOWED.test(String(url || ""));
}

// argv for one download: atomic (temp file + rename), bounded size and time, https only.
export function curlArgv(url, dest) {
  var tmp = dest + ".part";
  return ["sh", "-c", 'curl -fsSL --proto =https --max-time 20 --max-filesize 8000000 -o "$2" -- "$1" && mv -f -- "$2" "$3"', "imgfetch", url, tmp, dest];
}

// Queue policy: newest request first (what the user is looking at now), de-duplicated.
export function enqueue(queue, url) {
  var out = [url];
  for (var i = 0; i < queue.length; i++) if (queue[i] !== url) out.push(queue[i]);
  return out.slice(0, 400);
}
