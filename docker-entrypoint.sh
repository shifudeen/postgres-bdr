#!/bin/bash
set -e

if [ "${1:0:1}" = '-' ]; then
	set -- postgres "$@"
fi

if [ "$1" = 'postgres' ]; then
	mkdir -p "$PGDATA"
	chmod 700 "$PGDATA"
	chown -R postgres "$PGDATA"

	chmod g+s /run/postgresql
	chown -R postgres /run/postgresql

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
		eval "gosu postgres initdb $POSTGRES_INITDB_ARGS"

		# check password first so we can output the warning before postgres
		# messes it up
		if [ "$POSTGRES_PASSWORD" ]; then
			pass="PASSWORD '$POSTGRES_PASSWORD'"
			authMethod=md5
		else
			# The - option suppresses leading tabs but *not* spaces. :)
			cat >&2 <<-'EOWARN'
				****************************************************
				WARNING: No password has been set for the database.
				         This will allow anyone with access to the
				         Postgres port to access your database. In
				         Docker's default configuration, this is
				         effectively any other container on the same
				         system.

				         Use "-e POSTGRES_PASSWORD=password" to set
				         it in "docker run".
				****************************************************
			EOWARN

			pass=
			authMethod=trust
		fi

		{ echo; echo "host all all 0.0.0.0/0 $authMethod";
			echo "host replication all 0.0.0.0/0 $authMethod";
		} >> "$PGDATA/pg_hba.conf"
		{ echo; echo "shared_preload_libraries = 'bdr'";
			echo "wal_level = 'logical'";
			echo "track_commit_timestamp = on";
			echo "max_wal_senders = 50";
			echo "max_replication_slots = 50";
			echo "max_worker_processes = 50";
			echo "default_sequenceam = 'bdr'";
            echo "log_destination = 'stderr'";
            echo "logging_collector = on";
            echo "log_directory = 'pg_log'";
            echo "log_filename = 'postgresql-%a.log'";
            echo "log_truncate_on_rotation = on";
            echo "log_rotation_age = 1d";
            echo "log_rotation_size = 0";
            echo "log_min_duration_statement = 0";
            echo "log_checkpoints = on";
            echo "log_connections = on";
            echo "log_disconnections = on";
            echo "log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h'";
            echo "log_lock_waits = on";
            echo "log_timezone = 'Asia/Kuala_Lumpur'";
            echo "log_autovacuum_min_duration = 0";
		} >> "$PGDATA"/postgresql.conf

		# internal start of server in order to allow set-up using psql-client		
		# does not listen on external TCP/IP and waits until start finishes
		gosu postgres pg_ctl -D "$PGDATA" \
			-o "-c listen_addresses='localhost'" \
			-w start

		: ${POSTGRES_USER:=postgres}
		: ${POSTGRES_DB:=$POSTGRES_USER}
		export POSTGRES_USER POSTGRES_DB
		psql=( psql -v ON_ERROR_STOP=1 )

		if [ "$POSTGRES_DB" != 'postgres' ]; then
			"${psql[@]}" --username postgres <<-EOSQL
				CREATE DATABASE "$POSTGRES_DB" ;
			EOSQL
			echo
		fi

		if [ "$POSTGRES_USER" = 'postgres' ]; then
			op='ALTER'
		else
			op='CREATE'
		fi

		"${psql[@]}" --username postgres <<-EOSQL
			$op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
		EOSQL
		echo
		psql+=( --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "$0: running $f"; . "$f" ;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" < "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
	fi

    #Performance Tuning using PGTUNE
    if [ ! "$POSTGRES_OPERATION_TYPE" ]; then
        POSTGRES_OPERATION_TYPE="OLTP"
    fi

    if [ "$POSTGRES_MAX_MEMORY" ]; then
        POSTGRES_MAX_MEMORY=$(($POSTGRES_MAX_MEMORY * 1024 * 1024 * 1024))
        gosu postgres pgtune -M $POSTGRES_MAX_MEMORY -T $POSTGRES_OPERATION_TYPE -i /var/lib/postgresql/data/postgresql.conf -o /var/lib/postgresql/data/postgresql.conf
    else
        gosu postgres pgtune -T $POSTGRES_OPERATION_TYPE -i /var/lib/postgresql/data/postgresql.conf -o /var/lib/postgresql/data/postgresql.conf
    fi
    
    if [ ! "$POSTGRES_LOG_COLLECT" ]; then
        POSTGRES_LOG_COLLECT="on"
    fi

    sed -i "s/logging_collector.*/logging_collector = ${POSTGRES_LOG_COLLECT}/g" /var/lib/postgresql/data/postgresql.conf

    exec gosu postgres "$@"
fi

exec "$@"
