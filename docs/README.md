# Commonplace website (GitHub Pages, custom domain)

The static marketing, support and privacy pages for Commonplace, the Chrome extension, and Commonplace Helper, its Mac app. The site is plain HTML and one stylesheet, with no build step, external fonts, scripts or trackers. It shares its design and `style.css` with the other sites at victorshammas.com (Plainview, Gaugeline, Quoth, Staple, Claude Usage Meter, Lectern). The palette matches the icon: espresso and amber, with a warm off-white in light mode.

| File | Published URL |
|---|---|
| `index.html` | https://victorshammas.com/commonplace/ (homepage URL in the Chrome Web Store) |
| `support.html` | https://victorshammas.com/commonplace/support.html (support URL; `#install`, `#denied` and `#remove` are linked to) |
| `privacy.html` | https://victorshammas.com/commonplace/privacy.html (privacy policy URL for the Chrome Web Store) |
| `style.css`, `icon.png`, `favicon.png`, `apple-touch-icon.png` | assets |
| `images/hero.png` | the popup in front of a demo note in Apple Notes (1280×800), from `../store/src/hero.html` |
| `images/helper.png` | the Commonplace Helper setup window |
| `.nojekyll` | tells Pages to serve files as-is |

The Chrome Web Store listing links to the privacy and support pages, so keep the paths stable.

## How the URL works

The GitHub Pages user site (`victor-shammas.github.io`) uses the custom domain `victorshammas.com`, so a public repo named **`commonplace`** with Pages turned on is published at `https://victorshammas.com/commonplace/`. No `CNAME` file; don't add one.

## Publishing

Served by GitHub Pages from the `main` branch, folder `/docs`. Push to `main` and the site updates within a minute or two.

## Before and after launch

- **Chrome Web Store link:** live since 12 October 2026 at https://chromewebstore.google.com/detail/commonplace/pckjhgfeeiebcdegmgnllooegobohcoc. The homepage CTA, setup step 3, support `#install` step 3 and the `/apps/` card all link to it.
- **Privacy policy:** `privacy.html` is the text of `../PRIVACY.md`. If the policy changes, update both and the effective date.
- **App bar:** all seven sites carry the same seven tiles in a 4 + 3 grid; keep them in step when tiles change.
- After an icon change, regenerate `icon.png` (256 px), `favicon.png` (64 px, from the simplified small icon) and the opaque 180 px `apple-touch-icon.png` from `../assets/`.
