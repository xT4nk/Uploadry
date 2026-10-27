<?php
// Database configuration for SnapShare.
// NOTE (lab): the DB password here is intentionally REUSED as the system
// password of the 'michael' account -> credential-reuse lateral movement.
$DB_HOST = '127.0.0.1';
$DB_NAME = 'snapshare';
$DB_USER = 'michael';
$DB_PASS = 'Photos#Backup2023';
// (no real DB is used by the app; this file exists to be found/leaked)
