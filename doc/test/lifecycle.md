# PTEKWPDEV — Full Lifecycle Test
This document captures a clean-slate, end-to-end lifecycle test of the PTEKWPDEV
platform. It demonstrates the contributor workflow from app initialization to
project launch, using the `demo` project as a reference example.

---

## 🧱 Assumptions

Note: app_bootstrap and app_config do not expand shell variables such as $HOME
or ~ inside app.json. All paths must be specified as absolute paths. Shell-style
expansion will be added in a future version.

This lifecycle test begins from a completely clean BASH environment. The following conditions **must** be true before starting:

- **APP_BASE**  
  The application repository has been cloned to:  
  ```
  $HOME/projects/ptekwpdev
  ```
  This directory is referred to as **APP_BASE** throughout the test.

- **CONFIG_BASE**  
  The global application configuration directory either **does not exist** or is **empty**:  
  ```
  $HOME/.ptekwpdev
  ```
  This directory will be created and initialized by `app_bootstrap.sh`.

- **PROJECT_BASE**  
  The project workspace directory either **does not exist** or is **empty**:  
  ```
  $HOME/ptekwpdev_repo
  ```
  This directory will be created by `app_bootstrap.sh` and used to store all project‑level deployments.

- **DOCKER**  
    All previous containers, networks and images removed/pruned...
    Volumes:
        ptekwpdev_assets
        ptekwpdev_db
    Networks:
        [project]_frontend
        ptekwpdev_backend
    Images:
        (optional but recommended for a full clean slate)
        phpmyadmin/phpmyadmin
        mariadb:10.11
        nginx:alpine
        wordpress:latest
        wordpress:cli

---


## 0. Clean Slate
Before beginning, ensure no previous runtime state exists (see assumptions).
Commands:
    rm -rf $HOME/.ptekwpdev
    rm -rf $HOME/ptekwpdev_repo

# **1. Run `app_bootstrap.sh`**

This is the first real action in the lifecycle, and now that your bootstrap script is stable, we can document it cleanly and confidently.

Below is a polished continuation you can drop directly into `lifecycle.md`.  
It follows the tone and structure you’ve already established.

---

# **1. Run `app_bootstrap.sh`**

With a clean slate confirmed, initialize the application environment.  
This step creates all required directories, generates secrets, and writes the global `app.json` configuration.

### **Command**

```bash
cd $HOME/projects/ptekwpdev/bin
./app_bootstrap.sh -f
```

### **Expected Output (annotated)**

```
[SUCCESS] Logfile set to: .../app/logs/app_bootstrap.log
[INFO] Preparing directory structure...
[INFO] Ensured: $APP_BASE/app/config
[INFO] Ensured: $CONFIG_BASE
[INFO] Ensured: $CONFIG_BASE/config
[INFO] Ensured: $PROJECT_BASE
[INFO] Ensured: $PROJECT_BASE/wordpress
[INFO] Ensured: $PROJECT_BASE/src
[INFO] Ensured: $PROJECT_BASE/src/plugins
[INFO] Ensured: $PROJECT_BASE/src/themes
[INFO] Directory scaffolding complete.

[INFO] Generating secrets key values...
[SUCCESS] Secrets key values created

[INFO] Generating app.json → $APP_BASE/app/config/app.json
[SUCCESS] Wrote app.json → $APP_BASE/app/config/app.json

[SUCCESS] CONFIG_BASE initialized at $CONFIG_BASE/config/app.json
[SUCCESS] App bootstrap complete.
```

### **What This Step Does**

- Creates all required app‑level and project‑level directories  
- Generates deterministic, ASCII‑safe secrets  
- Writes `app.json` to both:
  - `$APP_BASE/app/config/app.json` (source of truth)
  - `$CONFIG_BASE/config/app.json` (runtime copy)
- Initializes the global configuration directory  
- Prepares the environment for project creation and deployment  

### **Artifacts Created**

| Path | Description |
|------|-------------|
| `$APP_BASE/app/config/app.json` | Canonical app‑level configuration |
| `$CONFIG_BASE/config/app.json` | Runtime copy used by all scripts |
| `$PROJECT_BASE/` | Root directory for all projects |
| `$PROJECT_BASE/src/plugins` | Dev‑source plugin workspace |
| `$PROJECT_BASE/src/themes` | Dev‑source theme workspace |
| `$PROJECT_BASE/wordpress` | WordPress core directory (populated later) |

---

# **Next Step: 2. Run `app_deploy.sh`**

This is the next major milestone in the lifecycle test.

`app_deploy.sh` will:

- Ensure `projects.json` exists  
- Initialize runtime state  
- Prepare the environment for project creation  
- Optionally register the demo project  


