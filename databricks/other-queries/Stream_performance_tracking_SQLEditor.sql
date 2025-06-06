SELECT from_utc_timestamp(timestamp, 'Australia/Sydney') timestamp_au, message,event_type, details, *  
FROM event_log(TABLE(databricks_trial.poc_bronze.bronze_kinesis_data)) where message like '%bronze%' and message like 'Completed%' order by timestamp desc ;


/*BRONZE LAYER INGESTION */

WITH bronze_query as (
SELECT 
from_utc_timestamp(timestamp, 'Australia/Sydney') timestamp_au, 
message,event_type, 
details, 
*   
FROM event_log(TABLE(databricks_trial.poc_bronze.bronze_kinesis_data)) 
where 
message like '%bronze%' and message like 'Completed%' and from_utc_timestamp(timestamp, 'Australia/Sydney') >= '2024-11-21T08:55:10.208'
order by timestamp desc
), lag_query as (
 SELECT
    timestamp_au,
    LAG(timestamp_au) OVER (ORDER BY timestamp_au) AS previous_timestamp,
    DATEDIFF(SECOND, LAG(timestamp_au) OVER (ORDER BY timestamp_au), timestamp_au) AS time_diff_seconds
  FROM bronze_query
  )SELECT 
  AVG(time_diff_seconds) AS average_time_between_records_in_seconds
FROM lag_query
WHERE time_diff_seconds IS NOT NULL; -- Exclude the first row, as it will have no previous timestamp
;


/*SILVER LAYER INGESTION */
select 'max' as measure, max(ingestion_seconds_to_silver) max from poc_bronze.gold_consumer_transaction_test 
where CREATED_BY = 'DAN_50_PER_SECOND_OPTIMIZE_8'
UNION ALL
select 'min' as measure, min(ingestion_seconds_to_silver) min from poc_bronze.gold_consumer_transaction_test 
where CREATED_BY = 'DAN_50_PER_SECOND_OPTIMIZE_8'
UNION ALL
select 'avg' as measure, avg(ingestion_seconds_to_silver) avg from poc_bronze.gold_consumer_transaction_test 
where CREATED_BY = 'DAN_50_PER_SECOND_OPTIMIZE_8'

;

/*GOLD LAYER PERFORMANCE */

WITH flow_events AS (
    SELECT 
        get_json_object(details, '$.flow_progress.status') AS status,
        origin.flow_id AS flow_id,
        from_utc_timestamp(timestamp, 'Australia/Sydney') AS timestamp_aet,
        id,
        sequence,
        origin,
        message,
        level,
        error,
        get_json_object(details, '$.flow_progress.metrics.num_output_rows') AS num_output_rows,
        details

    FROM 
        event_log(TABLE(databricks_trial.poc_bronze.gold_consumer_transaction_test))
    WHERE 
        message LIKE '%gold_consumer_transaction_test%' 
        AND event_type = 'flow_progress'
        AND get_json_object(details, '$.flow_progress.status') IN ('STARTING', 'COMPLETED')
        and from_utc_timestamp(timestamp, 'Australia/Sydney') >= '2024-11-21T10:45:10.208' and from_utc_timestamp(timestamp, 'Australia/Sydney') <= '2024-11-21T10:53:10.208'
), flow_with_lag as (
  SELECT 
        flow_id,
        status,
        timestamp_aet,
        sequence,
        num_output_rows,
        LAG(status) OVER (PARTITION BY flow_id ORDER BY timestamp_aet) AS previous_status,
        LAG(timestamp_aet) OVER (PARTITION BY flow_id ORDER BY timestamp_aet) AS previous_timestamp_aet,
        LAG(num_output_rows) OVER (PARTITION BY flow_id ORDER BY timestamp_aet) AS previous_num_output_rows
    FROM 
        flow_events
),
durations AS (
    SELECT 
        flow_id,
        previous_timestamp_aet AS start_time,
        timestamp_aet AS end_time,
        num_output_rows,
        UNIX_TIMESTAMP(timestamp_aet) - UNIX_TIMESTAMP(previous_timestamp_aet) AS duration_in_seconds
    FROM 
        flow_with_lag
    WHERE 
        previous_status = 'STARTING' AND status = 'COMPLETED'
), min_query as (
    select min(duration_in_seconds) min from durations
), max_query as (
    select max(duration_in_seconds) max from durations
), avg_query as (
    select avg(duration_in_seconds) avg from durations
)
select 'min' as measure, min from min_query
union all
select 'max' as measure, max from max_query
union all
select 'avg' as measure, avg from avg_query ;


/* COUNT */

select 'consumer', count(*) from poc_bronze.gold_consumer_test
where CREATED_BY = 'DAN_50_PER_SECOND_OPTIMIZE_8'  --26308   ---3168  ... it changed to 3,724
union all
select 'transaction',count(*) from poc_bronze.gold_transaction_test
where CREATED_BY = 'DAN_50_PER_SECOND_OPTIMIZE_8'
union all
select 'consumer_transaction', count(*) from poc_bronze.gold_consumer_transaction_test
where CREATED_BY = 'DAN_50_PER_SECOND_OPTIMIZE_8'

;
SELECT * 
 FROM 
        event_log(TABLE(databricks_trial.poc_bronze.gold_consumer_transaction_test))

;
/*CONSUMER COUNT */  --30500
select COUNT(*) from poc_bronze.bronze_kinesis_data 
where get_json_object(data_str, '$.data.CREATED_BY') IN ('MODERATE_FIFTY_ROWS_PER_SEC')
and get_json_object(data_str, '$.metadata.table-name') IN ('CONSUMER_TEST') ;

/*CONSUMER COUNT WITH DISTINCT */  --26324
select COUNT(distinct get_json_object(data_str, '$.data.ID') ) from poc_bronze.bronze_kinesis_data 
where get_json_object(data_str, '$.data.CREATED_BY') IN ('MODERATE_FIFTY_ROWS_PER_SEC')
and get_json_object(data_str, '$.metadata.table-name') IN ('CONSUMER_TEST') ;

/*SILVER - 1 STAGE  */  --30500
SELECT COUNT(*) FROM (
WITH metadata_parsed AS (
  SELECT
    partitionKey,
    approximateArrivalTimestamp,
    data_str,
    sequenceNumber,
    from_json(data_str, '
      struct<
        metadata: struct<
          `schema-name`: string,
          `table-name`: string,
          `operation`: string
        >
      >
    ') AS metadata_parsed
  FROM poc_bronze.bronze_kinesis_data 
),
filtered_table AS (
  SELECT
    partitionKey,
    approximateArrivalTimestamp,
    sequenceNumber,
    data_str,
    metadata_parsed.metadata.`schema-name` as METADATA_SCHEMA_NAME,
    metadata_parsed.metadata.`table-name` AS METADATA_TABLE_NAME,
    metadata_parsed.metadata.`operation` AS operation
  FROM metadata_parsed
  WHERE
    metadata_parsed.metadata.`schema-name` = 'KINESIS_GENERATOR'
    AND metadata_parsed.metadata.`table-name` = 'CONSUMER_TEST'
),
parsed_table AS (
  SELECT 
    partitionKey,
    approximateArrivalTimestamp,
    sequenceNumber,
    METADATA_SCHEMA_NAME,
    METADATA_TABLE_NAME,
    operation,
    from_json(data_str, '
      struct<
        data: struct<
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string,
          COLUMN_HERE: string
        >
      >
    ') AS parsed_data
  FROM filtered_table
)
SELECT
  partitionKey,
  approximateArrivalTimestamp,
  sequenceNumber,
  METADATA_SCHEMA_NAME,
  METADATA_TABLE_NAME,
  operation,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  TO_TIMESTAMP(parsed_data.data.COLUMN_HERE) AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  TO_TIMESTAMP(parsed_data.data.COLUMN_HERE) AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  parsed_data.data.COLUMN_HERE AS COLUMN_HERE,
  TO_TIMESTAMP(CONVERT_TIMEZONE('UTC', 'Australia/Sydney', CURRENT_TIMESTAMP())) AS silver_layer_timestamp
FROM parsed_table
WHERE parsed_data IS NOT NULL
AND parsed_data.data IS NOT NULL 
AND parsed_data.data.CREATED_BY IN ('MODERATE_FIFTY_ROWS_PER_SEC')
) X;

select count(*) from poc_bronze.silver_consumer_test where CREATED_BY IN ('MODERATE_FIFTY_ROWS_PER_SEC') ;





