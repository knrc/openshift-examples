function configure_server_identities() {
  if [ -n "$SSL_KEYSTORE_PATH" ]; then
    echo "Using SSL_KEYSTORE_PATH to configure HotRod SSL keystore"
    KEYSTORE_PATH="$SSL_KEYSTORE_PATH"
    KEYSTORE_RELATIVE_TO="$SSL_KEYSTORE_RELATIVE_TO"
  elif [ -n "$HTTPS_KEYSTORE" ]; then
    echo "Using HTTPS_KEYSTORE to configure HotRod SSL keystore"
    KEYSTORE_PATH="${HTTPS_KEYSTORE_DIR}/${HTTPS_KEYSTORE}"
    KEYSTORE_RELATIVE_TO=""
  else
    echo "WARNING! Neither SSL_KEYSTORE_PATH nor HTTPS_KEYSTORE is set. HotRod SSL will not be configured."
  fi

  if [ -n "$SSL_KEYSTORE_PASSWORD" ]; then
    echo "Using SSL_KEYSTORE_PASSWORD for the HotRod SSL keystore"
    KEYSTORE_PASSWORD="$SSL_KEYSTORE_PASSWORD"
  elif [ -n "$HTTPS_PASSWORD" ] ; then
    echo "Using HTTPS_PASSWORD for the HotRod SSL keystore"
    KEYSTORE_PASSWORD="$HTTPS_PASSWORD"
  else
    echo "WARNING! Neither SSL_KEYSTORE_PASSWORD nor HTTPS_PASSWORD is set. HotRod SSL will not be configured."
  fi


  if [ -n "$KEYSTORE_PATH$SECRET_VALUE" ]; then
    if [ -n "$KEYSTORE_PATH" -a -n "$KEYSTORE_PASSWORD" ]; then
      if [ -n "$SSL_PROTOCOL" ]; then
        SSL_PROTOCOL="protocol=\"$SSL_PROTOCOL\""
      fi
      if [ -n "$KEYSTORE_RELATIVE_TO" ]; then
        SSL_KEYSTORE_RELATIVE_TO="relative-to=\"$KEYSTORE_RELATIVE_TO\""
      fi
      if [ -n "$SSL_KEYSTORE_ALIAS" ]; then
        SSL_KEYSTORE_ALIAS="alias=\"$SSL_KEYSTORE_ALIAS\""
      fi
      if [ -n "$SSL_KEY_PASSWORD" ]; then
        SSL_KEY_PASSWORD="key-password=\"$SSL_KEY_PASSWORD\""
      fi
      ssl="\
          <ssl $SSL_PROTOCOL>\
            <keystore path=\"$KEYSTORE_PATH\" keystore-password=\"$KEYSTORE_PASSWORD\" $SSL_KEYSTORE_RELATIVE_TO $SSL_KEYSTORE_ALIAS $SSL_KEY_PASSWORD/>\
          </ssl>"
    fi
    if [ -n "$SECRET_VALUE" ]; then
      secret="\
          <secret value=\"$SECRET_VALUE\"/>"
    fi
    serverids="\
        <server-identities>$ssl$secret\
        </server-identities>"
  fi
  sed -i "s|<!-- ##SERVER_IDENTITIES## -->|$serverids|" "$CONFIG_FILE"
}

function configure_infinispan_core() {
  if [ -n "$CACHE_CONTAINER_START" ]; then
    CACHE_CONTAINER_START="start=\"$CACHE_CONTAINER_START\""
  fi
  if [ -n "$CACHE_CONTAINER_STATISTICS" ]; then
    CACHE_CONTAINER_STATISTICS="statistics=\"$CACHE_CONTAINER_STATISTICS\""
  fi
  if [ -n "$TRANSPORT_LOCK_TIMEOUT" ]; then
    locktimeout=" lock-timeout=\"$TRANSPORT_LOCK_TIMEOUT\""
  fi
  # We must always have a transport for a clustered cache otherwise it is treated as a local cache
  transport="\
                <transport$locktimeout/>"

  if [ -z "$CACHE_NAMES" ]; then
    CACHE_NAMES="default,memcached"
    MEMCACHED_CACHE="memcached"
  fi

  IFS=',' read -a cachenames <<< "$CACHE_NAMES"
  if [ "${#cachenames[@]}" -ne "0" ]; then
    FIRST_CACHE=${cachenames[0]}
    export DEFAULT_CACHE=${DEFAULT_CACHE:-$FIRST_CACHE}
    for cachename in ${cachenames[@]}; do
      configure_cache $cachename
    done
  fi
  configure_container_security

  subsystem="\
        <subsystem xmlns=\"urn:infinispan:server:core:6.3\" default-cache-container=\"clustered\">\
            <cache-container name=\"clustered\" default-cache=\"$DEFAULT_CACHE\" $CACHE_CONTAINER_START $CACHE_CONTAINER_STATISTICS>$transport $caches $containersecurity\
            </cache-container>\
            <cache-container name=\"security\"/>\
        </subsystem>"

  sed -i "s|<!-- ##INFINISPAN_CORE## -->|$subsystem|" "$CONFIG_FILE"
}

function configure_cache() {
  local CACHE_NAME=$1
  local prefix=${1^^}
  local CACHE_MODE=$(find_env "${prefix}_CACHE_MODE" "SYNC")
  local CACHE_TYPE=$(find_env "${prefix}_CACHE_TYPE" "distributed")

  if [ -n "$(find_env "${prefix}_CACHE_START")" ]; then
    local CACHE_START="start=\"$(find_env "${prefix}_CACHE_START")\""
  fi
  if [ -n "$(find_env "${prefix}_CACHE_BATCHING")" ]; then
    local CACHE_BATCHING="batching=\"$(find_env "${prefix}_CACHE_BATCHING")\""
  fi
  if [ -n "$(find_env "${prefix}_CACHE_STATISTICS")" ]; then
    local CACHE_STATISTICS="statistics=\"$(find_env "${prefix}_CACHE_STATISTICS")\""
  fi
  if [ -n "$(find_env "${prefix}_CACHE_QUEUE_SIZE")" ]; then
    local CACHE_QUEUE_SIZE="queue-size=\"$(find_env "${prefix}_CACHE_QUEUE_SIZE")\""
  fi
  if [ -n "$(find_env "${prefix}_CACHE_QUEUE_FLUSH_INTERVAL")" ]; then
    local CACHE_QUEUE_FLUSH_INTERVAL="queue-flush-interval=\"$(find_env "${prefix}_CACHE_QUEUE_FLUSH_INTERVAL")\""
  fi
  if [ -n "$(find_env "${prefix}_CACHE_REMOTE_TIMEOUT")" ]; then
    local CACHE_REMOTE_TIMEOUT="remote-timeout=\"$(find_env "${prefix}_CACHE_REMOTE_TIMEOUT")\""
  fi
  if [ "$(find_env "${prefix}_CACHE_TYPE")" = "distributed" ]; then
    if [ -n "$(find_env "${prefix}_CACHE_OWNERS")" ]; then
      local CACHE_OWNERS="owners=\"$(find_env "${prefix}_CACHE_OWNERS")\""
    fi
    if [ -n "$(find_env "${prefix}_CACHE_SEGMENTS")" ]; then
      local CACHE_SEGMENTS="segments=\"$(find_env "${prefix}_CACHE_SEGMENTS")\""
    fi
    if [ -n "$(find_env "${prefix}_CACHE_L1_LIFESPAN")" ]; then
      local CACHE_L1_LIFESPAN="l1-lifespan=\"$(find_env "${prefix}_CACHE_L1_LIFESPAN")\""
    fi
  fi
  if [ -n "$(find_env "${prefix}_CACHE_EVICTION_STRATEGY")$(find_env "${prefix}_CACHE_EVICTION_MAX_ENTRIES")" ]; then
    if [ -n "$(find_env "${prefix}_CACHE_EVICTION_STRATEGY")" ]; then
      local CACHE_EVICTION_STRATEGY="strategy=\"$(find_env "${prefix}_CACHE_EVICTION_STRATEGY")\""
    fi
    if [ -n "$(find_env "${prefix}_CACHE_EVICTION_MAX_ENTRIES")" ]; then
      local CACHE_EVICTION_MAX_ENTRIES="max-entries=\"$(find_env "${prefix}_CACHE_EVICTION_MAX_ENTRIES")\""
    fi

    local eviction="\
                    <eviction $CACHE_EVICTION_STRATEGY $CACHE_EVICTION_MAX_ENTRIES/>"
  fi
  if [ -n "$(find_env "${prefix}_CACHE_EXPIRATION_LIFESPAN")$(find_env "${prefix}_CACHE_EXPIRATION_MAX_IDLE")$(find_env "${prefix}_CACHE_EXPIRATION_INTERVAL")" ]; then
    if [ -n "$(find_env "${prefix}_CACHE_EXPIRATION_LIFESPAN")" ]; then
      local CACHE_EXPIRATION_LIFESPAN="lifespan=\"$(find_env "${prefix}_CACHE_EXPIRATION_LIFESPAN")\""
    fi
    if [ -n "$(find_env "${prefix}_CACHE_EXPIRATION_MAX_IDLE")" ]; then
      local CACHE_EXPIRATION_MAX_IDLE="max-idle=\"$(find_env "${prefix}_CACHE_EXPIRATION_MAX_IDLE")\""
    fi
    if [ -n "$(find_env "${prefix}_CACHE_EXPIRATION_INTERVAL")" ]; then
      local CACHE_EXPIRATION_INTERVAL="interval=\"$(find_env "${prefix}_CACHE_EXPIRATION_INTERVAL")\""
    fi

    local expiration="\
                    <expiration $CACHE_EXPIRATION_LIFESPAN $CACHE_EXPIRATION_MAX_IDLE $CACHE_EXPIRATION_INTERVAL/>"
  fi

  if [ -n "$(find_env "${prefix}_CACHE_INDEX")$(find_env "${prefix}_INDEXING_PROPERTIES")" ]; then
    if [ -n "$(find_env "${prefix}_CACHE_INDEX")" ]; then
      local index="index=\"$(find_env "${prefix}_CACHE_INDEX")\""
    fi
    if [ -n "${prefix}_INDEXING_PROPERTIES" ]; then
      IFS=',' read -a properties <<< "$(find_env "${prefix}_INDEXING_PROPERTIES")"
      if [ "${#properties[@]}" -ne "0" ]; then
        for property in ${properties[@]}; do
          local name=${property%=*}
          local value=${property#*=}
          local indexingprops+="\
                        <property name=\"$name\">$value</property>"
        done
      fi
    fi

    local indexing="\
                    <indexing $index>$indexingprops\
                    </indexing>"
  fi
  if [ -n "$(find_env "${prefix}_CACHE_SECURITY_AUTHORIZATION_ENABLED")$(find_env "${prefix}_CACHE_SECURITY_AUTHORIZATION_ROLES")" ]; then
    if [ -n "$(find_env "${prefix}_CACHE_SECURITY_AUTHORIZATION_ENABLED")" ]; then
      local CACHE_SECURITY_AUTHORIZATION_ENABLED="enabled=\"$(find_env "${prefix}_CACHE_SECURITY_AUTHORIZATION_ENABLED")\""
    fi
    if [ -n "$(find_env "${prefix}_CACHE_SECURITY_AUTHORIZATION_ROLES")" ]; then
      local roles="$(find_env "${prefix}_CACHE_SECURITY_AUTHORIZATION_ROLES")"
      local CACHE_SECURITY_AUTHORIZATION_ROLES="roles=\"${roles//,/ }\""
    fi

    local cachesecurity="\
                    <security>\
                      <authorization $CACHE_SECURITY_AUTHORIZATION_ENABLED $CACHE_SECURITY_AUTHORIZATION_ROLES/>\
                    </security>"
  fi
  if [ -n "$(find_env "${prefix}_CACHE_PARTITION_HANDLING_ENABLED")" ]; then
    local partitionhandling="\
                    <partition-handling enabled=\"$(find_env "${prefix}_CACHE_PARTITION_HANDLING_ENABLED")\"/>"
  fi

  configure_jdbc_store $1

  caches+="\
                <$CACHE_TYPE-cache name=\"$CACHE_NAME\" mode=\"$CACHE_MODE\" $CACHE_START $CACHE_BATCHING $CACHE_STATISTICS $CACHE_QUEUE_SIZE $CACHE_QUEUE_FLUSH_INTERVAL $CACHE_REMOTE_TIMEOUT $CACHE_OWNERS $CACHE_SEGMENTS $CACHE_L1_LIFESPAN>$eviction $expiration $jdbcstore $indexing $cachesecurity $partitionhandling\
                </$CACHE_TYPE-cache>"
}

function configure_jdbc_store() {
  local prefix=${1^^}
  if [ -n "$(find_env "${prefix}_JDBC_STORE_TYPE")" ]; then
    local JDBC_STORE_TYPE="$(find_env "${prefix}_JDBC_STORE_TYPE")"
    if [ -n "$(find_env "${prefix}_KEYED_TABLE_PREFIX")" ]; then
      local KEYED_TABLE_PREFIX="prefix=\"$(find_env "${prefix}_KEYED_TABLE_PREFIX")\""
    fi

    local JDBC_STORE_DATASOURCE=$(find_env "${prefix}_JDBC_STORE_DATASOURCE")
    local db="$(get_db_type "$JDBC_STORE_DATASOURCE")"

    case "${db}" in
      "MYSQL")
        local columns="\
                            <id-column name=\"id\" type=\"VARCHAR(255)\"/>\
                            <data-column name=\"datum\" type=\"BLOB\"/>"
        ;;
      "POSTGRESQL")
        local columns="\
                            <data-column name=\"datum\" type=\"BYTEA\"/>"
        ;;
    esac

    if [ -n "$(find_env "${prefix}_CACHE_EVICTION_STRATEGY")" -a "$(find_env "${prefix}_CACHE_EVICTION_STRATEGY")" != "NONE" ]; then
      JDBC_STORE_PASSIVATION=true
    else
      JDBC_STORE_PASSIVATION=false
    fi

    jdbcstore="\
                    <$JDBC_STORE_TYPE-keyed-jdbc-store datasource=\"$JDBC_STORE_DATASOURCE\" passivation=\"$JDBC_STORE_PASSIVATION\" shared=\"true\">\
                        <$JDBC_STORE_TYPE-keyed-table $KEYED_TABLE_PREFIX>$columns\
                        </$JDBC_STORE_TYPE-keyed-table>\
                    </$JDBC_STORE_TYPE-keyed-jdbc-store>"
  else
    jdbcstore=""
  fi
}

function get_db_type() {
  ds=$1
  IFS=',' read -a db_backends <<< $DB_SERVICE_PREFIX_MAPPING

  if [ "${#db_backends[@]}" -gt "0" ]; then
    for db_backend in ${db_backends[@]}; do

      local service_name=${db_backend%=*}
      local service=${service_name^^}
      local service=${service//-/_}
      local db=${service##*_}
      local prefix=${db_backend#*=}

      if [ "$ds" = "$(get_jndi_name "$prefix" "$service")" ]; then
        echo $db
        break
      fi 
    done
  fi
}

function configure_container_security() {
  if [ -n "$CONTAINER_SECURITY_ROLE_MAPPER$CONTAINER_SECURITY_CUSTOM_ROLE_MAPPER_CLASS$CONTAINER_SECURITY_ROLES" ]; then
    if [ -n "$CONTAINER_SECURITY_ROLE_MAPPER" ]; then
      if [ -n "$CONTAINER_SECURITY_CUSTOM_ROLE_MAPPER_CLASS" ] && [ "$CONTAINER_SECURITY_ROLE_MAPPER" == "custom-role-mapper"]; then
        local CONTAINER_SECURITY_CUSTOM_ROLE_MAPPER_CLASS="class=\"$CONTAINER_SECURITY_CUSTOM_ROLE_MAPPER_CLASS\""
      fi
      local rolemapper="\
                        <$CONTAINER_SECURITY_ROLE_MAPPER $CONTAINER_SECURITY_CUSTOM_ROLE_MAPPER_CLASS/>"
    fi
    if [ -n "$CONTAINER_SECURITY_ROLES" ]; then
      IFS=',' read -a roles <<< "$(find_env "CONTAINER_SECURITY_ROLES")"
      if [ "${#roles[@]}" -ne "0" ]; then
        for role in ${roles[@]}; do
          local rolename=${role%=*}
          local permissions=${role#*=}
          local roles+="\
                        <role name=\"$rolename\" permissions=\"$permissions\"/>"
        done
      fi
    fi

    containersecurity="\
                <security>\
                    <authorization>$rolemapper$roles\
                    </authorization>\
                </security>"
  else
    containersecurity=""
  fi
}

function configure_infinispan_endpoint() {
  IFS=',' read -a connectors <<< "$(find_env "INFINISPAN_CONNECTORS" "hotrod,memcached,rest")"
  if [ "${#connectors[@]}" -ne "0" ]; then
    for connector in ${connectors[@]}; do
      case "${connector}" in
        "hotrod")
          if [ -n "$HOTROD_SERVICE_NAME" ]; then

            HOTROD_SERVICE_NAME=`echo $HOTROD_SERVICE_NAME | sed -e 's/-/_/g' -e 's/\(.*\)/\U\1/'`
            if [ -n "$(find_env "${HOTROD_SERVICE_NAME^^}_SERVICE_HOST")" ]; then
              TOPOLOGY_EXTERNAL_HOST=$(find_env "${HOTROD_SERVICE_NAME^^}_SERVICE_HOST")
              TOPOLOGY_EXTERNAL_PORT="11333"
              topology="\
              <topology-state-transfer external-host=\"$TOPOLOGY_EXTERNAL_HOST\" external-port=\"$TOPOLOGY_EXTERNAL_PORT\"/>"
            fi
          fi
          if [ -n "$HOTROD_AUTHENTICATION" ]; then
            authentication="\
              <authentication security-realm=\"ApplicationRealm\">\
                  <sasl server-name=\"jdg-server\" mechanisms=\"DIGEST-MD5\" qop=\"auth\">\
                      <policy>\
                          <no-anonymous value=\"true\"/>\
                      </policy>\
                      <property name=\"com.sun.security.sasl.digest.utf8\">true</property>\
                  </sasl>\
              </authentication>"
          fi
          if [ -n "$HOTROD_ENCRYPTION" ]; then
            if [ -n "$ENCRYPTION_REQUIRE_SSL_CLIENT_AUTH" ]; then
              ENCRYPTION_REQUIRE_SSL_CLIENT_AUTH="require-ssl-client-auth=\"$ENCRYPTION_REQUIRE_SSL_CLIENT_AUTH\""
            fi

            encryption="\
              <encryption security-realm=\"ApplicationRealm\" $ENCRYPTION_REQUIRE_SSL_CLIENT_AUTH/>"
          fi

          hotrod="\
            <hotrod-connector cache-container=\"clustered\" socket-binding=\"hotrod-internal\" name=\"hotrod-internal\">$authentication $encryption\
            </hotrod-connector>"
          if [ -n "$topology" ]; then
            hotrod+="\
            <hotrod-connector cache-container=\"clustered\" socket-binding=\"hotrod-external\" name=\"hotrod-external\">$topology $authentication $encryption\
            </hotrod-connector>"
          fi
        ;;
        "memcached")
          if [ -n "$MEMCACHED_CACHE" ]; then
            memcached="\
            <memcached-connector cache-container=\"clustered\" cache=\"${MEMCACHED_CACHE}\" socket-binding=\"memcached\"/>"
          else
            echo "WARNING! The cache for memcached-connector is not set so the connector will not be configured."
          fi
        ;;
        "rest")
            if [ -n "$REST_SECURITY_DOMAIN" ]; then
              REST_SECURITY_DOMAIN="security-domain=\"$REST_SECURITY_DOMAIN\""
            fi
          rest="\
            <rest-connector cache-container=\"clustered\" $REST_SECURITY_DOMAIN/>"
        ;;
      esac
    done
  fi

  subsystem="\
        <subsystem xmlns=\"urn:infinispan:server:endpoint:6.1\">$hotrod $memcached $rest\
        </subsystem>"

  sed -i "s|<!-- ##INFINISPAN_ENDPOINT## -->|$subsystem|" "$CONFIG_FILE"
}
