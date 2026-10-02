// Shared by the node tests and dev tools: the committed dev data is the client bundle of a
// real snapshot build (store/dev/, ADR-0032; refreshed by tools/dev-bundle.sh). Home and
// search are gzipped; the app unpacks them next to themselves (git-ignored).
import { existsSync, readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";

export const devDir = new URL("../dev/", import.meta.url).pathname;

function text(name) {
  if (existsSync(`${devDir}${name}`)) return readFileSync(`${devDir}${name}`, "utf8");
  return gunzipSync(readFileSync(`${devDir}${name}.gz`)).toString("utf8");
}

export const devHomeText = () => text("store-home.json");
export const devSearchText = () => text("store-search.json");

export function devDetail(id) {
  const home = JSON.parse(devHomeText());
  return JSON.parse(readFileSync(`${devDir}${home.apiBase.replace(/\/+$/, "")}/plugins/${id}.json`, "utf8"));
}
