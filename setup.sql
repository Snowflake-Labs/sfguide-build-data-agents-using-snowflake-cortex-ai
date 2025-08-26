use role accountadmin;

create role if not exists snowflake_intelligence_admin;
grant create integration on account to role snowflake_intelligence_admin;
grant create database on account to role snowflake_intelligence_admin;
grant usage on warehouse compute_wh to role snowflake_intelligence_admin;

set current_user = (SELECT CURRENT_USER());   
grant role snowflake_intelligence_admin to user IDENTIFIER($current_user);
alter user set default_role = snowflake_intelligence_admin;

use role snowflake_intelligence_admin;

create database if not exists snowflake_intelligence;
create schema if not exists snowflake_intelligence.agents;

grant create agent on schema snowflake_intelligence.agents to role snowflake_intelligence_admin;

create database if not exists dash_cortex_agents;
create schema if not exists dash_cortex_agents.data;

use database dash_cortex_agents;
use schema data;

create or replace api integration git_api_integration
  api_provider = git_https_api
  api_allowed_prefixes = ('https://github.com/snowflake-labs/')
  enabled = true;

create or replace git repository git_repo
    api_integration = git_api_integration
    origin = 'https://github.com/snowflake-labs/sfguide-build-data-agents-using-snowflake-cortex-ai';

alter git repository git_repo fetch;

create or replace stage docs encryption = (type = 'snowflake_sse') directory = ( enable = true );

copy files
    into @docs/
    from @dash_cortex_agents.data.git_repo/branches/main/docs/;

alter stage docs refresh;

create or replace notification integration email_integration
  type=email
  enabled=true
  default_subject = 'Snowflake Intelligence';

create or replace procedure send_email(
    recipient_email varchar,
    subject varchar,
    body varchar
)
returns varchar
language python
runtime_version = '3.12'
packages = ('snowflake-snowpark-python')
handler = 'send_email'
as
$$
def send_email(session, recipient_email, subject, body):
    try:
        # Escape single quotes in the body
        escaped_body = body.replace("'", "''")
        
        # Execute the system procedure call
        session.sql(f"""
            CALL SYSTEM$SEND_EMAIL(
                'email_integration',
                '{recipient_email}',
                '{subject}',
                '{escaped_body}',
                'text/html'
            )
        """).collect()
        
        return "Email sent successfully"
    except Exception as e:
        return f"Error sending email: {str(e)}"
$$;

ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';

select 'Congratulations! The setup has completed successfully!' as status;
