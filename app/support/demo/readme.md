# Demo Project (PTEKWPDEV)

```
app/support/demo/.
```
This directory contains a complete, minimal demo project for PTEKWPDEV.  
It is fully stand‑alone and treated exactly like any user‑created project.

## Workflow

From APP_BASE (~/projects/ptekwpdev)

1. **Create the project**

    ```bash
    ./bin/project_create.sh \
     --project demo \
     --dev-plugin "name=demo source=app/support/demo/wordpress/templates/plugins/demo type=local init_git=false" \
     --dev-theme  "name=demo source=app/support/demo/wordpress/templates/themes/demo type=local init_git=false"
    ```

2. **Deploy the project**
    ```bash
    ./bin/project_deploy.sh --project demo --action deploy
    ```

3. **Launch the project**
    ```bash
    ./bin/project_launch.sh --project demo --action deploy
    ```

4. **Cleanup the project**
    ```bash
    ./bin/project_cleanup.sh --project demo
    ```

## Demo Project Manifest 
APP_BASE/app/support/demo/...

- config/project.tpl.json
    Optional template metadata for future automation.
- wordpress/templates/plugins/demo/
    Minimal demo plugin source code.
- wordpress/templates/themes/demo/
    Minimal demo theme source code.

This project is intentionally simple and serves as a reference for:
- dev_sources provisioning
- WordPress theme/plugin development
- project lifecycle testing
- contributor onboarding

---

### 📄 `.../config/project.tpl.json`

This is optional, but useful for future automation or documentation.

```json
{
  "project_title": "Demo Project",
  "project_description": "A minimal demonstration project for PTEKWPDEV.",
  "project_domain": "demo.local",
  "project_network": "ptekwpdev_demo_net",
  "base_dir": "demo"
}
```

### 🧩 Demo Plugin: `.../wordpress/templates/plugins/demo/...`
📄 demo.php
```php
<?php
/**
 * Plugin Name: Demo Plugin
 * Description: A minimal plugin for the PTEKWPDEV demo project.
 * Version: 1.0
 */

add_action('init', function () {
    error_log("Demo Plugin Loaded");
});
```

📄 readme.txt
```
Demo Plugin
===========

A minimal plugin used by the PTEKWPDEV demo project.
```


### 🎨 Demo Theme: .../wordpress/templates/themes/demo/...
📄 style.css
```css
/*
Theme Name: PTEKWPDEV Demo Theme
Description: Minimal theme for the PTEKWPDEV demo project.
Version: 1.0
*/
```

📄 functions.php
```php
<?php
add_action('wp_head', function () {
    echo "<!-- PTEKWPDEV Demo Theme Loaded -->";
});
```


📄 index.php
```php
<?php
echo "<h1>PTEKWPDEV Demo Theme Active</h1>";
```

-- End --


