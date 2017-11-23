S3 Backup
----------------

A simple Ruby script to back up PostgreSQL database tables, MongoDB databases, full directories, and groups of single files to S3 storage.

Flags
 
 For backup only databases:
 `--only_db=true`
 
 For backup only files:
 `--only_files=true`

Example of crone configuration:

`15 3 * * * /usr/bin/ruby /home/username/backups/simple-s3-backup.rb`
