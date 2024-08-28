#!/bin/sh

##########################################################################
# COPYRIGHT Ericsson 2022
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
##########################################################################

# UTILITIES
_GREP=/bin/grep
_SED=/bin/sed
_AWK=/bin/awk

SCRIPT_NAME="${0}"
LOG_TAG="CMEventsSubscription"

readonly PG_CLIENT=@postgres.client@
readonly INSTALL_PATH=@install-path@
readonly DDL_PATH=${INSTALL_PATH}/ddl
readonly PG_USER=@postgres.user@
readonly PG_HOSTNAME=${POSTGRES_SERVICE:-postgresql01}
readonly DB=@cmsubdb.databaseName@
readonly DB_ROLE=@cmsubdb.role.name@
readonly DB_ROLE_PSW=@cmsubdb.role.password@

PGPASSWORD=""
LOGIN_TO_PG_SUPERUSER=""
DP_USER_LOGIN_AND_CONNECT_TO_DP_DB="${PG_CLIENT} postgresql://${DB_ROLE}:${DB_ROLE_PSW}@${PG_HOSTNAME}/${DB} "
SCHEMA_VERSION_QUERY="SELECT version FROM version ORDER BY version DESC LIMIT 1;"
DOES_NOT_EXIST_STRING="does not exist"
DATABASE_STRING="database"
RELATION_STRING="relation"
NUM_TRIES_FOR_CREATEROLE=3
WAIT_TIME_FOR_CREATEROLE=1
LATEST_DDL_VERSION=$(find ${DDL_PATH} -name "CMSubscriptionEvents?*.ddl" -exec basename {} \; | sort --version-sort | tail -n 1 | ${_SED} 's/CMSubscriptionEventsSchema?_//' | ${_SED} 's/\.[^.]*$//' | ${_SED} 's/\_/./g')
INITIAL_INSTALL_VERSION=0
DDL_FILES_AVAILABLE=$(find ${DDL_PATH} -name "CMSubscriptionEvents?*.ddl" -exec basename {} \; | sort --version-sort)

# SOURCE PG Util methods FROM ERICpostgresutils_CXP9038493
source /ericsson/enm/pg_utils/lib/pg_syslog_library.sh
source /ericsson/enm/pg_utils/lib/pg_dblock_library.sh
source /ericsson/enm/pg_utils/lib/pg_password_library.sh
source /ericsson/enm/pg_utils/lib/pg_dbcreate_library.sh
source /ericsson/enm/pg_utils/lib/pg_rolecreate_library.sh

#///////////////////////////////////////////////////////////////
# This function will check the exit code
# Arguments:
#       $1 - function calling checkExitCode
# Return: 0 if success
#         exit 1 on failure
#//////////////////////////////////////////////////////////////
checkExitCode() {
  if [ $? -eq 0 ];  then
    return 0;
  fi
  error "Step $1 failed. Exiting..."
  exit 1
}

#///////////////////////////////////////////////////////////////
# Function used for creating database ${DB} and role ${DB_ROLE}.
# Arguments: None
# Return: 0 if success
#         return 1 on failure.
#//////////////////////////////////////////////////////////////
setupDatabase() {
  output=$( ${LOGIN_TO_PG_SUPERUSER} -c '\l' )

  # Check if role and DB exists
  echo "${output}" | ${_GREP} -w "${DB}" | ${_GREP} -wq "${DB_ROLE}"
  if [ $? -eq 0 ]; then
    info "DB '$DB' and Role '$DB_ROLE' already exists, Can Continue..."
    return 0
  fi

  info "Creating DB '$DB'..."
  if ! createDb; then
    error "Database '$DB' could not be created. Exiting with error.";
    return 1
  fi

  info "Creating role '$DB_ROLE' for DB '$DB'..."
  if ! role_create; then
    error "'$DB_ROLE' Role creation failed for DB '$DB'."
    return 1
  fi

  info "Changing ownership to role '$DB_ROLE' for DB '$DB'..."
  if ! change_db_ownership; then
    error "'$DB_ROLE' Role ownership change failed for DB '$DB'."
    return 1
  fi

  info "Granting Connect privilege for role '$DB_ROLE' on DB '$DB'..."
  if ! grant_connect_privilege_on_database_for_role; then
    error "Failure in granting Connect privilege for role '$DB_ROLE' on DB '$DB'..."
    return 1
  fi

  info "Revoking public Connect privilege for role '$DB_ROLE'..."
  if ! revoke_connect_for_user_on_database; then
    error "Failure attempting to Revoke public Connect privilege for role '$DB_ROLE'"
    return 1
  fi

  info "DB '$DB' and Role '$DB_ROLE' exists, Can Continue..."
  return 0;
}

#///////////////////////////////////////////////////////////////
# A retry mechanism for Database and Role creation
# Arguments: None
# Return: 0 if success
#         exit 1 on failure.
#//////////////////////////////////////////////////////////////
waitForSetupDatabase(){
  retry=0
  while [ $retry -le $NUM_TRIES_FOR_CREATEROLE ]; do
    info "Checking Database '$DB' and Role '$DB_ROLE' exists"
    setupDatabase
    if [ $? -eq 0 ]; then
      break
    fi
    if [ $retry -eq $NUM_TRIES_FOR_CREATEROLE ]; then
      error "Database '$DB'and Role '$DB_ROLE' does not exist after ${NUM_TRIES_FOR_CREATEROLE} attempts. Exiting with error."
      exit 1
    fi
    info "Waiting for ${WAIT_TIME_FOR_CREATEROLE} seconds to check database and role is created on the server "
    sleep ${WAIT_TIME_FOR_CREATEROLE}
    retry=$(( retry + 1 ))
  done
}

#///////////////////////////////////////////////////////////////
# Function used for checking connection to postgres server
# Arguments: None
# Return: 0 if success
#         exit 1 on failure.
#//////////////////////////////////////////////////////////////
serviceCheck() {
  is_running=$( ${LOGIN_TO_PG_SUPERUSER} -A -t -c 'select true;' 2>&1 )
  if [ $? -eq 0 ]; then
    info "Postgres is running on ${PG_HOSTNAME}. we can now deploy database ${DB} objects!"
  else
    error "Postgres is not running on ${PG_HOSTNAME}. Hence cannot install database ${DB} Objects at this time. Error : ${is_running}"
    exit 1
  fi
}

#///////////////////////////////////////////////////////////////
# Finds the schema version to be executed.
# Arguments: None
# Return: 0 if success
#         exit 1 on failure.
#//////////////////////////////////////////////////////////////
executeCMSubscriptionEventsSchema() {
  lockDb
  if [ $? -ne 0 ]; then
     error "Lock not acquired for database ${DB}: an error occurred or another instance has lock ownership."
     exit 1;
  fi
  trap 'unlockDb' EXIT
  info "Determining ${DB} schema version."
  queryResult=$( ${DP_USER_LOGIN_AND_CONNECT_TO_DP_DB} -A -t -c "${SCHEMA_VERSION_QUERY}" 2>&1 )
  if [ $? -eq 0 ];  then
     local current_ddl_version=$queryResult
     info "Current Schema version = ${current_ddl_version}."
     info "Latest DDL version available = ${LATEST_DDL_VERSION}"
     executeSchema "$current_ddl_version"
  elif echo "$queryResult" | grep -Eq "($DOES_NOT_EXIST_STRING)" && echo "$queryResult" | grep -Eq "($RELATION_STRING)" ; then
     info "Database ${DB} is empty. Involving schema creation..."
     executeSchema "$INITIAL_INSTALL_VERSION"
  else
     handleQueryErrors "${queryResult}"
  fi
}

#///////////////////////////////////////////////////////////////
# Function to handle errors after running the sql statement.
# Arguments: queryResult
# Return: 0 if success
#         exit 1 on failure.
#//////////////////////////////////////////////////////////////
handleQueryErrors() {
  queryResult=$1
  if echo "$queryResult" | grep -Eq "($DOES_NOT_EXIST_STRING)" && echo "$queryResult" | grep -Eq "($DATABASE_STRING)" ; then
     error "Database ${DB} does not exist."
  else
     error "Unable to determine the schema version."
  fi
  error "Exiting with error, $queryResult"
  exit 1
}

#///////////////////////////////////////////////////////////////
# The schema to be executed.
# Arguments: schema version
# Return: 0 if success
#         exit 1 on failure.
#//////////////////////////////////////////////////////////////
executeSchema() {
  for ddlFile in $DDL_FILES_AVAILABLE
    do
     ddlVersion=$(echo "${ddlFile}" | "${_SED}" "s/CMSubscriptionEventsSchema_//" | "${_SED}" "s/\.[^.]*$//" | "${_SED}" "s/\_/./g")
     if [ "$ddlVersion" -gt "$1" ]; then #Verifying if the available ddl versions are greater than current ddl version
        info "ddl version to be executed : ${ddlVersion}"
        applyCMSubscriptionEventsSchemaVersion "${DDL_PATH}/${ddlFile}"
        verifyVersion "${ddlVersion}"
     fi
    done
}

#///////////////////////////////////////////////////////////////
# Helper function used by executeSchema.
# Arguments: schema version
# Return: 0 if success
#         exit 1 on failure.
#//////////////////////////////////////////////////////////////
applyCMSubscriptionEventsSchemaVersion() {
    local CMSubscriptionEventsSchema_ddl=$1
    info "ddl to be executed = ${CMSubscriptionEventsSchema_ddl}"
    ${DP_USER_LOGIN_AND_CONNECT_TO_DP_DB} -q -w -f "${CMSubscriptionEventsSchema_ddl}"
    checkExitCode "applyCMSubscriptionEventsSchemaVersion"
}

#///////////////////////////////////////////////////////////////
# Function to verify the correct schema version is executed.
# Arguments: schema version
# Return: 0 if success
#         exit 1 on failure.
#//////////////////////////////////////////////////////////////
verifyVersion() {
  queryResult=$( ${DP_USER_LOGIN_AND_CONNECT_TO_DP_DB} -A -t -c "${SCHEMA_VERSION_QUERY}" 2>&1 )
  if [ $? -eq 0 ];  then
     local current_ddl_version=$queryResult
     if [ "$1" -eq "$current_ddl_version" ]; then #Verifying if the Latest ddl version is equal to current ddl version
        info "Version $1 installed successfully"
        return 0;
     fi
  fi
  error "Error applying schema version $1 . Exiting with error, $queryResult"
  exit 1
}

#///////////////////////////////////////////////////////////////////////
# Fetches the postgres user password
#///////////////////////////////////////////////////////////////////////
fetchpassword() {
  export_password
  LOGIN_TO_PG_SUPERUSER="${PG_CLIENT} postgresql://${PG_USER}:${PGPASSWORD}@${PG_HOSTNAME} "
}

#*Main*
fetchpassword
serviceCheck
waitForSetupDatabase
executeCMSubscriptionEventsSchema

exit 0