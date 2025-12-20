
## 📄 Managing Local vs Remote Dev Sources

### 🔍 Local Sources
- When starting a new theme or plugin, add your scaffold under:
  - `PROJECT_BASE/src/themes/<name>`  
  - `PROJECT_BASE/src/plugins/<name>`  
- In `environments.json`, define it as a **local source**:
  ```json
  {
    "name": "demo",
    "source": "config/wordpress/templates/plugins/demo",
    "type": "local"
  }
  ```
- Provisioning will copy this local source into the WordPress container during `init`/`up`.

### 🚀 Promoting to Remote
Once your local scaffold is ready to be versioned independently:

1. **Initialize a Git repo manually** inside the local source folder:
   ```bash
   cd PROJECT_BASE/src/plugins/demo
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/yourorg/demo-plugin.git
   git push -u origin main
   ```

2. **Update `environments.json`** to point to the remote repo:
   ```json
   {
     "name": "demo",
     "source": "https://github.com/yourorg/demo-plugin.git",
     "type": "git"
   }
   ```

3. **Provision again** — the next run will clone the remote repo into `src/plugins/demo` instead of copying from local.

### ✅ Outcome
- `PROJECT_BASE` remains the parent repo, tracking provisioning scripts and configs.  
- `src/plugins` and `src/themes` evolve independently as Git repos.  
- Contributors explicitly control when a local scaffold becomes a remote repo.  
- No hidden state or skip logic in provisioning — everything is transparent and declarative.

---

Would you like me to also add a **diagram** (ASCII or Markdown table style) showing the transition from `local → promote → remote`, so contributors can visualize the workflow at a glance?

---

## 🔄 Local → Remote Workflow Diagram

```markdown
+-------------------+        +-------------------+        +-------------------+
|   Local Source    |        |   Promote to Git  |        |   Remote Source   |
|-------------------|        |-------------------|        |-------------------|
| src/plugins/demo  | -----> | git init, commit  | -----> | GitHub/GitLab/etc |
| src/themes/minimal|        | git remote add    |        | environments.json |
| type: local       |        | git push origin   |        | type: git         |
+-------------------+        +-------------------+        +-------------------+
```

---

### ✅ How to Read It
- **Local Source**: Start with scaffolds copied into `src/plugins` or `src/themes`.  
- **Promote to Git**: Manually initialize a repo, commit, and push to a remote.  
- **Remote Source**: Update `environments.json` to point to the remote repo (`type: git`).  

---

## 🗂️ Repo Hierarchy Diagram

```markdown
+---------------------------------------------------+
|                  PROJECT_BASE (parent repo)       |
|---------------------------------------------------|
|  Tracks:                                          |
|   • Provisioning scripts                          |
|   • Config files (environments.json, etc.)        |
|   • Shared helpers                                |
|                                                   |
|  Contains:                                        |
|   src/                                            |
|    ├── plugins/  ---> Independent Git repo(s)     |
|    │     • demo                                   |
|    │     • other plugins                          |
|    │                                              |
|    └── themes/   ---> Independent Git repo(s)     |
|          • minimaltesttheme                       |
|          • other themes                           |
+---------------------------------------------------+
```

---

### ✅ How to Read It
- **PROJECT_BASE** is the parent repo — it holds provisioning logic, configs, and scaffolds.  
- **src/plugins** and **src/themes** are child repos — each can be local scaffolds or independent Git repos.  
- The parent repo doesn’t track child commits, only their presence and provisioning pointers.  
- Contributors manage child repos independently, promoting local scaffolds to remote repos when ready.  

---

