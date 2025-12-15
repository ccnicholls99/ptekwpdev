# --------------------------------------------------------------------
# Environment Settings for ptekwpdev project %project_name%
# --------------------------------------------------------------------
# The project name - used as a prefix for all container & project names
PROJECT_NAME=^project_name^
PROJECT_DOMAIN=^project_domain^
PROJECT_TITLE="^project_title^"

# SQL Database values
SQLDB_IMAGE=^sqldb_image^
SQLDB_VERSION=^sqldb_version^
SQLDB_NAME=^sqldb_name^
SQLDB_USER=^sqldb_user^
SQLDB_PASSWORD=^sqldb_pass^
SQLDB_ROOT_PASSWORD=^sqldb_root_pass^

# SQL Admin
SQLADMIN_IMAGE=^sqladmin_image^
SQLADMIN_PORT=^sqladmin_port^

# Wordpress values
WORDPRESS_IMAGE=^wordpress_image^
WORDPRESS_ADMIN_USER=^wp_admin_user^
WORDPRESS_ADMIN_EMAIL=^wp_admin_email^
WORDPRESS_ADMIN_PASSWORD=^wp_admin_pass^
WORDPRESS_DEBUG=0
WORDPRESS_DEBUG_LOG=false
WORDPRESS_DISABLE_FATAL=true
WORDPRESS_SCHEME=http
WORDPRESS_PORT=^wordpress_port^
WORDPRESS_HOST=^wordpress_host^

# Assorted Volumes
VOL_WORDPRESS_CORE=../wordpress
VOL_WORDPRESS_APP=../app
VOL_SQLDB=../sql-data
