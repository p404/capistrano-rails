#Configure your stages
set :stages, %w(production staging)
set :default_stage, "staging"
require 'capistrano/ext/multistage'
require 'rvm/capistrano'

set :rvm_type, :user
set :rvm_ruby_version, 'ruby-version@gemset'
set :bundle_dir, ''
set :bundle_flags, '--quiet'

#Set your application name and domain
set :application, "my_app"
set :app_stage, "myapplication.com"

#Set your user and group for shell commands
set :user, "deploy"
set :group, "deploy"

#Set your Git repo
set :scm, :git 
set :repository,  "git@gitserver.com:repo.git"
set :ssh_options, { forward_agent: true}
default_run_options[:env] = {'rvmsudo_secure_path' => 1}

#Set number of releases you want to keep after cleanup
set :keep_releases, 10

namespace :deploy do
  desc "Create and set permittions for capistrano directory structure."
  task :setup, roles: :app do
    run "mkdir -p #{deploy_to}/{releases,shared/{assets,config,log,pids,system}}"
    run "chmod -R g+w #{deploy_to}"
  end

  desc "Clone project in a cached_copy path and install gems in Gemfile."
  task :first_release, roles: :app do
    run "git clone #{repository} -b #{branch} #{shared_path}/cached_copy && cd #{shared_path}/cached_copy && bundle install --without development test --path #{shared_path}/vendor/bundle --binstubs #{shared_path}/vendor/bundle/bin --deployment"
    copy_cache
  end

  desc "Copy cached version to new release path"
  task :copy_cache, roles: :app do
    forced_deploy = fetch(:forced, false)

    if forced_deploy == true
      run "cd #{shared_path}/cached_copy && git fetch && git checkout #{branch} && git reset --hard origin/#{branch} && cp -RPp #{shared_path}/cached_copy #{deploy_to}/releases/#{release_name}"
    else
      run "cd #{shared_path}/cached_copy && git fetch && git checkout #{branch} && git pull origin #{branch} && cp -RPp #{shared_path}/cached_copy #{deploy_to}/releases/#{release_name}"
    end
  end

  desc "Clone project in a new release path and install gems in Gemfile."
  task :update_release, roles: :app do
    copy_cache
    run "cd #{deploy_to}/releases/#{release_name} && bundle install --without development test --path #{shared_path}/vendor/bundle --binstubs #{shared_path}/vendor/bundle/bin --deployment"
  end

  desc "Updates the symlink to the most recently deployed version."
  task :create_symlink, roles: :app, :except => { :no_release => true } do
    on_rollback do
      if previous_release
        run "rm -f #{current_path}; ln -s #{previous_release} #{current_path}; true"
      else
        logger.important "no previous release to rollback to, rollback of symlink skipped"
      end
    end

    run "rm -f #{current_path} && ln -s #{latest_release} #{current_path}"
  end

  desc "Create database yaml in shared path."
  task :db_configure, roles: :app do
    db_config = <<-EOF
#{rails_env}:
  adapter:  #{database_adapter}
  database: \<\%\= ENV\[\'DB_DBNAME\'\] \%\>
  host:     \<\%\= ENV\[\'DB_HOSTNAME\'\] \%\>
  pool:     #{database_pool}
  username: \<\%\= ENV\[\'DB_USERNAME\'\] \%\>
  password: \<\%\= ENV\[\'DB_PASSWORD\'\] \%\>
EOF

    run "rm -f #{shared_path}/config/database.yml"
    put db_config, "#{shared_path}/config/database.yml"
  end

  desc "Make symlink for database yaml."
  task :db_symlink, roles: :app do
    run "ln -snf #{shared_path}/config/database.yml #{latest_release}/config/database.yml"
  end

  desc "Make symlink for public directories."
  task :dir_symlink, roles: :app do
    run "ln -snf #{shared_path}/assets #{latest_release}/public/assets"
    run "ln -snf #{shared_path}/log #{latest_release}/log"
    run "ln -snf #{shared_path}/system #{latest_release}/public/system"
  end

  desc "Configuring database for project."
  task :db_setup, roles: :app do
    run "cd #{latest_release} && bundle exec rake db:setup RAILS_ENV=#{rails_env}"
  end

  desc "Start Passenger Server."
  task :start, roles: :app do
    run "cd #{current_path} && rvmsudo `tail -n +2 /etc/environment | paste -s -d ' ' | sed -e 's/\"//g'` passenger start --environment #{rails_env} --user #{user} --load-shell-envvars --log-file #{shared_path}/log/passenger.3000.log --pid-file #{shared_path}/log/passenger.3000.pid --daemonize"
  end

  desc "Stop Passenger server."
  task :stop, roles: :app do
    run "cd #{current_path} && rvmsudo passenger stop --pid-file #{shared_path}/log/passenger.3000.pid"
  end

  desc "Restart Passenger server."
  task :restart, roles: :app do
    run "passenger-config restart-app #{latest_release}"
  end

  desc "Reload database with seed data"
  task :seed, roles: :app do
    run "cd #{current_path} && bundle exec rake db:seed RAILS_ENV=#{rails_env}"
  end

  desc "Show log file in real time"
  task :log do
    hostname = find_servers_for_task(current_task).first
    port = exists?(:port) ? fetch(:port) : 22
    exec "ssh -l #{user} #{hostname} -p #{port} -t 'tail -f #{current_path}/log/#{rails_env}.log'"
  end

  desc "Run cleanup task when releases count reach threshold"
  task :auto_cleanup, :except => { :no_release => true } do
    thresh = fetch(:cleanup_threshold, 20).to_i
    if releases.length > thresh
      logger.info "Threshold of #{thresh} releases reached, runing deploy:cleanup."
      cleanup
    end
  end

  desc "First time deploy."
  task :cold do
    first_release
    db_configure
    db_symlink
    dir_symlink
    db_setup
    rake.migrate
    rake.assets
    start
  end

  desc "Deploys you application."
  task :default do
    update_release
    db_symlink
    dir_symlink
    rake.migrate
    rake.assets
    stop
    start
  end
end

namespace :rake do

  desc "Run assets:precompile rake task for the deployed application."
  task :assets, roles: :app do
    run "cd #{latest_release} && bundle exec rake assets:precompile RAILS_ENV=#{rails_env} RAILS_GROUPS=assets #{bundle_flags}"
  end

  desc "Run the migrate rake task."
  task :migrate, roles: :app do
    run "cd #{latest_release} && bundle exec rake RAILS_ENV=#{rails_env} db:migrate #{bundle_flags}"
  end
end

namespace :rails do
  desc "Open the rails console on one of the remote servers."
  task :console, roles: :app do
    hostname = find_servers_for_task(current_task).first
    port = exists?(:port) ? fetch(:port) : 22
    exec "ssh -l #{user} #{hostname} -p #{port} -t '#{current_path}/script/rails c #{rails_env}'"
  end
end

before "deploy:cold", "deploy:setup"
before "deploy:start", "deploy:create_symlink"
before "deploy:restart", "deploy:create_symlink"
after "deploy", "deploy:auto_cleanup"
