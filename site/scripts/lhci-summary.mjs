// Print category scores (and what drags a score down) from .lighthouseci/lhr-*.json.
import { readdirSync, readFileSync } from 'node:fs';

const dir = process.argv[2] ?? '.lighthouseci';
for (const f of readdirSync(dir).filter((x) => x.startsWith('lhr-') && x.endsWith('.json'))) {
  const r = JSON.parse(readFileSync(`${dir}/${f}`, 'utf8'));
  const scores = Object.fromEntries(Object.entries(r.categories).map(([k, v]) => [k, v.score]));
  console.log(r.finalDisplayedUrl, JSON.stringify(scores));
  for (const [cat, c] of Object.entries(r.categories)) {
    for (const ref of c.auditRefs) {
      const a = r.audits[ref.id];
      if (ref.weight > 0 && a.score !== null && a.score < 0.9) {
        console.log(`  ${cat}: ${ref.id} ${a.displayValue ?? ''} (${a.score})`);
        for (const i of (a.details?.items ?? []).slice(0, 3))
          if (i.node) console.log(`    ${i.node.selector}`);
      }
    }
  }
}
