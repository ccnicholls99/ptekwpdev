# 📄 **Lifecycle Test Script — Demo Project (Text‑Only)**  
**Purpose:** Validate the full lifecycle of a project on a clean installation of the PTEKWPDEV platform, using the `demo` project as the reference case.

---

## 0. **Prerequisites**

- The repository is freshly cloned to:  
  `~/projects/ptekwpdev`
- No previous `CONFIG_BASE` or `PROJECT_BASE` directories exist.
- Docker is running.
- You are inside the repo root.
---
For the purpose of this document, we will assume the following key locations:
- APP_BASE => $HOME/projects/ptekwpdev
- CONFIG_BASE => $HOME/.ptekwpdev
- PROJECT_BASE => $HOME/ptekwpdev/project_repo

---

## 1. **Clean Slate Preparation**

1. Remove any previous config or project directories:

   ``` bash
   # CONFIG_BASE
   rm -rf ~/.ptekwpdev
   # PROJECT_BASE
   rm -rf ~/ptekwpdev_repo
   ```

2. Confirm they are gone:

   ```
   ls ~/.ptekwpdev
   ls ~/ptekwpdev_repo
   ```

Expected: Only `~/projects/ptekwpdev` (APP_BASE) remains.

---

## 2. **Run app_bootstrap**

Command:

```
./bin/app_bootstrap.sh
```

Expected outcomes:

- `CONFIG_BASE` directory created  
- `app.json` generated  
- `docker/` directory created under config  
- meta‑schema bundled  
- logs written to `app/logs/app_bootstrap.log`

Verify:

```
ls ~/.ptekwpdev/config
cat ~/.ptekwpdev/config/app.json
```

---

## 3. **Run app_deploy**

Command:

```
./bin/app_deploy.sh
```

Expected outcomes:

- All templates copied into `CONFIG_BASE/config`:
  - `env.app.tpl`
  - `env.project.tpl`
  - `projects.tpl.json` → `projects.json`
- Docker Compose files generated:
  - `compose.app.yml`
- `.env` generated for app-level services
- phpMyAdmin + global DB ready (but not launched yet)
- Backups created for any overwritten JSON files (TODO)

Verify:

```
ls ~/.ptekwpdev/config
cat ~/.ptekwpdev/config/projects.json
```

Expected:  
`projects.json` contains:

```
{
  "projects": {}
}
```

---

## 4. **Create the Demo Project**

Command:

```
./bin/project_create.sh --project demo
```

Expected interactive flow:

- Defaults shown:
  - domain: demo.local
  - network: ptekwpdev_demo_net
  - base_dir: demo
  - ports: 8080 / 8443
  - title: demo
  - description: “A new WordPress site for demo”
  - wp image: default from app.json
  - wp host: demo.local
- User accepts or overrides
- Secrets generated
- Project block inserted into `projects.json`

Verify:

```
cat ~/.ptekwpdev/config/projects.json | jq '.projects.demo'
```

Expected fields:

- project_title  
- project_description  
- project_domain  
- project_network  
- base_dir  
- wordpress.image  
- wordpress.host  
- wordpress.port  
- wordpress.ssl_port  
- secrets.*  
- dev_sources.*  

---

## 5. **Add Dev Sources (Optional)**

Command:

```
./bin/project_dev_sources.sh --project demo --interactive
```

Expected:

- Prompts for plugin/theme dev sources  
- Updates `projects.json` under `dev_sources`

Verify:

```
cat ~/.ptekwpdev/config/projects.json | jq '.projects.demo.dev_sources'
```

---

## 6. **Deploy the Demo Project**

Command:

```
./bin/project_deploy.sh --project demo --action deploy
```

Expected outcomes:

- PROJECT_REPO computed:
  `~/ptekwpdev_repo/demo`
- Project directory created:
  - `wordpress/`
  - `app/`
  - `sql-data/`
  - `docker/`
- `.env` generated from `env.project.tpl`
- `compose.project.yml` generated
- WordPress core downloaded (if not present)
- Database created for project
- WordPress provisioned via WP‑CLI:
  - site title
  - description
  - admin user
  - admin email
  - admin password

Verify:

```
ls ~/ptekwpdev_repo/demo
cat ~/ptekwpdev_repo/demo/docker/.env
```

---

## 7. **Launch the Demo Project**

Command:

```
./bin/project_launch.sh --project demo
```

Expected:

- Containers start:
  - demo_wordpress
  - demo_db
- WordPress reachable at:
  `http://demo.local:8080`

Verify:

```
docker ps | grep demo
```

---

## 8. **Validate WordPress Installation**

Open browser:

```
http://demo.local:8080
```

Expected:

- WordPress site loads
- Title matches `project_title`
- Tagline matches `project_description`
- Admin login works with generated credentials

---

## 9. **Stop the Demo Project**

Command:

```
./bin/project_launch.sh --project demo --action stop
```

Expected:

- Containers stop cleanly

Verify:

```
docker ps | grep demo
```

Expected: no running containers.

---

## 10. **Cleanup (Optional)**

Command:

```
./bin/project_deploy.sh --project demo --action destroy
```

Expected:

- Project containers removed  
- Project volumes removed  
- Project directory removed  
- Project entry removed from `projects.json`

Verify:

```
cat ~/.ptekwpdev/config/projects.json
ls ~/ptekwpdev_repo
```

---

# 🎉 **End of Lifecycle Test**

This script validates:

- app bootstrap  
- app deploy  
- project creation  
- dev source injection  
- project deploy  
- WordPress provisioning  
- project launch  
- project stop  
- project destroy  

