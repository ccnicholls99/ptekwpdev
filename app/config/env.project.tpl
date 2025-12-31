# --------------------------------------------------------------------
# Project-specific Environment Settings for ptekwpdev project {{project_name}}
# --------------------------------------------------------------------

# Project identity
PROJECT_NAME={{project_name}}
PROJECT_TITLE={{project_title}}
PROJECT_DESCRIPTION={{project_description}}
PROJECT_DOMAIN={{project_domain}}
PROJECT_REPO={{project_repo}}

# Docker Networks
FRONTEND_NETWORK={{project_network}}
BACKEND_NETWORK={{backend_network}}

# SQL Database values
SQLDB_HOST={{database.host}}
SQLDB_NAME={{secrets.sqldb_name}}
SQLDB_USER={{secrets.sqldb_user}}
SQLDB_PASSWORD={{secrets.sqldb_pass}}

# WordPress project values
WORDPRESS_IMAGE={{wordpress.image}}
WORDPRESS_HOST={{wordpress.host}}
WORDPRESS_PORT={{wordpress.port}}
WORDPRESS_SSL_PORT={{wordpress.ssl_port}}

WORDPRESS_ADMIN_USER={{secrets.wp_admin_user}}
WORDPRESS_ADMIN_EMAIL={{secrets.wp_admin_email}}
WORDPRESS_ADMIN_PASSWORD={{secrets.wp_admin_pass}}

# Volumes (managed in compose.project.yml)
# VOL_WORDPRESS_CORE=../wordpress
# VOL_SQLDB=../sql-data