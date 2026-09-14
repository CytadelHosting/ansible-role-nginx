# Ansible Role: Nginx

[![CI](https://github.com/geerlingguy/ansible-role-nginx/actions/workflows/ci.yml/badge.svg)](https://github.com/geerlingguy/ansible-role-nginx/actions/workflows/ci.yml)

**Note:** Please consider using the official [NGINX Ansible role](https://github.com/nginxinc/ansible-role-nginx) from NGINX, Inc.

Installs Nginx on RedHat/CentOS, Debian/Ubuntu, Archlinux, FreeBSD or OpenBSD servers.

Cytadel changes apply to **Debian only**. Other OS stay on the upstream geerlingguy behavior.

On Debian this fork installs nginx from **nginx.org** plus **blendbyte** extras (brotli, modsecurity, ...). Vhosts live in `/etc/nginx/sites-available` and are enabled via symlink in `/etc/nginx/sites-enabled`. HTTP tunables go in `/etc/nginx/conf.d/`.

## Cytadel: repos, extras, migration, conf.d

### Repositories

    nginx_official_repo_enabled: true
    nginx_official_repo_channel: stable   # or mainline — blendbyte is stable-only

Debian only: nginx.org apt repo + pin 900. Distro nginx is no longer the default.

Keys go in `/etc/apt/keyrings/` (admin third-party keys). `/usr/share/keyrings/` is left to Debian packages — nginx.org docs put the key there, we don't.

    nginx_apt_deb822: auto   # deb822 (.sources) on Debian >= 12 / Ubuntu >= 24, else .list
    nginx_apt_keyring_dir: /etc/apt/keyrings

The unused format (`.list` vs `.sources`) is removed so apt does not see the same repo twice. Override with `true` / `false`.

`nginx-module-*` is pinned to `apt.blendbyte.net` at priority 1001 (`/etc/apt/preferences.d/blendbyte-nginx`). nginx.org itself stays pinned at 900 for the `nginx` package.

    nginx_blendbyte_repo_enabled: true
    nginx_extra_packages: []
    # - nginx-module-brotli
    # - nginx-module-modsecurity
    # - nginx-module-headers-more

Blendbyte modules auto-drop `load_module` snippets in `/etc/nginx/modules-enabled/`. The role injects `include /etc/nginx/modules-enabled/*.conf;` at the top of `nginx.conf` (stock nginx.org does not).

### Main config

    nginx_manage_main_config: true

`true` keeps the geerlingguy `nginx.conf.j2` template. Set `false` to keep the package `nginx.conf` and move HTTP tunables into `conf.d` snippets.

Debian vhost layout:

- `/etc/nginx/sites-available/<name>` — fichier réel
- `/etc/nginx/sites-enabled/<name>` — symlink
- `/etc/nginx/conf.d/` — snippets HTTP (tuning, modules), pas les vhosts

The catch-all default site is seeded once in `sites-available/default` (`templates/default-site.j2`) and enabled as `sites-enabled/000-default.conf`. Existing `sites-available/default` is never overwritten. `conf.d/default.conf` (paquet nginx.org) is renamed to `conf.d/default.disabled` so `include *.conf` skips it.

    nginx_default_site_enabled: true
    nginx_default_site_filename: default
    nginx_default_site_link: 000-default.conf
    nginx_default_site_listen: "80 default_server"
    nginx_default_site_listen_ipv6: "80 default_server"
    nginx_default_site_index: "index.html index.htm index.php index.nginx-debian.html"
    nginx_default_site_return: "444"   # location / only; empty = try_files

`fastcgi_params` is kept. `fastcgi.conf`, `uwsgi_params` and `scgi_params` are deleted (uwsgi = Python uWSGI, scgi = old alternative to FastCGI).

### Migration (one-shot)

    nginx_migrate: true
    nginx_migrate_force: false
    nginx_manage_main_config: false
    nginx_confd_files:
      - { name: 00-tuning.conf, src: conf.d/00-tuning.conf.j2 }
      - { name: 10-log-formats.conf, src: conf.d/10-log-formats.conf.j2 }
      - { name: brotli.conf, src: conf.d/brotli.conf.j2 }
    nginx_extra_packages:
      - nginx-module-brotli
When `nginx_migrate` is true (and no stamp, unless `force`):

1. Backup current files under `/var/backups/nginx-migrate/<timestamp>/`
2. Inventory existing `conf.d/*.conf` (left untouched)
3. Restore `nginx.conf`, `mime.types`, `fastcgi_params` from the **installed package**
4. Delete `fastcgi.conf`, `uwsgi_params`, `scgi_params`, `snippets`, `proxy_params`
5. Keep `sites-available` / `sites-enabled`
6. Write `/etc/nginx/.cytadel-migrated`

Leave `nginx_migrate: false` afterwards. Re-run with `nginx_migrate_force: true`.

Override lists via `nginx_migrate_reset_files`, `nginx_migrate_remove_paths`, `nginx_migrate_adopt_from`.

### Declared conf.d overlays

Existing undeclared `*.conf` in `conf.d` are never touched. Only names listed here are deployed (or removed):

    nginx_confd_files:
      - name: 00-tuning.conf
        src: conf.d/00-tuning.conf.j2
      - name: custom-security.conf
        src: "{{ playbook_dir }}/templates/nginx/security.conf.j2"
        state: present

Snippets shipped by the role: `templates/conf.d/00-tuning.conf.j2`, `10-log-formats.conf.j2`, `20-upstreams.conf.j2`, `brotli.conf.j2`.

If `nginx_upstreams` is set and `nginx_manage_main_config` is false, `20-upstreams.conf` is deployed automatically.

## Requirements

None.

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):


    nginx_listen_ipv6: true

Whether or not to listen on IPv6 (applied to all vhosts managed by this role).

    nginx_vhosts: []

A list of vhost definitions (server blocks) for Nginx virtual hosts. Each entry will create a separate config file named by `server_name`. If left empty, you will need to supply your own virtual host configuration. See the commented example in `defaults/main.yml` for available server options. If you have a large number of customizations required for your server definition(s), you're likely better off managing the vhost configuration file yourself, leaving this variable set to `[]`.

    nginx_vhosts:
      - listen: "443 ssl http2"
        server_name: "example.com"
        server_name_redirect: "www.example.com"
        root: "/var/www/example.com"
        index: "index.php index.html index.htm"
        error_page: ""
        access_log: ""
        error_log: ""
        state: "present"
        template: "{{ nginx_vhost_template }}"
        filename: "example.com.conf"
        extra_parameters: |
          location ~ \.php$ {
              fastcgi_split_path_info ^(.+\.php)(/.+)$;
              fastcgi_pass unix:/var/run/php5-fpm.sock;
              fastcgi_index index.php;
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              include fastcgi_params;
          }
          ssl_certificate     /etc/ssl/certs/ssl-cert-snakeoil.pem;
          ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
          ssl_protocols       TLSv1.1 TLSv1.2;
          ssl_ciphers         HIGH:!aNULL:!MD5;

An example of a fully-populated nginx_vhosts entry, using a `|` to declare a block of syntax for the `extra_parameters`.

Please take note of the indentation in the above block. The first line should be a normal 2-space indent. All other lines should be indented normally relative to that line. In the generated file, the entire block will be 4-space indented. This style will ensure the config file is indented correctly.

      - listen: "80"
        server_name: "example.com www.example.com"
        return: "301 https://example.com$request_uri"
        filename: "example.com.80.conf"

An example of a secondary vhost which will redirect to the one shown above.

*Note: The `filename` defaults to the first domain in `server_name`, if you have two vhosts with the same domain, eg. a redirect, you need to manually set the `filename` so the second one doesn't override the first one*

    nginx_remove_default_vhost: true

Whether to remove the 'default' virtualhost configuration supplied by Nginx. Useful if you want the base `/` URL to be directed at one of your own virtual hosts configured in a separate .conf file.

    nginx_upstreams: []

If you are configuring Nginx as a load balancer, you can define one or more upstream sets using this variable. In addition to defining at least one upstream, you would need to configure one of your server blocks to proxy requests through the defined upstream (e.g. `proxy_pass http://myapp1;`). See the commented example in `defaults/main.yml` for more information.

    nginx_user: "nginx"

The user under which Nginx will run. Defaults to `nginx` for RedHat, `www-data` for Debian and `www` on FreeBSD and OpenBSD.

    nginx_worker_processes: "{{ ansible_processor_vcpus|default(ansible_processor_count) }}"
    nginx_worker_connections: "1024"
    nginx_multi_accept: "off"

`nginx_worker_processes` should be set to the number of cores present on your machine (if the default is incorrect, find this number with `grep processor /proc/cpuinfo | wc -l`). `nginx_worker_connections` is the number of connections per process. Set this higher to handle more simultaneous connections (and remember that a connection will be used for as long as the keepalive timeout duration for every client!). You can set `nginx_multi_accept` to `on` if you want Nginx to accept all connections immediately.

    nginx_error_log: "/var/log/nginx/error.log warn"
    nginx_access_log: "/var/log/nginx/access.log main buffer=16k flush=2m"

Configuration of the default error and access logs. Set to `off` to disable a log entirely.

    nginx_sendfile: "on"
    nginx_tcp_nopush: "on"
    nginx_tcp_nodelay: "on"

TCP connection options. See [this blog post](https://t37.net/nginx-optimization-understanding-sendfile-tcp_nodelay-and-tcp_nopush.html) for more information on these directives.

    nginx_keepalive_timeout: "65"
    nginx_keepalive_requests: "100"

Nginx keepalive settings. Timeout should be set higher (10s+) if you have more polling-style traffic (AJAX-powered sites especially), or lower (<10s) if you have a site where most users visit a few pages and don't send any further requests.

    nginx_server_tokens: "on"

Nginx server_tokens settings. Controls whether nginx responds with it's version in HTTP headers. Set to `"off"` to disable.

    nginx_client_max_body_size: "64m"

This value determines the largest file upload possible, as uploads are passed through Nginx before hitting a backend like `php-fpm`. If you get an error like `client intended to send too large body`, it means this value is set too low.

    nginx_server_names_hash_bucket_size: "64"

If you have many server names, or have very long server names, you might get an Nginx error on startup requiring this value to be increased.

    nginx_proxy_cache_path: ""

Set as the `proxy_cache_path` directive in the `nginx.conf` file. By default, this will not be configured (if left as an empty string), but if you wish to use Nginx as a reverse proxy, you can set this to a valid value (e.g. `"/var/cache/nginx keys_zone=cache:32m"`) to use Nginx's cache (further proxy configuration can be done in individual server configurations).

    nginx_extra_http_options: ""

Extra lines to be inserted in the top-level `http` block in `nginx.conf`. The value should be defined literally (as you would insert it directly in the `nginx.conf`, adhering to the Nginx configuration syntax - such as `;` for line termination, etc.), for example:

    nginx_extra_http_options: |
      proxy_buffering    off;
      proxy_set_header   X-Real-IP $remote_addr;
      proxy_set_header   X-Scheme $scheme;
      proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header   Host $http_host;

See the template in `templates/nginx.conf.j2` for more details on the placement.

    nginx_extra_conf_options: ""

Extra lines to be inserted in the top of `nginx.conf`. The value should be defined literally (as you would insert it directly in the `nginx.conf`, adhering to the Nginx configuration syntax - such as `;` for line termination, etc.), for example:

    nginx_extra_conf_options: |
      worker_rlimit_nofile 8192;

See the template in `templates/nginx.conf.j2` for more details on the placement.

    nginx_log_format: |-
      '$remote_addr - $remote_user [$time_local] "$request" '
      '$status $body_bytes_sent "$http_referer" '
      '"$http_user_agent" "$http_x_forwarded_for"'

Configures Nginx's [`log_format`](http://nginx.org/en/docs/http/ngx_http_log_module.html#log_format). options.

    nginx_default_release: ""

(For Debian/Ubuntu only) Allows you to set a different repository for the installation of Nginx. As an example, if you are running Debian's wheezy release, and want to get a newer version of Nginx, you can install the `wheezy-backports` repository and set that value here, and Ansible will use that as the `-t` option while installing Nginx.

    nginx_ppa_use: false
    nginx_ppa_version: stable

(For Ubuntu only) Allows you to use the official Nginx PPA instead of the system's package. You can set the version to `stable` or `development`.

    nginx_official_repo_enabled: true
    nginx_yum_repo_enabled: true

`nginx_official_repo_enabled` installs the nginx.org repo on Debian/Ubuntu/RHEL. `nginx_yum_repo_enabled` is the geerlingguy alias: on RedHat the repo is enabled if either flag is true. Set both to `false` for distro packages or Satellite.

    nginx_zypper_repo_enabled: true

(For Suse only) Set this to `false` to disable the installation of the `nginx` zypper repository. This could be necessary if you want the default OS stable packages, or if you use Suse Manager.

    nginx_service_state: started
    nginx_service_enabled: yes

By default, this role will ensure Nginx is running and enabled at boot after Nginx is configured. You can use these variables to override this behavior if installing in a container or further control over the service state is required.

## Overriding configuration templates

If you can't customize via variables because an option isn't exposed, you can override the template used to generate the virtualhost configuration files or the `nginx.conf` file.

```yaml
nginx_conf_template: "nginx.conf.j2"
nginx_vhost_template: "vhost.j2"
```

If necessary you can also set the template on a per vhost basis.

```yaml
nginx_vhosts:
  - listen: "80 default_server"
    server_name: "site1.example.com"
    root: "/var/www/site1.example.com"
    index: "index.php index.html index.htm"
    template: "{{ playbook_dir }}/templates/site1.example.com.vhost.j2"
  - server_name: "site2.example.com"
    root: "/var/www/site2.example.com"
    index: "index.php index.html index.htm"
    template: "{{ playbook_dir }}/templates/site2.example.com.vhost.j2"
```

You can either copy and modify the provided template, or extend it with [Jinja2 template inheritance](http://jinja.pocoo.org/docs/2.9/templates/#template-inheritance) and override the specific template block you need to change.

### Example: Configure gzip in nginx configuration

Set the `nginx_conf_template` to point to a template file in your playbook directory.

```yaml
nginx_conf_template: "{{ playbook_dir }}/templates/nginx.conf.j2"
```

Create the child template in the path you configured above and extend `geerlingguy.nginx` template file relative to your `playbook.yml`.

```
{% extends 'roles/geerlingguy.nginx/templates/nginx.conf.j2' %}

{% block http_gzip %}
    gzip on;
    gzip_proxied any;
    gzip_static on;
    gzip_http_version 1.0;
    gzip_disable "MSIE [1-6]\.";
    gzip_vary on;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/x-javascript
        application/json
        application/xml
        application/xml+rss
        application/xhtml+xml
        application/x-font-ttf
        application/x-font-opentype
        image/svg+xml
        image/x-icon;
    gzip_buffers 16 8k;
    gzip_min_length 512;
{% endblock %}
```

## Dependencies

None.

## Example Playbook

    - hosts: server
      roles:
        - { role: geerlingguy.nginx }

## License

MIT / BSD

## Author Information

This role was created in 2014 by [Jeff Geerling](https://www.jeffgeerling.com/), author of [Ansible for DevOps](https://www.ansiblefordevops.com/).
