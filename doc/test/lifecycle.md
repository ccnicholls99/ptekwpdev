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
