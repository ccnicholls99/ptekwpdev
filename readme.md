# PtekWPDev – Local WordPress Development Environment Manager

PtekWPDev is a Bash-based application for Ubuntu that automates the build, test, and deployment of local WordPress development environments using Docker. It provides simple commands to **create**, **edit**, and **teardown** complete WordPress stacks, ensuring each environment is standalone and Git-ready.

---

## ✨ Features

- **WordPress** – Standard WordPress container for content hosting
- **WP-CLI** – Command-line automation for WordPress tasks
- **MariaDB** – SQL database backend
- **phpMyAdmin** – Web-based database administration
- **Nginx Proxy** – Reverse proxy with SSL certificates and unique hostnames per environment
- **Assets Container** – Shared volume for plugins, themes, and attachments

---

## 📋 Prerequisites

Before using PtekWPDev, ensure you have:

- **Ubuntu 20.04+** (tested on Ubuntu/Debian-based distros)
- **Docker** ≥ 20.x
- **Docker Compose** ≥ 2.x
- **Bash** ≥ 5.x
- **OpenSSL** (for SSL certificate generation)
- Git (to clone and manage repositories)
- Visual Studio Code

---

## 📂 Directory layout

- **Repository root:** `$HOME/projects/ptekwpdev`  
  Contains app source, scripts, and templates. Managed via Git.

- **App config:** `$HOME/.ptekwpdev`  
  Stores environment templates, SSL certs, and shared assets. Not committed to Git.

```
ptekwpdev/
├── app/                # Executables (setup, provision, teardown, edit)
  └── logs/             # Setup logs
  └── assets/           # Local plugins, themes, and static assets deployed to Assets Container, available to all projects
    └── plugins/        # Static plugin archives - unversioned plugins go here. Versioned plugins at ./name/version/my-plugin.1.1.2.zip.
    └── themes/         # Static theme archives - versioned by ./name/version/my-theme.1.0.2.zip
    └── static/         # Other Static assets (templates, ini, cfg, images, css, etc)
    └── docker/         # Docker Context for container management
├── bin/                # Executables (setup, provision, teardown, edit)
├── config/             # Deployment templates
  └── docker/           # App Docker Context
  └── wordpress/        # Wordpress config, extra php.ini, etc
  └── sqldb/            # Wordpress SQL DB 
├── lib/                # Shared Bash functions (logging, error handling, envsubst)
└── docs/               # Usage guides

~/.ptekwpdev/
├── environments.json   # App config and deployment projects
├── docker-templates/   # Compose + Dockerfile templates
├── certs/              # SSL certs per environment
└── assets/             # Shared plugins/themes

$PROJECT_BASE/          # Deployed Environment/Project
├── app                 # log files and other app-generated assets
├── docker              # Docker context
├── config/             # Config and templates for various containerized apps
└── assets/             # Shared plugins/themes
```

---

## ⚙️ Installation

1. Clone the repository:
   ```
   git clone https://github.com/ccnicholls99/ptekwpdev.git ~/projects/ptekwpdev
   cd ~/projects/ptekwpdev
   ```

2. Run the setup script:
   ```
   ./bin/setup.sh
   ```
   - Creates `$HOME/.ptekwpdev`
   - Copies default templates
   - Adds `ptekwpdev/bin` to your `$PATH`

---

## 🚀 Quickstart

```
# Create a new environment
provision.sh demo-site

# Edit environment settings
edit.sh demo-site

# Teardown environment
teardown.sh demo-site
```

Each environment is created in its own project directory (e.g., `~/projects/demo-site`) and can be committed as a standalone Git repository.

---

## 🔐 Best practices

- Use `envsubst` for variable expansion in templates
- Keep secrets in `.dev` files (never commit them)
- Ensure idempotent operations (scripts check directories before copying)
- SSL certs are auto-generated per hostname and stored in `~/.ptekwpdev/certs`

---

## 📊 Architecture diagram

```
        ┌──────────────┐
        │   NGINX      │  ← Reverse Proxy + SSL
        └─────┬────────┘
              │
 ┌────────────┴────────────┐
 │                         │
 │      WordPress          │
 │                         │
 └────────────┬────────────┘
              │
      ┌───────┴────────┐
      │   MariaDB      │
      └───────┬────────┘
              │
      ┌───────┴────────┐
      │ phpMyAdmin     │
      └────────────────┘

Shared Assets Volume → Plugins, Themes, Attachments
WP-CLI Container → Automation tasks
```

---

## 🤝 Contributing

Contributions are welcome!  
- Fork the repo and create a feature branch.  
- Add new templates or extend functionality.  
- Submit a pull request with clear commit messages.  

For community projects (e.g., fishing co-op, Poker Run), symbolic hostnames (`marlin.dev`, `pelican.dev`) can be added to reflect local identity.

---

## 📜 License

MIT License – free to use, modify, and distribute.

## 📜 Provisioning Flow

```mermaid
flowchart TD

    %% ============================
    %% GLOBAL CONFIG (APP LEVEL)
    %% ============================

    A1[app.json\napp_base, config_base, project_base\nbackend_network, database, wordpress_defaults]
    A2[app_config.sh\n(appcfg accessor)]
    A3[app_deploy.sh\nGlobal provisioning]

    A1 --> A2 --> A3

    A3 --> A4[Global Backend Network]
    A3 --> A5[Global SQLDB Container\nptekwpdev_db]
    A3 --> A6[Global SQL Admin Container]
    A3 --> A7[Global Assets Volume\nptekwpdev_assets_volume]


    %% ============================
    %% PROJECT CONFIG (PER PROJECT)
    %% ============================

    B1[environments.json\nprojects.{key}\nproject_domain, project_network, base_dir\nwordpress.*, secrets.*, dev_sources.*]
    B2[project_deploy.sh]
    B3[derived_json\n(lowercase merged config)]
    B4[env.project.tpl]
    B5[.env (project env vars)]

    B1 --> B2 --> B3 --> B4 --> B5


    %% ============================
    %% PROJECT RUNTIME (DOCKER)
    %% ============================

    B5 --> C1[compose.project.yml]

    C1 --> C2[wp container\nWordPress]
    C1 --> C3[wpcli container]
    C1 --> C4[proxy container\nNGINX]

    C1 --> C5[frontend network\nname=${FRONTEND_NETWORK}]
    C1 --> C6[backend network\nname=${BACKEND_NETWORK}]

    C2 --> C6
    C3 --> C6
    C4 --> C5


    %% ============================
    %% DATABASE CONNECTION
    %% ============================

    C2 -->|SQLDB_HOST| A5


    %% ============================
    %% PROXY ROUTING
    %% ============================

    C4 -->|server_name PROJECT_DOMAIN| C2


    %% ============================
    %% DEV SOURCES + ASSETS
    %% ============================

    B2 --> D1[dev_sources deployment\nplugins/themes]
    C2 --> D2[Assets Volume\nptekwpdev_assets_volume]