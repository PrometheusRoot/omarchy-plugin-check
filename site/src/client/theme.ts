// Theme cycling: the button or the T key steps through the skins; the choice is a per-viewer
// convenience in localStorage (every access guarded: private windows and blocked storage throw).
import { nextSkin, SKINS, type Skin } from '../lib/skins';

const KEY = 'opc.skin';

function read(): Skin {
  try {
    const v = localStorage.getItem(KEY);
    return (SKINS as readonly string[]).includes(v ?? '') ? (v as Skin) : 'auto';
  } catch {
    return 'auto';
  }
}

function apply(skin: Skin): void {
  const root = document.documentElement;
  if (skin === 'auto') root.removeAttribute('data-skin');
  else root.setAttribute('data-skin', skin);
  const name = getComputedStyle(root).getPropertyValue('--skin-name').replace(/"/g, '').trim();
  const label = document.getElementById('themeName');
  if (label) label.textContent = skin === 'auto' ? `${name} · auto` : name;
  try {
    localStorage.setItem(KEY, skin);
  } catch {
    // storage unavailable: the skin still applies for this page view
  }
}

let skin = read();
apply(skin);
const cycle = () => {
  skin = nextSkin(skin);
  apply(skin);
};
document.getElementById('themeBtn')?.addEventListener('click', cycle);
document.addEventListener('keydown', (e) => {
  if (e.key.toLowerCase() !== 't' || e.ctrlKey || e.metaKey || e.altKey) return;
  const t = e.target as HTMLElement | null;
  if (t && (t.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName))) return;
  e.preventDefault();
  cycle();
});
window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => apply(skin));
