-- Override dbt's default schema naming to use the custom schema as-is,
-- instead of prefixing with the profile's default schema.
-- Without this, `+schema: silver` in dbt_project.yml produces `silver_silver`
-- because the profile default schema is also `silver`.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
