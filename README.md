# About

Capistrano configuration for Rails application using Phusion passenger and RVM at user level.

# Requirements

Ubuntu Server 12.04 LTS, 14.04 LTS, configured with: [Server Configuration](https://gist.github.com/p404/f0d37cb4b4912543f5a5)

# Setting up your project

```bash
 git checkout --orphan capistrano
 rm -rf *
```
And git clone the capistrano-rails project and move the files inside your own project.

```bash
 git clone --no-checkout git@github.com:p404/capistrano-rails.git 
 git commit -m 'Initial capistrano setup'
```

# Configure your stages

```ruby
set :stages, %w(production staging)
set :default_stage, "staging"
require 'capistrano/ext/multistage'
```

# Set your application name and domain

```ruby
set :application, "my_app"
set :app_stage, "myapplication.com"
```

# Set your user and group for shell commands

```ruby
set :user, "deploy"
set :group, "deploy"
```

# Set Ruby version and gemset
```ruby
set :rvm_ruby_version, 'ruby-version@gemset'
```

# Set your Git repo

```ruby
set :scm, :git 
set :repository,  "git@gitserver.com:repo.git"
set :ssh_options, { forward_agent: true}
```

# Configure your stages params
```ruby
server 'app_server:22', :app, :db, primary: true
```

If our servers are configured separately:

```ruby
server 'app_server:22', :app, primary: true
server 'db_server:22', :db
```

# Application settings

```ruby
set :rails_env, "production"
set :branch, "master"
set :deploy_to, "/home/deploy/#{rails_env}.#{app_stage}"
```

# Ready to go?

### Don't forget to execute bundle install inside the capistrano branch.

Now, we need to deploy our application for the first time:

```bash
bundle exec cap <stage> deploy:cold
```

For each deploy, after our first one:

```bash
bundle exec cap <stage> deploy
```
