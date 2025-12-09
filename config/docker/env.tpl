# --------------------------------------------------------------------
# Environment Settings for ptekwpdev project %project_name%
# --------------------------------------------------------------------
# The project name - used as a prefix for all container & project names
PROJECT_NAME=^project_name^
PROJECT_DOMAIN=^project_domain^
PROJECT_TITLE="^project_title^"

# SQL Database values
SQLDB_IMAGE=mariadb
SQLDB_VERSION=10.5
SQLDB_NAME=^sqldb_name^
SQLDB_USER=^sqldb_user^
SQLDB_PASSWORD=^sqldb_pass^
SQLDB_ROOT_PASSWORD=^sqldb_root_pass^

# SQL Admin
SQLADMIN_IMAGE=phpmyadmin
SQLADMIN_PORT=5211

# Wordpress values
WORDPRESS_IMAGE=php8.1
WORDPRESS_ADMIN_USER=^wp_admin_user^
WORDPRESS_ADMIN_EMAIL=^wp_admin_email^
WORDPRESS_ADMIN_PASSWORD=^wp_admin_pass^
WORDPRESS_DEBUG=0
WORDPRESS_DEBUG_LOG=false
WORDPRESS_DISABLE_FATAL=true
WORDPRESS_SCHEME=http
WORDPRESS_PORT=5210
WORDPRESS_HOST=wordpress

# Assorted Volumes
VOL_WORDPRESS_CORE=../wordpress
VOL_WORDPRESS_APP=../app
VOL_SQLDB=../sql-data
