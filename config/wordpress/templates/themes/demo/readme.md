# Minimal Test Theme

A barebones WordPress theme for testing provisioning and deployment flows.

## 📂 Location
This theme lives in: ${APP_BASE}/config/wordpress/templates/theme

## ⚙️ Installation
1. Copy the `theme` folder into your WordPress container’s `wp-content/themes/` directory.
   - Provisioning scripts will handle this automatically if `dev_sources.themes` includes the minimal test theme.
2. Log in to your WordPress admin dashboard.
3. Navigate to **Appearance → Themes**.
4. Activate **Minimal Test Theme**.

## 🧪 What it does
- Displays a simple “Hello, WordPress!” message on the front page.
- Provides basic theme support for:
  - Dynamic `<title>` tags
  - Post thumbnails

## 🔧 Notes
- The theme is intentionally minimal — no templates beyond `index.php`.
- Use it to validate provisioning workflows before deploying real themes.
- Extend it by adding `header.php`, `footer.php`, `screenshot.png`, or custom templates as needed.



✅ Outcome
- Contributors see clear instructions on where the theme lives, how to activate it, and what to expect.
- The README reinforces that this is a test scaffold, not a production theme.
- Both theme and plugin templates now have matching documentation, making your repo consistent and contributor‑friendly.
Would you like me to also add a screenshot.png placeholder in the theme folder so WordPress shows a thumbnail in the admin UI when browsing themes?

