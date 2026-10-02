// Skin order for the T key: auto follows the viewer's light/dark preference (Tokyo Night when dark).
export const SKINS = ['auto', 'tokyo-night', 'catppuccin', 'gruvbox', 'rose-pine', 'light'] as const;
export type Skin = (typeof SKINS)[number];

export const nextSkin = (s: Skin): Skin => SKINS[(SKINS.indexOf(s) + 1) % SKINS.length] ?? 'auto';
