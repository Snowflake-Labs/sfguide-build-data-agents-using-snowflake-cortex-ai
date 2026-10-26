-- Build Agentic Application in Snowflake: setup
-- Creates a role, warehouse, database and schema, connects the GitHub repository, copies the sample
-- PDFs and images to a stage, creates the SEND_EMAIL stored procedure used later as a custom tool,
-- and grants the role access to Snowflake CoWork and to a compute pool for Workspace notebooks.

use role accountadmin;

-- OPTIONAL: enable cross-region inference if the Claude models used in this guide aren't available in your region
-- alter account set cortex_enabled_cross_region = 'ANY_REGION';

create role if not exists dash_agents_role;
grant create database on account to role dash_agents_role;
grant database role snowflake.cortex_user to role dash_agents_role;

set current_user = (select current_user());
grant role dash_agents_role to user identifier($current_user);

create warehouse if not exists dash_wh_agents with warehouse_size = 'small' auto_suspend = 60;
grant usage on warehouse dash_wh_agents to role dash_agents_role;

-- Compute pool for running the notebook in Workspaces (Container Runtime)
create compute pool if not exists dash_agents_compute_pool
  min_nodes = 1
  max_nodes = 1
  instance_family = cpu_x64_xs
  auto_suspend_secs = 600;
grant usage, monitor on compute pool dash_agents_compute_pool to role dash_agents_role;

-- Access to the public GitHub repository (used for the Git repository object and the Git-synced workspace)
create or replace api integration dash_agents_git_api_integration
  api_provider = git_https_api
  api_allowed_prefixes = ('https://github.com/Snowflake-Labs/')
  enabled = true;
grant usage on integration dash_agents_git_api_integration to role dash_agents_role;

create or replace notification integration dash_agents_email_integration
  type = email
  enabled = true
  default_subject = 'Snowflake CoWork';
grant usage on integration dash_agents_email_integration to role dash_agents_role;

-- Snowflake CoWork object (one per account; skipped if it already exists)
create snowflake intelligence if not exists snowflake_intelligence_object_default;
grant usage on snowflake intelligence snowflake_intelligence_object_default to role dash_agents_role;

use role dash_agents_role;
use warehouse dash_wh_agents;

create database if not exists dash_cortex_agents;
create schema if not exists dash_cortex_agents.data;

use schema dash_cortex_agents.data;

create or replace git repository git_repo
  api_integration = dash_agents_git_api_integration
  origin = 'https://github.com/Snowflake-Labs/sfguide-build-data-agents-using-snowflake-cortex-ai';

alter git repository git_repo fetch;

-- Stage with the sample PDFs and images that the Cortex Search tool indexes
create or replace stage docs encryption = (type = 'snowflake_sse') directory = (enable = true);

copy files
  into @docs/
  from @git_repo/branches/main/docs/;

alter stage docs refresh;

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
        # Use bind parameters so agent-supplied values can't alter the SQL
        session.sql(
            "CALL SYSTEM$SEND_EMAIL('dash_agents_email_integration', ?, ?, ?, 'text/html')",
            params=[recipient_email, subject, body]
        ).collect()

        return "Email sent successfully"
    except Exception as e:
        return f"Error sending email: {str(e)}"
$$;

select 'Congratulations! The setup has completed successfully!' as status;
