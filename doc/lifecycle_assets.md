# 📦 **lifecycle_assets.md**  
**Global Assets Lifecycle for PTEKWPDEV**

---

## 🧭 Overview

The **Assets Lifecycle** manages a global, shared repository of WordPress plugins, themes, static bundles, and versioned asset sets. This repository is stored inside the `ptekwpdev_assets` container and backed by the `ptekwpdev_assets_volume`.

The assets subsystem is **fully independent** of both the **app lifecycle** and the **project lifecycle**. It can be initialized **before** the app is deployed and **before** any project exists.

This independence allows teams to preload standard toolsets (e.g., Divi, Breakdance, Elementor, ACF Pro) and ensure consistent provisioning across all projects.

---

## 🧱 Architectural Principles

- The assets repository is **global**, not project‑scoped.  
- Assets are stored in a **versioned directory structure** inside a dedicated Docker volume.  
- The assets lifecycle has **its own container**, **its own volume**, and **its own scripts**.  
- Projects **consume** assets but do not own or manage them.  
- The assets lifecycle can run **before**, **after**, or **between** app/project operations.  
- Assets are mounted into project containers during `project_deploy` and available at runtime.

---

## 📂 Directory Structure (Inside the Assets Volume)

```
/assets
  /plugins
    /<plugin-name>
      /<version>/
  /themes
    /<theme-name>
      /<version>/
  /static
    /<bundle-name>
      /<version>/
  /versions
  metadata.json (optional)
```

This structure is created automatically by `assets_bootstrap.sh`.

---

## 🔄 Assets Lifecycle Stages

The assets lifecycle consists of three scripts:

- `assets_bootstrap.sh`  
- `assets_add.sh`  
- `assets_list.sh`  

Each script plays a specific role in managing the global assets repository.

---

# 1. 🚀 assets_bootstrap.sh  
**Initialize the Global Assets Repository**

### Purpose
Create the assets container and volume, and initialize the canonical directory structure.

### When to Run
- First‑time setup  
- After wiping the assets volume  
- When upgrading the assets container image  
- Before any app or project lifecycle steps (recommended)

### What It Does
- Creates `ptekwpdev_assets_volume`  
- Builds/starts the `ptekwpdev_assets` container  
- Creates the directory structure under `/assets`  
- Ensures the repository is ready for asset operations  
- Logs to `app/logs/assets_bootstrap.log`

### Notes
This script does **not** depend on:
- app.json  
- projects.json  
- any project directories  
- any app‑level Docker configuration  

It is completely standalone.

---

# 2. ➕ assets_add.sh  
**Add or Update Assets in the Repository**

### Purpose
Copy local assets (plugins, themes, static bundles) into the global repository in a structured, versioned way.

### When to Run
- Adding new global plugins/themes  
- Updating an asset to a new version  
- Preparing standard toolsets before creating projects  
- Maintaining a clean, versioned asset library  

### Usage Example
```
./bin/assets_add.sh --type plugin --name my-plugin --version 1.2.3 --source ./local/path
```

### What It Does
- Validates asset type (`plugin`, `theme`, `static`)  
- Validates version format  
- Copies assets into the correct versioned directory  
- Updates metadata.json (if used)  
- Logs to `app/logs/assets_add.log`  

### Notes
Assets added here become available to **all** projects.

---

# 3. 📜 assets_list.sh  
**Inspect the Assets Repository**

### Purpose
Provide a structured, human‑readable listing of all assets stored in the global repository.

### When to Run
- Before creating a project  
- Before adding new assets  
- During debugging  
- When verifying asset versions  

### What It Does
- Connects to the assets container  
- Recursively lists all asset types, names, and versions  
- Outputs a clean, readable structure  
- Logs to `app/logs/assets_list.log`

### Example Output
```
plugins/
  my-plugin/
    1.0.0
    1.2.3
themes/
  my-theme/
    2.0.0
static/
  logo-pack/
    2024-01
```

---

# 🧩 How the Assets Lifecycle Integrates with the Platform

Although independent, the assets lifecycle supports both the app and project lifecycles.

### **App Lifecycle**
- Does not modify or depend on assets  
- Assets can be bootstrapped before or after app_deploy  

### **Project Lifecycle**
- During `project_deploy`, the assets volume is mounted into the project container  
- WordPress provisioning may copy or activate assets from the global repository  
- Projects can optionally add project‑specific assets, but the global repository remains canonical  

---

# 🧭 Recommended Order for a Clean Setup

1. **assets_bootstrap.sh**  
   Initialize the global assets repository.

2. **assets_add.sh**  
   Add global plugins/themes (e.g., Divi, Breakdance).

3. **app_bootstrap.sh**  
   Initialize app-level configuration.

4. **app_deploy.sh**  
   Deploy app-level Docker configuration.

5. **project_create.sh**  
   Create project metadata.

6. **project_deploy.sh**  
   Deploy project and mount the global assets repository.

This ensures projects have immediate access to all global assets.

---

# 📝 Future Enhancements (Optional)

- Version metadata schema  
- Asset dependency mapping  
- Asset bundle definitions  
- Dynamic volume naming  
- Asset validation during project provisioning  
