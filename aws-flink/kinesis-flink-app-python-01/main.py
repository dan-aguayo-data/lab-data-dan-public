"""
Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""
# -*- coding: utf-8 -*-
"""
main.py
~~~~~~~~~~~~~~~~~~~
This module:
FIXME
    1. Creates a execution environment
    2. Set any special configuration for local mode (e.g. when running in the IDE)
    3. Retrieve the runtime configuration
    4. Create a source table from a Kinesis Data Stream
    5. Create a sink table writing to a Kinesis Data Stream
    6. Insert the source table data into the sink table
"""

from pyflink.table import EnvironmentSettings, TableEnvironment
import os
import json
import pyflink

#######################################
# 1. Creates the execution environment
#######################################

env_settings = EnvironmentSettings.in_streaming_mode()
table_env = TableEnvironment.create(env_settings)

# Location of the configuration file when running on Managed Flink.
# NOTE: this is not the file included in the project, but a file generated by Managed Flink, based on the
# application configuration.
APPLICATION_PROPERTIES_FILE_PATH = "/etc/flink/application_properties.json"

# Set the environment variable IS_LOCAL=true in your local development environment,
# or in the run profile of your IDE: the application relies on this variable to run in local mode (as a standalone
# Python application, as opposed to running in a Flink cluster).
# Differently from Java Flink, PyFlink cannot automatically detect when running in local mode
is_local = (
    True if os.environ.get("IS_LOCAL") else False
)

##############################################
# 2. Set special configuration for local mode
##############################################

if is_local:
    # Load the configuration from the json file included in the project
    APPLICATION_PROPERTIES_FILE_PATH = "application_properties.json"

    # Point to the fat-jar generated by Maven, containing all jar dependencies (e.g. connectors)
    CURRENT_DIR = os.path.dirname(os.path.realpath(__file__))
    table_env.get_config().get_configuration().set_string(
        "pipeline.jars",
        # For local development (only): use the fat-jar containing all dependencies, generated by `mvn package`
        # located in the target/ subdirectory
        "file:///" + CURRENT_DIR + "/target/pyflink-dependencies.jar",
    )

    # Show the PyFlink home directory and the directory where logs will be written, when running locally
    print("PyFlink home: " + os.path.dirname(os.path.abspath(pyflink.__file__)))
    print("Logging directory: " + os.path.dirname(os.path.abspath(pyflink.__file__)) + '/log')

# Utility method, extracting properties from the runtime configuration file
def get_application_properties():
    if os.path.isfile(APPLICATION_PROPERTIES_FILE_PATH):
        with open(APPLICATION_PROPERTIES_FILE_PATH, "r") as file:
            contents = file.read()
            properties = json.loads(contents)
            return properties
    else:
        print('A file at "{}" was not found'.format(APPLICATION_PROPERTIES_FILE_PATH))

# Utility method, extracting a property from a property group
def property_map(props, property_group_id):
    for prop in props:
        if prop["PropertyGroupId"] == property_group_id:
            return prop["PropertyMap"]


AT_TIMESTAMP = "AT_TIMESTAMP"

def main():

    #####################################
    # 3. Retrieve runtime configuration
    #####################################

    props = get_application_properties()

    # Input stream configuration
    input_stream_properties = property_map(props, "InputStream0")
    input_stream_name = input_stream_properties["stream.name"]
    input_stream_region = input_stream_properties["aws.region"]
    input_stream_initpos = input_stream_properties["flink.stream.initpos"] if "flink.stream.initpos" in input_stream_properties else None
    input_stream_initpos_timestamp = input_stream_properties["flink.stream.initpos.timestamp"] if "flink.stream.initpos.timestamp" in input_stream_properties else None
    if input_stream_initpos == AT_TIMESTAMP and input_stream_initpos_timestamp == None:
            raise ValueError(f"A timestamp must be supplied for stream_initpos {AT_TIMESTAMP}")

    # Output stream configuration
    output_stream_properties = property_map(props, "OutputStream0")
    output_stream_name = output_stream_properties["stream.name"]
    output_stream_region = output_stream_properties["aws.region"]

    #################################################
    # 4. Define source table using kinesis connector
    #################################################

    # Some trick is required to generate the string defining the initial position, depending on the configuration
    # See Flink documentation for further details about configuring a Kinesis source table
    # https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/connectors/table/kinesis/
    init_pos = "\n'scan.stream.initpos' = '{0}',".format(input_stream_initpos) if input_stream_initpos is not None else ''
    init_pos_timestamp = "\n'scan.stream.initpos-timestamp' = '{0}',".format(input_stream_initpos_timestamp) if input_stream_initpos_timestamp is not None else ''

    table_env.execute_sql(f"""
        CREATE TABLE kinesisTable (
                `ticker` VARCHAR(6),
                `price` DOUBLE,
                `event_time` TIMESTAMP(3),
                `arrival_time` TIMESTAMP(3) METADATA FROM 'timestamp' VIRTUAL
                `shard_id` VARCHAR(128) NOT NULL METADATA FROM 'shard-id' VIRTUAL
                `sequence_number` VARCHAR(128) NOT NULL METADATA FROM 'sequence-number' VIRTUAL
              )
              PARTITIONED BY (ticker)
              WITH (
                'connector' = 'kinesis-legacy',
                'stream' = '{input_stream_name}',
                'aws.region' = '{input_stream_region}',
                'scan.stream.initpos' = 'LATEST',
                'format' = 'json',
                'json.timestamp-format.standard' = 'ISO-8601'
              ) """)


    #################################################
    # 5. Define sink table using kinesis connector
    #################################################

    table_env.execute_sql(f"""
            CREATE TABLE output (
                ticker VARCHAR(6),
                price DOUBLE,
                event_time TIMESTAMP(3)
              )
              PARTITIONED BY (ticker)
              WITH (
                'connector' = 'kinesis-legacy',
                'stream' = '{output_stream_name}',
                'aws.region' = '{output_stream_region}',
                'sink.partitioner-field-delimiter' = ';',
                'sink.batch.max-size' = '100',
                'format' = 'json',
                'json.timestamp-format.standard' = 'ISO-8601'
              )""")

    # For local development purposes, you might want to print the output to the console, instead of sending it to a
    # Kinesis Stream. To do that, you can replace the sink table using the 'kinesis' connector, above, with a sink table
    # using the 'print' connector. Comment the statement immediately above and uncomment the one immediately below.

    # table_env.execute_sql("""
    #     CREATE TABLE output (
    #             ticker VARCHAR(6),
    #             price DOUBLE,
    #             event_time TIMESTAMP(3)
    #           )
    #           WITH (
    #             'connector' = 'print'
    #           )""")

    # In a real application we would probably have some transformations between the input and the output.
    # For simplicity, we will send the source table directly to the sink table.

    ##########################################################################################
    # 6. Define an INSERT INTO statement writing data from the source table to the sink table
    ##########################################################################################

    # Executing an INSERT INTO statement will trigger the job
    table_result = table_env.execute_sql("""
        INSERT INTO output 
        SELECT ticker, price, event_time 
        FROM kinesisTable""")

    # When running locally, as a standalone Python application, you must instruct Python not to exit at the end of the
    # main() method, otherwise the job will stop immediately.
    # When running the job deployed in a Flink cluster or in Amazon Managed Service for Apache Flink, the main() method
    # must end once the flow has been defined and handed over to the Flink framework to run.
    if is_local:
        table_result.wait()


if __name__ == "__main__":
    main()