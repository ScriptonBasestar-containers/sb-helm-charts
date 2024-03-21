<?php
$directory_custom_apps = getenv('NEXTCLOUD_PATH_CUSTOM_APPS');
if (! $directory_custom_apps) {
  $directory_custom_apps = OC::$SERVERROOT.'/custom_apps';
}

$CONFIG = array (
  'apps_paths' => array (
    0 => array (
      'path'     => OC::$SERVERROOT.'/apps',
      'url'      => '/apps',
      'writable' => false,
    ),
    1 => array (
      'path'     => $directory_custom_apps,
      'url'      => '/custom_apps',
      'writable' => true,
    ),
  ),
);
