# --------------------------------------------------------------------
# App-wide Environment Settings for ptekwpdev
# --------------------------------------------------------------------

# SQL Database root credentials (used by app-wide DB container)
SQLDB_PORT={{sqldb_port}}
MYSQL_ROOT_USER={{sqldb_root}}
MYSQL_ROOT_PASSWORD={{sqldb_root_pass}}

# Paths
BUILD_HOME={{build_home}}
PROJECT_BASE={{project_base}}
NETWORK_NAME={{docker_network}}

# SQL Admin defaults
SQLADMIN_IMAGE={{sqladmin_image}}
SQLADMIN_PORT={{sqladmin_port}}
