// Copy buttons ([data-copy] = id of the element whose text is copied). Clipboard access may be
// refused (insecure context, permissions): then the text is selected for a manual copy.
import { copyLabel } from '../lib/install';

for (const btn of document.querySelectorAll<HTMLButtonElement>('[data-copy]')) {
  btn.addEventListener('click', async () => {
    const src = document.getElementById(btn.dataset.copy ?? '');
    const label = btn.querySelector<HTMLElement>('[data-copy-label]');
    if (!src || !label) return;
    let ok = true;
    try {
      await navigator.clipboard.writeText(src.textContent ?? '');
    } catch {
      ok = false;
      const range = document.createRange();
      range.selectNodeContents(src);
      const sel = window.getSelection();
      sel?.removeAllRanges();
      sel?.addRange(range);
    }
    label.textContent = copyLabel(ok);
    setTimeout(() => {
      label.textContent = 'copy';
    }, 1600);
  });
}
