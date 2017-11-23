#!/usr/bin/env ruby

# Add local directory to LOAD_PATH
$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__))

%w(s3 fileutils).each do |lib|
  require lib
end

require 'settings'
require 'flags'

# Initial setup
timestamp = Time.now.strftime('%Y%m%d-%H%M')
full_tmp_path = File.join(File.expand_path(File.dirname(__FILE__)), TMP_BACKUP_PATH)

# Init service
S3.host = S3_CONF[:host]

service = S3::Service.new(
  access_key_id: S3_CONF[:access_key_id],
  secret_access_key: S3_CONF[:secret_access_key],
  use_ssl: S3_CONF[:use_ssl]
)

# Find/create the backup bucket
bucket = service.buckets.find(S3_BUCKET)

unless bucket
  begin
    bucket = service.buckets.build(S3_BUCKET)
    bucket.save
  rescue Error => e
    puts "There was a problem creating the bucket: #{e}"
    exit
  end
end

# Create tmp directory
FileUtils.mkdir_p full_tmp_path

# Perform PostgreSQL backups
if !only_files? && defined?(POSTGRESQL_DBS)
  POSTGRESQL_DBS.each do |db|
    db_filename = "db-#{db}-#{timestamp}.gz"
    system("#{PG_DUMP_CMD} #{db} | #{GZIP_CMD} -c > #{full_tmp_path}/#{db_filename}")
    object = bucket.objects.build(db_filename)
    object.content = open("#{full_tmp_path}/#{db_filename}")
    object.save
  end
end

# Perform MongoDB backups
if !only_files? && defined?(MONGO_DBS)
  mdb_dump_dir = File.join(full_tmp_path, 'mdbs')
  FileUtils.mkdir_p mdb_dump_dir
  MONGO_DBS.each do |mdb|
    mdb_filename = "mdb-#{mdb}-#{timestamp}.tgz"
    system("#{MONGODUMP_CMD} -h #{MONGO_HOST} -d #{mdb} -o #{mdb_dump_dir} && cd #{mdb_dump_dir}/#{mdb} && #{TAR_CMD} -czf #{full_tmp_path}/#{mdb_filename} .")
    object = bucket.objects.build(mdb_filename)
    object.content = open("#{full_tmp_path}/#{mdb_filename}")
    object.save
  end
  FileUtils.remove_dir mdb_dump_dir
end

# Perform directory backups
if !only_db? && defined?(DIRECTORIES)
  DIRECTORIES.each do |name, dir|
    dir_filename = "dir-#{name}-#{timestamp}.tgz"
    system("cd #{dir} && #{TAR_CMD} -czf #{full_tmp_path}/#{dir_filename} .")
    object = bucket.objects.build(dir_filename)
    object.content = open("#{full_tmp_path}/#{dir_filename}")
    object.save
  end
end

# Perform single files backups
if !only_db? && defined?(SINGLE_FILES)
  SINGLE_FILES.each do |name, files|

    # Create a directory to collect the files
    files_tmp_path = File.join(full_tmp_path, "#{name}-tmp")
    FileUtils.mkdir_p files_tmp_path

    # Filename for files
    files_filename = "files-#{name}-#{timestamp}.tgz"

    # Copy files to temp directory
    FileUtils.cp files, files_tmp_path

    # Create archive & copy to S3
    system("cd #{files_tmp_path} && #{TAR_CMD} -czf #{full_tmp_path}/#{files_filename} .")
    object = bucket.objects.build(files_filename)
    object.content = open("#{full_tmp_path}/#{files_filename}")
    object.save

    # Remove the temporary directory for the files
    FileUtils.remove_dir files_tmp_path
  end
end

# Remove tmp directory
FileUtils.remove_dir full_tmp_path

# Now, clean up unwanted archives
cutoff_date = Time.now.utc.to_i - (DAYS_OF_ARCHIVES * 864_00)
bucket.objects.select { |o| o.last_modified.to_i < cutoff_date }.each(&:destroy)
