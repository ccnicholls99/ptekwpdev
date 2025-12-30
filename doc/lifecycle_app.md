# **PTEKWPDEV — App Lifecycle Guide**

VERSION: 1.0.0-RC

This document describes the **rarely‑performed** but essential **app‑level lifecycle** for the PTEKWPDEV platform.  
These steps initialize the global application environment, prepare runtime templates, and bring core containers online.

Most contributors will **never** need to run the app lifecycle.  
It is typically performed only:

- when setting up the platform for the first time  
- when resetting the entire environment  
- when upgrading global templates  
- when modifying app‑level configuration structure  
- when onboarding a new machine  

For day‑to‑day development, see **`lifecycle_project.md`** instead.

---
# **Assumptions**

In this RC version, we assume the app will be cloned to a directory named "path/to/ptekwpdev". Note the dependance on the final 
directory name of "ptekwpdev". You can choose a different folder name and it should work, but at this point it is "experimental".

---

# **Before You Begin: Clone the Repository**

The app lifecycle assumes that the PTEKWPDEV application repository has already been cloned to a working directory on the operator’s machine.

Clone the repo:

```bash
git clone https://github.com/ccnicholls99/ptekwpdev.git $HOME/projects/ptekwpdev
```

This directory is referred to throughout this document as:

```
APP_BASE = $HOME/projects/ptekwpdev
```

For now, the operator is expected to **run the app lifecycle manually** after cloning.  
In the future, optional git automation may be added to trigger bootstrap or deploy steps automatically.

---

# **0. Overview**

The app lifecycle consists of two major stages:

1. **Bootstrap the app**  
   Creates global directories, generates secrets, and writes `app.json`.

2. **Deploy the app environment**  
   Generates runtime templates, installs Docker configs, and starts core containers.

These steps prepare the global environment under:

```
CONFIG_BASE = $HOME/.ptekwpdev
PROJECT_BASE = $HOME/ptekwpdev_repo
```

Once the app lifecycle is complete, the system is ready for project creation and deployment.

---
Absolutely, Craig — here is the updated **Section 0. Overview** with a clean, prominent **Key Concept** callout explaining exactly what `app.json` is and why it matters.  
This fits naturally into the document and reinforces the architecture you’ve built.

Below is the **updated section**, ready to paste directly into `lifecycle_app.md`.

---

# **0. Overview**

The app lifecycle consists of two major stages:

1. **Bootstrap the app**  
   Creates global directories, generates secrets, and writes `app.json`.

2. **Deploy the app environment**  
   Generates runtime templates, installs Docker configs, and starts core containers.

These steps prepare the global environment under:

```
CONFIG_BASE = $HOME/.ptekwpdev
PROJECT_BASE = $HOME/ptekwpdev_repo
```

Once the app lifecycle is complete, the system is ready for project creation and deployment.

---

## **🔑 Key Concept: What is `app.json`?**

`app.json` is the **single source of truth** for all *static, app‑level configuration* in PTEKWPDEV.  
It defines values that apply to the entire platform — not to any individual project.

It includes:

- absolute paths (`APP_BASE`, `CONFIG_BASE`, `PROJECT_BASE`)  
- Docker settings (backend network, asset volume name)  
- secrets used across all projects  
- WordPress defaults  
- any global constants required by the toolchain  

**Important:**  
`app.json` is generated once during `app_bootstrap.sh` and then copied into `CONFIG_BASE` for runtime use.  
It is **never edited manually** and **never overwritten** unless the operator intentionally re‑runs the app lifecycle.

Every script in the system loads app‑level values through:

``` bash
source $APP_BASE/lib/app_configure.sh
appcfg <key>
```

ensuring deterministic, centralized configuration across the entire platform.

---

# **1. Clean Slate Requirements**

Before running the app lifecycle, ensure the environment is clean.  
This prevents stale configuration, mismatched templates, or leftover containers.

### **Remove global config**

```bash
rm -rf $HOME/.ptekwpdev
```

### **Remove project workspace**

```bash
rm -rf $HOME/ptekwpdev_repo
```

### **Optional: prune Docker state**

Recommended for a fully clean environment:

- **Volumes**
  - `ptekwpdev_assets`
  - `ptekwpdev_db`

- **Networks**
  - `ptekwpdev_backend`
  - any `[project]_frontend` networks

- **Images** (optional)
  - `phpmyadmin/phpmyadmin`
  - `mariadb:10.11`
  - `nginx:alpine`
  - `wordpress:latest`
  - `wordpress:cli`

---

# **2. Run `app_bootstrap.sh`**

This script initializes the **app layer** — the static configuration that defines the platform.

### **Command**

```bash
cd $HOME/projects/ptekwpdev/bin
./app_bootstrap.sh -f
```

### **What This Step Does**

- Creates all required app‑level and project‑level directories  
- Generates deterministic secrets  
- Writes `app.json` to:
  - `$APP_BASE/app/config/app.json`
  - `$CONFIG_BASE/config/app.json`
- Prepares the environment for runtime deployment  

### **Artifacts Created**

| Path | Description |
|------|-------------|
| `$APP_BASE/app/config/app.json` | Canonical app configuration |
| `$CONFIG_BASE/config/app.json` | Runtime copy |
| `$PROJECT_BASE/` | Root directory for all projects |

---

# **3. Run `app_deploy.sh`**

This script deploys the **runtime environment** and starts the core containers.

### **Command**

```bash
cd $HOME/projects/ptekwpdev/bin
./app_deploy.sh -a init
```

### **What This Step Does**

- Generates `projects.json` from `projects.tpl.json`  
- Deploys all `env.*.tpl` templates  
- Deploys Docker engine templates  
- Deploys container config directories  
- Generates the app‑level `.env`  
- Starts core containers using `compose.app.yml`  

### **Artifacts Created**

| Path | Description |
|------|-------------|
| `$CONFIG_BASE/config/projects.json` | Global project registry |
| `$CONFIG_BASE/config/env.*.tpl` | Runtime environment templates |
| `$CONFIG_BASE/docker/compose.app.yml` | App‑level Docker Compose file |
| `$CONFIG_BASE/docker/.env` | App‑level environment variables |
| Running containers | DB, phpMyAdmin, backend network, asset volume |

---

# **4. Validate App Environment**

After deployment, verify that the app environment is healthy.

### **Check running containers**

```bash
docker ps
```

You should see:

- MariaDB  
- phpMyAdmin  
- asset volume container (if applicable)  
- backend network  

### **Check config structure**

```
$CONFIG_BASE/
  config/
    app.json
    projects.json
    env.app.tpl
    ...
  docker/
    compose.app.yml
    .env
```

### **Check logs**

```
$APP_BASE/app/logs/app_bootstrap.log
$APP_BASE/app/logs/app_deploy.log
```

---

# **5. When to Re-run the App Lifecycle**

The app lifecycle is **rarely** needed.  
Re-run it only when:

- resetting the entire environment  
- upgrading global templates  
- changing app-level configuration structure  
- migrating to a new version of PTEKWPDEV  
- onboarding a new machine  

For all normal development, use the **project lifecycle** instead.

---

# **6. Next Steps**

Once the app lifecycle is complete, proceed to:

👉 **`lifecycle_project.md`** — the day‑to‑day workflow for creating, deploying, and launching projects.

