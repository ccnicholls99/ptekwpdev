# --------------------------------------------------------------------
# Project-specific Environment Settings for ptekwpdev project {{project_name}}
# --------------------------------------------------------------------

# Project identity
PROJECT_NAME={{project_name}}
PROJECT_DOMAIN={{project_domain}}
PROJECT_TITLE="{{project_title}}"
PROJECT_BASE={{project_base}}
BUILD_HOME={{build_home}}

# Docker Network
FRONTEND_NETWORK={{project_network}}

# SQL Database values
SQLDB_IMAGE={{sqldb_image}}
SQLDB_VERSION={{sqldb_version}}
SQLDB_NAME={{sqldb_name}}
SQLDB_USER={{sqldb_user}}
SQLDB_PASSWORD={{sqldb_pass}}

# Wordpress project values
WORDPRESS_IMAGE={{wordpress_image}}
WORDPRESS_ADMIN_USER={{wp_admin_user}}
WORDPRESS_ADMIN_EMAIL={{wp_admin_email}}
WORDPRESS_ADMIN_PASSWORD={{wp_admin_pass}}
WORDPRESS_PORT={{wordpress_port}}
WORDPRESS_HOST={{wordpress_host}}

# Assorted Volumes (project-local)
VOL_WORDPRESS_CORE=../wordpress
VOL_WORDPRESS_APP=../app
VOL_SQLDB=../sql-data