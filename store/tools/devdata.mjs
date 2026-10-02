// Shared by the node tests and dev tools: the committed dev snapshot is gzipped
// (store/dev/store.json.gz); `just store-dev` unpacks it next to itself for the QML app
// (store.json is git-ignored).
import { existsSync, readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";

export const devDir = new URL("../dev/", import.meta.url).pathname;

export function devSnapshotText() {
  if (existsSync(`${devDir}store.json`)) return readFileSync(`${devDir}store.json`, "utf8");
  return gunzipSync(readFileSync(`${devDir}store.json.gz`)).toString("utf8");
}

export function devDetail(id) {
  return JSON.parse(readFileSync(`${devDir}api/plugins/${id}.json`, "utf8"));
}
