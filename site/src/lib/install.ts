// The one-line omarchy-store install (ADR-0042) and what it brings. Pure data, shared by the index
// and /about; the copy button copies exactly INSTALL_CMD.
export const STORE_REPO = 'https://github.com/PrometheusRoot/omarchy-store';
export const INSTALL_CMD = `omarchy plugin add ${STORE_REPO} --enable`;

export const GETS = [
  { icon: 'i-grid', title: 'store', text: 'browse, search and install, pinned to the reviewed commit' },
  {
    icon: 'i-shield',
    title: 'bar shield',
    text: 'the worst state of what you run; right click for verdicts',
  },
  {
    icon: 'i-sig',
    title: 'verified locally',
    text: 'signed snapshot + sha256 of every file; blocked is refused',
  },
  {
    icon: 'i-term',
    title: 'optional',
    text: 'menu entry, keybind, terminal command; listed and asked first',
  },
] as const;

/** The copy button's label after a copy attempt. */
export function copyLabel(ok: boolean): string {
  return ok ? 'copied' : 'select + copy';
}
