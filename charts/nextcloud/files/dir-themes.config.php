<?php
$directory_themes = getenv('NEXTCLOUD_PATH_THEMES');
if (! $directory_themes) {
  $directory_themes = OC::$SERVERROOT.'/themes';
}
$CONFIG = array (
  'datadirectory' = $directory_themes;
)