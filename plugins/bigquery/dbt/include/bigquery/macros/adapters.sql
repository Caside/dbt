
{% macro partition_by(partition_config) -%}
    {%- if partition_config is none -%}
      {% do return('') %}
    {%- elif partition_config.data_type | lower in ('date','timestamp','datetime') -%}
        partition by {{ partition_config.render() }}
    {%- elif partition_config.data_type | lower in ('int64') -%}
        {%- set range = partition_config.range -%}
        partition by range_bucket(
            {{ partition_config.field }},
            generate_array({{ range.start}}, {{ range.end }}, {{ range.interval }})
        )
    {%- endif -%}
{%- endmacro -%}

{% macro cluster_by(raw_cluster_by) %}
  {%- if raw_cluster_by is not none -%}
  cluster by {% if raw_cluster_by is string -%}
    {% set raw_cluster_by = [raw_cluster_by] %}
  {%- endif -%}
  {%- for cluster in raw_cluster_by -%}
    {{ cluster }}
    {%- if not loop.last -%}, {% endif -%}
  {%- endfor -%}

  {% endif %}

{%- endmacro -%}


{% macro bigquery_table_options(config, node, temporary) %}
  {% set opts = adapter.get_table_options(config, node, temporary) %}

  {% set options -%}
    OPTIONS({% for opt_key, opt_val in opts.items() %}
      {{ opt_key }}={{ opt_val }}{{ "," if not loop.last }}
    {% endfor %})
  {%- endset %}
  {%- do return(options) -%}
{%- endmacro -%}

{% macro bigquery__create_table_as(temporary, relation, sql) -%}
  {%- set raw_partition_by = config.get('partition_by', none) -%}
  {%- set raw_cluster_by = config.get('cluster_by', none) -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {%- set partition_config = adapter.parse_partition_by(raw_partition_by) -%}

  {{ sql_header if sql_header is not none }}

  create or replace table {{ relation }}
  {{ partition_by(partition_config) }}
  {{ cluster_by(raw_cluster_by) }}
  {{ bigquery_table_options(config, model, temporary) }}
  as (
    {{ sql }}
  );

{%- endmacro -%}

{% macro bigquery__create_view_as(relation, sql) -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {{ sql_header if sql_header is not none }}

  create or replace view {{ relation }}
  {{ bigquery_table_options(config, model, temporary=false) }}
  as {{ sql }};

{% endmacro %}

{% macro bigquery__create_schema(relation) -%}
  {{ adapter.create_schema(relation) }}
{% endmacro %}

{% macro bigquery__drop_schema(relation) -%}
  {{ adapter.drop_schema(relation) }}
{% endmacro %}

{% macro bigquery__drop_relation(relation) -%}
  {% call statement('drop_relation') -%}
    drop {{ relation.type }} if exists {{ relation }}
  {%- endcall %}
{% endmacro %}

{% macro bigquery__get_columns_in_relation(relation) -%}
  {{ return(adapter.get_columns_in_relation(relation)) }}
{% endmacro %}


{% macro bigquery__list_relations_without_caching(schema_relation) -%}
  {{ return(adapter.list_relations_without_caching(schema_relation)) }}
{%- endmacro %}


{% macro bigquery__current_timestamp() -%}
  CURRENT_TIMESTAMP()
{%- endmacro %}


{% macro bigquery__snapshot_string_as_time(timestamp) -%}
    {%- set result = 'TIMESTAMP("' ~ timestamp ~ '")' -%}
    {{ return(result) }}
{%- endmacro %}


{% macro bigquery__list_schemas(database) -%}
  {{ return(adapter.list_schemas(database)) }}
{% endmacro %}


{% macro bigquery__check_schema_exists(information_schema, schema) %}
  {{ return(adapter.check_schema_exists(information_schema.database, schema)) }}
{% endmacro %}

{#-- relation-level macro is not implemented. This is handled in the CTAs statement #}
{% macro bigquery__persist_docs(relation, model, for_relation, for_columns) -%}
  {% if for_columns and config.persist_column_docs() and model.columns %}
    {% do alter_column_comment(relation, model.columns) %}
  {% endif %}
{% endmacro %}

{% macro bigquery__alter_column_comment(relation, column_dict) -%}
  {% do adapter.update_columns(relation, column_dict) %}
{% endmacro %}

{% macro bigquery__rename_relation(from_relation, to_relation) -%}
  {% do adapter.rename_relation(from_relation, to_relation) %}
{% endmacro %}

{% macro bigquery__alter_relation_add_columns(relation, add_columns) %}
  
  {% set sql -%}
     
     alter {{ relation.type }} {{ relation }}
        {% for column in add_columns %}
          add column {{ column.name }} {{ column.data_type }}{{ ',' if not loop.last }}
        {% endfor %}
  
  {%- endset -%}

  {{ return(run_query(sql)) }}

{% endmacro %}

{% macro bigquery__alter_relation_drop_columns(relation, drop_columns) %}
  
  {% set sql -%}
     
     alter {{ relation.type }} {{ relation }}

        {% for column in drop_columns %}
          drop column {{ column.name }}{{ ',' if not loop.last }}
        {% endfor %}
  
  {%- endset -%}
  
  {{ return(run_query(sql)) }}

{% endmacro %}


{% macro bigquery__alter_column_type(relation, column_name, new_column_type) -%}
  {#
    Changing a column's data type using a query requires you to scan the entire table.
    The query charges can be significant if the table is very large.

    https://cloud.google.com/bigquery/docs/manually-changing-schemas#changing_a_columns_data_type
  #}
  {% set relation_columns = get_columns_in_relation(relation) %}

  {% set sql %}
    select
      {%- for col in relation_columns -%}
        {% if col.column == column_name %}
          CAST({{ col.quoted }} AS {{ new_column_type }}) AS {{ col.quoted }}
        {%- else %}
          {{ col.quoted }}
        {%- endif %}
        {%- if not loop.last %},{% endif -%}
      {%- endfor %}
    from {{ relation }}
  {% endset %}

  {% call statement('alter_column_type') %}
    {{ create_table_as(False, relation, sql)}}
  {%- endcall %}

{% endmacro %}
