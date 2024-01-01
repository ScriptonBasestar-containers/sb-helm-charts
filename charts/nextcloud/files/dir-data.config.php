<?php
$directory_data = getenv('NEXTCLOUD_PATH_DATA');
if (! $directory_data) {
  $directory_data = OC::$SERVERROOT.'/data';
}
$CONFIG = array (
  'datadirectory' = $directory_data;
)