Full Lifecycle Test Guide

This document describes the steps to run a complete lifecycle test of the WordPress development environment.

1. Provision

```make provision PROJECT=demo

Expected:
    * Creates PROJECT_BASE (resolved as app.project_base + base_dir).
    * Scaffolds app, bin, docker, src, plus app/config/docker and app/config/nginx.
    * Generates .env file with defaults.
    * Log written to PROJECT_BASE/app/logs/provision.log.

2. Certificates

```make certs PROJECT=demo

Expected:
    * Generates SSL certs under PROJECT_BASE/docker/config/ssl.
    * Uses openssl by default (or mkcert if specified).
    * Status check available via bin/generate_certs.sh --status --project demo.
    * Log written to PROJECT_BASE/app/logs/generate_certs.log.

3. Build

```make build PROJECT=demo

Expected:
    * Runs docker compose -f app/config/docker/compose.build.yml up -d --build.
    * Verifies source mount inside demo_wp container.
    * Log written to PROJECT_BASE/app/logs/build.log.

4. Auto-install

```make autoinstall PROJECT=demo

Expected:
    * Loads .env from PROJECT_BASE.
    * Runs wp core install inside demo_wp container.
    * Log written to PROJECT_BASE/app/logs/autoinstall.log.

5. Assets

```make assets ACTION=build

Expected:
    * Builds ptekwpdev-assets container.
    * Copies existing assets from APP_BASE/app/assets into container.
    * Log written to APP_BASE/app/logs/assets.log.

What to Watch For
    * Directory creation: Confirm app/config/docker and app/config/nginx exist after provisioning.
    * Logging: Each step should append to its own log file under app/logs.
    * Path resolution: No PROJECT_BASE//... double slashes.

Container names: 
    * demo_wp for WordPress
    * ptekwpdev-assets for assets.

Certs: 
    * Check docker/config/ssl contains .crt and .key.

Assets: 
    * Verify copied plugins/themes/static inside container at /usr/src/ptekwpdev/assets.

