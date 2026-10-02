import assert from "node:assert/strict";
import { test } from "node:test";
import * as C from "./imgcache.mjs";

const URL1 = "https://plugins.omarchy.org/assets/img/plugins/8-huacnlee-omamail-card.webp";

test("file names are stable, 16 hex + the image extension", () => {
  assert.equal(C.fileName(URL1), C.fileName(URL1));
  assert.match(C.fileName(URL1), /^[0-9a-f]{16}\.webp$/);
  assert.notEqual(C.fileName(URL1), C.fileName(URL1.replace("card", "detail")));
  assert.match(C.fileName("https://x.example/a.PNG?x=1"), /\.png$/);
  assert.match(C.fileName("https://x.example/a"), /\.img$/);
  assert.equal(C.filePath("/c/img/", URL1), `/c/img/${C.fileName(URL1)}`);
});

test("only https URLs are fetched", () => {
  assert.ok(C.fetchable(URL1));
  for (const bad of ["", "http://x.example/a.png", "file:///etc/passwd", "assets/a.webp", "javascript:alert(1)"]) assert.equal(C.fetchable(bad), false, bad);
});

test("curl argv keeps the URL out of the shell script and writes atomically", () => {
  const argv = C.curlArgv("https://x.example/a.png;rm -rf ~", "/c/img/f.png");
  assert.equal(argv[0], "sh");
  assert.ok(!argv[2].includes("x.example"), "URL is a positional parameter, never script text");
  assert.ok(argv[2].includes("--proto =https"));
  assert.ok(argv[2].includes("--max-filesize"));
  assert.deepEqual(argv.slice(4), ["https://x.example/a.png;rm -rf ~", "/c/img/f.png.part", "/c/img/f.png"]);
});

test("queue: newest first, de-duplicated, bounded", () => {
  let q = [];
  q = C.enqueue(q, "a");
  q = C.enqueue(q, "b");
  q = C.enqueue(q, "a");
  assert.deepEqual(q, ["a", "b"]);
  for (let i = 0; i < 500; i++) q = C.enqueue(q, `u${i}`);
  assert.equal(q.length, 400);
  assert.equal(q[0], "u499");
});
