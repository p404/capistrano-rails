server 'app_server:22', :app, :db, primary: true
#server 'db_server:22', :db

#Application settings
set :rails_env, "production"
set :branch, "master"
set :deploy_to, "/home/deploy/#{rails_env}.#{app_stage}"

#Database settings
set :database_adapter, "postgresql"
set :database_pool, "25"