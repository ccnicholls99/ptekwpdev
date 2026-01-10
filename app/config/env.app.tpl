# ==============================================================================
#  PTEKWPDEV — App-Level Environment Template
#  Used by app_deploy.sh to generate CONFIG_BASE/docker/.env
# ==============================================================================

# ----------------------------------------------------------------------
# Networking
# ----------------------------------------------------------------------
BACKEND_NETWORK={{backend_network}}

# ----------------------------------------------------------------------
# Database Engine (MariaDB)
# ----------------------------------------------------------------------
SQLDB_CONTAINER={{database.sqldb_container}}
SQLDB_IMAGE={{database.sqldb_image}}
SQLDB_VERSION={{database.sqldb_version}}
SQLDB_PORT={{database.sqldb_port}}

SQLDB_ROOT_USER={{secrets.sqldb_root}}
SQLDB_ROOT_PASS={{secrets.sqldb_root_pass}}

# ----------------------------------------------------------------------
# SQL Admin (phpMyAdmin)
# ----------------------------------------------------------------------
SQLADMIN_CONTAINER={{database.sqladmin_container}}
SQLADMIN_IMAGE={{database.sqladmin_image}}
SQLADMIN_VERSION={{database.sqladmin_version}}
SQLADMIN_PORT={{database.sqladmin_port}}

# ----------------------------------------------------------------------
# Assets Container (if used by core services)
# ----------------------------------------------------------------------
ASSETS_CONTAINER={{assets.container}}