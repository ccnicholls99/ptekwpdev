# --------------------------------------------------------------------
# App-wide Environment Settings for ptekwpdev
# --------------------------------------------------------------------

# Network for backend containers
BACKEND_NETWORK={{backend_network}}

# SQL Database root credentials (used by app-wide DB container)
SQLDB_PORT={{sqldb_port}}
MYSQL_ROOT_USER={{sqldb_root}}
MYSQL_ROOT_PASSWORD={{sqldb_root_pass}}

# Paths
BUILD_HOME={{build_home}}
PROJECT_BASE={{project_base}}

# SQL Admin defaults
SQLADMIN_IMAGE={{sqladmin_image}}
SQLADMIN_PORT={{sqladmin_port}}
