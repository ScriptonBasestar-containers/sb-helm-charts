<?php
$CONFIG = array (
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'apps_paths' => 
  array (
    0 => 
    array (
      'path' => '/var/www/html/apps',
      'url' => '/apps',
      'writable' => false,
    ),
    1 => 
    array (
      'path' => '/nextcloud/custom_apps',
      'url' => '/custom_apps',
      'writable' => true,
    ),
  ),
  'datadirectory' => '/nextcloud/data',
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' => 
  array (
    'host' => 'redis-master.data.svc.cluster.local',
    'password' => 'i^txoGxLHYGFMS22',
    'port' => 6379,
  ),
  'overwritehost' => 'nas.polypia.net',
  'overwriteprotocol' => 'https',
  'overwrite.cli.url' => 'https://nas.polypia.net',
  'trusted_proxies' => 
  array (
    0 => '10.42.0.0/16',
  ),
  'upgrade.disable-web' => true,
  'passwordsalt' => 'wsckkbyenEQfgY22Gfue6ouF/YLXZV',
  'secret' => 'WdcHYhIjaKVqlNd2G81kOBUxy6eLWKlehp+cXKDOLH64lZYl',
  'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => 'nas.polypia.net',
  ),
  'dbtype' => 'pgsql',
  'version' => '28.0.1.1',
  'dbname' => 'nextcloud_db',
  'dbhost' => 'postgresql.data.svc.cluster.local',
  'dbport' => '',
  'dbtableprefix' => 'oc_',
  'dbuser' => 'nextcloud_user',
  'dbpassword' => 'Lak#ej!!S9Y5zZRV!i',
  'installed' => true,
  'instanceid' => 'oc1fcrw8ev53',
);
