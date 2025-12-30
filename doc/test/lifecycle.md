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
    # All previous containers, networks and images removed/pruned...
    # Volumes:
      ## ptekwpdev_assets
      ## ptekwpdev_db
    # Networks:
      ## [project]_frontend
      ## ptekwpdev_backend
    # Images:
      ## (optional but recommended for a full clean slate)
      ## phpmyadmin/phpmyadmin
      ## mariadb:10.11
      ## nginx:alpine
      ## wordpress:latest
      ## wordpress:cli

---


## 0. Clean Slate
Before beginning, ensure no previous runtime state exists (see assumptions).
Commands:
```
rm -rf $HOME/.ptekwpdev
rm -rf $HOME/ptekwpdev_repo
```

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

# **2. Run `app_deploy.sh`**

After bootstrapping the application, the next step is to deploy the **runtime environment**.  
This prepares all app‑level runtime assets under `$CONFIG_BASE`, generates the `.env` file used by core containers, and brings the app‑level Docker services online.

### **Command**

```bash
cd $HOME/projects/ptekwpdev/bin
./app_deploy.sh -a init
```

### **Expected Output (annotated)**

```
[INFO] Generating projects.json → ~/.ptekwpdev/config/projects.json
[INFO] projects.json not found — generating from template
[SUCCESS] projects.json created

[INFO] Deploying env templates from app/config → ~/.ptekwpdev/config
[SUCCESS] Env templates deployed

[INFO] Deploying Docker engine templates → ~/.ptekwpdev/docker
[SUCCESS] Docker templates deployed

[INFO] Deploying container config directories from config/ → ~/.ptekwpdev/config
[SUCCESS] Container config directories deployed

[INFO] Generating app-level .env file...
[SUCCESS] .env file written to ~/.ptekwpdev/docker/.env

[INFO] Starting core containers...
[SUCCESS] Core containers are online

[SUCCESS] App environment deployed at ~/.ptekwpdev
```

### **What This Step Does**

`app_deploy.sh` is responsible for preparing the **runtime layer** of the platform:

- Creates `projects.json` from `projects.tpl.json`  
- Deploys all `env.*.tpl` templates  
- Deploys Docker engine templates (`compose.app.yml`, `compose.project.yml`, Dockerfiles, etc.)  
- Deploys container config directories (`proxy/`, `wordpress/`, `sqladmin/`, etc.)  
- Generates the app‑level `.env` file using values from `app.json`  
- Starts the core containers defined in `compose.app.yml`  

### **Artifacts Created**

| Path | Description |
|------|-------------|
| `$CONFIG_BASE/config/projects.json` | Runtime project registry (initially empty) |
| `$CONFIG_BASE/config/env.*.tpl` | Runtime environment templates |
| `$CONFIG_BASE/docker/compose.app.yml` | App‑level Docker Compose file |
| `$CONFIG_BASE/docker/.env` | App‑level environment variables |
| Docker containers | MariaDB, phpMyAdmin, asset volume, backend network |

### **State After This Step**

At this point:

- The **app layer is fully initialized**  
- The **runtime layer is fully deployed**  
- Core containers are running  
- The system is ready for **project creation**  

---

# **Next Step: 3. Create a Project (`project_create.sh`)**

This is the next major milestone in the lifecycle.

`project_create.sh` will:

- create a new project directory under `$PROJECT_BASE`  
- scaffold project‑level config  
- generate project‑level `.env`  
- generate `compose.project.yml`  
- register the project in `projects.json`  
- prepare the project for launch  
