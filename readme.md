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

## 📂 Directory Layout

- **Repository root:** `$HOME/projects/ptekwpdev`  
  Contains app source, scripts, and templates. Managed via Git.

ptekwpdev/ 
├── bin/                # Executables (setup, provision, teardown, edit) 
├── templates/          # Dockerfiles, docker-compose.yml, env templates 
├── lib/                # Shared Bash functions (logging, error handling, envsubst) 
└── docs/               # Usage guides

- **User config:** `$HOME/.ptekwpdev`  
  Stores environment templates, SSL certs, and shared assets. Not committed to Git.

~/.ptekwpdev/ 
├── env-templates/      # Base .env files 
├── docker-templates/   # Compose + Dockerfile templates 
├── certs/              # SSL certs per environment └── assets/             # Shared plugins/themes


---

## ⚙️ Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ccnicholls99/ptekwpdev.git ~/projects/ptekwpdev
   cd ~/projects/ptekwpdev

2. Run the setup script:
    ```bash
    ./bin/setup.sh

## 🚀 Usage
Create a new environment
    ```bash
    provision.sh myproject

- Generates .env, docker-compose.yml, and Dockerfiles in ~/projects/myproject
- Starts containers with docker compose up -d

Edit an environment
    ```bash
    edit.sh myproject

- Opens .env for editing
- Supports regenerating SSL certs or updating templates

Teardown an environment
    ```bash
    teardown.sh myproject

- Stops and removes containers
- Cleans volumes and certs if desired


