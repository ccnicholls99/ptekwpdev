
## ⚙️ Installation
1. Copy the `demo` folder into your WordPress container’s `wp-content/plugins/` directory.
   - Provisioning scripts will handle this automatically if `dev_sources.plugins` includes the demo plugin.
2. Log in to your WordPress admin dashboard.
3. Navigate to **Plugins → Installed Plugins**.
4. Activate **Demo Plugin**.

## 🧪 What it does
- On activation, the plugin displays a green admin notice:
  > *“Demo Plugin is active!”*
- This confirms that provisioning successfully deployed the plugin.

## 🔧 Notes
- The plugin is intentionally minimal — no settings, no dependencies.
- Use it to validate provisioning workflows before deploying real plugins.
- Extend it by adding hooks, shortcodes, or REST endpoints as needed.