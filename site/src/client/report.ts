// Report page: switch the provider panel from the provider table, and highlight the section in view.
function select(provider: string, focus = false): void {
  for (const p of document.querySelectorAll<HTMLElement>('[data-panel]'))
    p.hidden = p.dataset.panel !== provider;
  for (const tr of document.querySelectorAll<HTMLElement>('tr[data-row]'))
    tr.classList.toggle('sel', tr.dataset.row === provider);
  for (const b of document.querySelectorAll<HTMLButtonElement>('button[data-p]'))
    b.setAttribute('aria-pressed', String(b.dataset.p === provider));
  if (focus) document.getElementById(`panel-${provider}`)?.scrollIntoView({ block: 'start' });
  spy();
}

for (const b of document.querySelectorAll<HTMLButtonElement>('button[data-p]')) {
  b.addEventListener('click', () => select(b.dataset.p ?? '', true));
}

// A finding link (#f-<provider>-<id>) inside a hidden panel opens that panel first.
function openHash(): void {
  const id = decodeURIComponent(location.hash.slice(1));
  if (!id) return;
  const el = document.getElementById(id);
  const panel = el?.closest<HTMLElement>('[data-panel]');
  if (el && panel?.hidden) {
    select(panel.dataset.panel ?? '');
    el.scrollIntoView({ block: 'start' });
  }
  if (el instanceof HTMLElement && el.closest('details') && !el.closest('details')?.open) {
    const d = el.closest('details');
    if (d) d.open = true;
    el.scrollIntoView({ block: 'start' });
  }
}
window.addEventListener('hashchange', openHash);
openHash();

let observer: IntersectionObserver | null = null;
function spy(): void {
  observer?.disconnect();
  const panel = document.querySelector<HTMLElement>('[data-panel]:not([hidden])');
  if (!panel || !('IntersectionObserver' in window)) return;
  const links = [...panel.querySelectorAll<HTMLAnchorElement>('.rnav a')];
  observer = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const id = e.target.id;
        for (const l of links) l.classList.toggle('cur', l.getAttribute('href') === `#${id}`);
      }
    },
    { rootMargin: '-20% 0px -70% 0px' },
  );
  for (const s of panel.querySelectorAll('.sect')) observer.observe(s);
}
spy();
