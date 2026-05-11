#!/bin/bash
# MIMIC-Extract pipeline entrypoint
set -e

export USER=${USER:-mimic}
export MIMIC_CODE_DIR=${MIMIC_CODE_DIR:-/opt/mimic-code}
export MIMIC_EXTRACT_CODE_DIR=${MIMIC_EXTRACT_CODE_DIR:-/opt/mimic-extract}
export MIMIC_EXTRACT_OUTPUT_DIR=${MIMIC_EXTRACT_OUTPUT_DIR:-/opt/mimic-extract/data/curated}
export MIMIC_DATA_DIR=${MIMIC_DATA_DIR:-/mimic_data}
export PGHOST=${PGHOST:-postgres}
export PGPORT=${PGPORT:-5432}
export PGDATABASE=${PGDATABASE:-mimic}
export PGUSER=${PGUSER:-mimic}
export PGPASSWORD=${PGPASSWORD:-mimic}
export POP_SIZE=${POP_SIZE:-0}
export NUMERICS_BATCH_SIZE=${NUMERICS_BATCH_SIZE:-0}
export EXTRACT_POP=${EXTRACT_POP:-2}
export EXTRACT_NUMERICS=${EXTRACT_NUMERICS:-2}
export EXTRACT_OUTCOMES=${EXTRACT_OUTCOMES:-2}
export MIN_AGE=${MIN_AGE:-15}
export MAX_AGE=${MAX_AGE:-999}
export MIN_DURATION=${MIN_DURATION:-12}
export MAX_DURATION=${MAX_DURATION:-240}
export MIN_PERCENT=${MIN_PERCENT:-0}
export EXTRACT_ALL_NUMERICS=${EXTRACT_ALL_NUMERICS:-0}

# PostgreSQL connection string for psql
export CONNSTR="-h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE"
export PGPASSWORD

# suppress verbose PostgreSQL NOTICEs 
export PGOPTIONS="-c client_min_messages=warning"

echo "=== MIMIC-Extract Docker Pipeline ==="
echo "PGHOST=$PGHOST PGDATABASE=$PGDATABASE POP_SIZE=$POP_SIZE NUMERICS_BATCH_SIZE=$NUMERICS_BATCH_SIZE EXTRACT_ALL_NUMERICS=$EXTRACT_ALL_NUMERICS"
echo "EXTRACT_POP=$EXTRACT_POP EXTRACT_NUMERICS=$EXTRACT_NUMERICS EXTRACT_OUTCOMES=$EXTRACT_OUTCOMES"
echo "MIN_AGE=$MIN_AGE MAX_AGE=$MAX_AGE MIN_DURATION=$MIN_DURATION MAX_DURATION=$MAX_DURATION MIN_PERCENT=$MIN_PERCENT"
echo ""

# Check if using DuckDB mode
if [ -n "${DB_PATH:-}" ] && [ -f "${DB_PATH}" ]; then
  echo "Using DuckDB mode: $DB_PATH"
  echo "Skipping PostgreSQL wait and data load steps."
  echo ""
else
  # wait for PostgreSQL to be ready
  echo "Waiting for PostgreSQL..."
  until PGPASSWORD=$PGPASSWORD psql $CONNSTR -c '\q' 2>/dev/null; do
    echo "  PostgreSQL is unavailable - sleeping"
    sleep 2
  done
  echo "PostgreSQL is ready."
  echo ""
fi

# Check if using DuckDB mode
if [ -n "${DB_PATH:-}" ] && [ -f "${DB_PATH}" ]; then
  echo "Skipping data load and concept building (DuckDB mode)"
else
  # create schema and load MIMIC-III data 
  if [ -d "$MIMIC_DATA_DIR" ] && [ "$(ls -A $MIMIC_DATA_DIR/*.csv.gz 2>/dev/null || ls -A $MIMIC_DATA_DIR/*.csv 2>/dev/null)" ]; then
    echo "loading MIMIC-III data into PostgreSQL"
  
  if ! PGPASSWORD=$PGPASSWORD psql $CONNSTR -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='mimiciii'" | grep -q 1; then
    echo "Creating schema and tables..."

    POSTGRES_DIR=$MIMIC_CODE_DIR/buildmimic/postgres
    [ ! -d "$POSTGRES_DIR" ] && POSTGRES_DIR=$MIMIC_CODE_DIR/mimic-iii/buildmimic/postgres
    PGPASSWORD=$PGPASSWORD psql $CONNSTR -f $POSTGRES_DIR/postgres_create_tables_pg10.sql 2>/dev/null || \
    PGPASSWORD=$PGPASSWORD psql $CONNSTR -f $POSTGRES_DIR/postgres_create_tables.sql
    

    cd $MIMIC_DATA_DIR
    if ls *.csv.gz 1> /dev/null 2>&1; then
      echo "Loading from .csv.gz files..."
      PGPASSWORD=$PGPASSWORD psql $CONNSTR -v mimic_data_dir=$MIMIC_DATA_DIR -f $POSTGRES_DIR/postgres_load_data_gz.sql
    else
      echo "Loading from .csv files..."
      PGPASSWORD=$PGPASSWORD psql $CONNSTR -v mimic_data_dir=$MIMIC_DATA_DIR -f $POSTGRES_DIR/postgres_load_data.sql
    fi
    cd -
    

    echo "Adding constraints and indexes..."
    PGPASSWORD=$PGPASSWORD psql $CONNSTR -f $POSTGRES_DIR/postgres_add_constraints.sql
    PGPASSWORD=$PGPASSWORD psql $CONNSTR -f $POSTGRES_DIR/postgres_add_indexes.sql
    echo "MIMIC-III data loaded."
  else
    echo "MIMIC-III schema already exists - skipping data load."
  fi
  echo ""
else
  echo "=== Step 1: Skipping data load (no MIMIC-III files in $MIMIC_DATA_DIR) ==="
  echo "Mount MIMIC-III CSV files to /mimic_data to load from scratch."
  echo ""
fi

# build mimic-code concepts 
if [ -n "${DB_PATH:-}" ] && [ -f "${DB_PATH}" ]; then
  echo "Skipping concept building (DuckDB mode - concepts already in database)"
else
  echo "building mimic-code concepts" 
  PGPASSWORD=$PGPASSWORD psql $CONNSTR -c "CREATE SCHEMA IF NOT EXISTS mimiciii" -q
  PGPASSWORD=$PGPASSWORD psql $CONNSTR -v ON_ERROR_STOP=1 -f $MIMIC_CODE_DIR/concepts/postgres-functions.sql
  cd $MIMIC_CODE_DIR/concepts && PGPASSWORD=$PGPASSWORD bash postgres_make_concepts.sh
  echo "mimic-code concepts built"
  
  # build MIMIC-Extract extended concepts 
  echo "building MIMIC-Extract extended concepts"
  REGEX_DATETIME_DIFF="s/DATETIME_DIFF\((.+?),\s?(.+?),\s?(DAY|MINUTE|SECOND|HOUR|YEAR)\)/DATETIME_DIFF(\1, \2, '\3')/g"
  REGEX_SCHEMA='s/`physionet-data.(mimiciii_clinical|mimiciii_derived|mimiciii_notes).(.+?)`/\2/g'
  echo "  Creating colloid_bolus..."
  { echo "SET search_path TO public,mimiciii; DROP TABLE IF EXISTS colloid_bolus; CREATE TABLE colloid_bolus AS "; cat $MIMIC_CODE_DIR/concepts/fluid_balance/colloid_bolus.sql; } | sed -r -e "${REGEX_DATETIME_DIFF}" | sed -r -e "${REGEX_SCHEMA}" | PGPASSWORD=$PGPASSWORD psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE
  echo "  Creating crystalloid_bolus..."
  { echo "SET search_path TO public,mimiciii; DROP TABLE IF EXISTS crystalloid_bolus; CREATE TABLE crystalloid_bolus AS "; cat $MIMIC_CODE_DIR/concepts/fluid_balance/crystalloid_bolus.sql; } | sed -r -e "${REGEX_DATETIME_DIFF}" | sed -r -e "${REGEX_SCHEMA}" | PGPASSWORD=$PGPASSWORD psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE
  echo "  Creating nivdurations..."
  PGPASSWORD=$PGPASSWORD psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -f $MIMIC_EXTRACT_CODE_DIR/utils/niv-durations.sql
  echo ""
fi
fi

# run extraction 
echo "running MIMIC-Extract"
mkdir -p $MIMIC_EXTRACT_OUTPUT_DIR
cd $MIMIC_EXTRACT_CODE_DIR

# Build command with DuckDB path if set
CMD_ARGS="--out_path $MIMIC_EXTRACT_OUTPUT_DIR/ \
  --resource_path $MIMIC_EXTRACT_CODE_DIR/resources/ \
  --extract_pop $EXTRACT_POP \
  --extract_outcomes $EXTRACT_OUTCOMES \
  --extract_codes 0 \
  --extract_numerics $EXTRACT_NUMERICS \
  --extract_notes 0 \
  --exit_after_loading 0 \
  --plot_hist 0 \
  --pop_size $POP_SIZE \
  --numerics_batch_size $NUMERICS_BATCH_SIZE \
  --min_age $MIN_AGE \
  --max_age $MAX_AGE \
  --min_duration $MIN_DURATION \
  --max_duration $MAX_DURATION \
  --min_percent $MIN_PERCENT"

if [ "$EXTRACT_ALL_NUMERICS" = "1" ]; then
  CMD_ARGS="$CMD_ARGS --extract_all_numerics"
fi

# Add database connection arguments
if [ -n "${DB_PATH:-}" ] && [ -f "${DB_PATH}" ]; then
  echo "Using DuckDB: $DB_PATH"
  CMD_ARGS="$CMD_ARGS --db_path $DB_PATH"
else
  echo "Using PostgreSQL: $PGHOST:$PGPORT/$PGDATABASE"
  CMD_ARGS="$CMD_ARGS --psql_password $PGPASSWORD --psql_host $PGHOST"
fi

/opt/conda/envs/mimic_data_extraction/bin/python -u mimic_direct_extract.py $CMD_ARGS

echo ""
echo "pipeline complete. Output in $MIMIC_EXTRACT_OUTPUT_DIR"
