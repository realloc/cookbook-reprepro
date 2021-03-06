#
# Cookbook Name:: reprepro
# Recipe:: default
#
# Author:: Joshua Timberman <joshua@opscode.com>
# Copyright 2010, Opscode
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "build-essential"
include_recipe "apache2"

apt_repo = data_bag_item("reprepro", "main")

node.set_unless.reprepro.fqdn = apt_repo['fqdn']
node.set_unless.reprepro.description = apt_repo['description']
node.set_unless.reprepro.pgp_email = apt_repo['pgp']['email']
node.set_unless.reprepro.pgp_fingerprint = apt_repo['pgp']['fingerprint']

apt_repo_owner = apt_repo['owner'] || "nobody"
apt_repo_group = apt_repo['group'] || "nogroup"
apt_repo_mode = apt_repo['mode'] || "0755"
apt_repo_allow = apt_repo["allow"] || []

ruby_block "save node data" do
  block do
    node.save
  end
  action :create
end unless Chef::Config[:solo]

%w{apt-utils dpkg-dev reprepro debian-keyring devscripts dput}.each do |pkg|
  package pkg
end

[ apt_repo["repo_dir"], apt_repo["incoming"] ].each do |dir|
  directory dir do
    owner apt_repo_owner
    group apt_repo_group
    mode  apt_repo_mode
  end
end

%w{ conf db dists pool tarballs }.each do |dir|
  directory "#{apt_repo["repo_dir"]}/#{dir}" do
    owner apt_repo_owner
    group apt_repo_group
    mode  apt_repo_mode
  end
end

%w{ distributions incoming pulls }.each do |conf|
  template "#{apt_repo["repo_dir"]}/conf/#{conf}" do
    source "#{conf}.erb"
    owner apt_repo_owner
    group apt_repo_group
    mode  apt_repo_mode
    variables(
      :allow => apt_repo_allow,
      :codenames => apt_repo["codenames"],
      :architectures => apt_repo["architectures"],
      :incoming => apt_repo["incoming"],
      :pulls => apt_repo["pulls"]
    )
  end
end

apt_repo["pgp"]["users"].each do |pgpuser|
  execute "import packaging key for #{pgpuser}" do
    command "/bin/echo -e '#{apt_repo["pgp"]["private"]}' | sudo -u #{pgpuser} gpg --import -"
    not_if "gpg --list-secret-keys --fingerprint #{node['reprepro']['pgp_email']} | egrep -qx '.*Key fingerprint = #{node['reprepro']['pgp_fingerprint']}'"
  end
end

template "#{apt_repo["repo_dir"]}/#{node['reprepro']['pgp_email']}.gpg.key" do
  source "pgp_key.erb"
  mode "0644"
  owner "nobody"
  group "nogroup"
  variables(
    :pgp_public => apt_repo["pgp"]["public"]
  )
end

template "#{node['apache']['dir']}/sites-available/apt_repo.conf" do
  source "apt_repo.conf.erb"
  mode 0644
  owner "root"
  group "root"
  variables(
    :repo_dir => apt_repo["repo_dir"]
  )
end

execute "reprepro export" do
  command "sudo -u #{apt_repo_owner} reprepro export"
  user "root"
  cwd apt_repo["repo_dir"]
  not_if "sudo -u #{apt_repo_owner} reprepro check"
end

apache_site "apt_repo.conf"

apache_site "000-default" do
  enable false
end
