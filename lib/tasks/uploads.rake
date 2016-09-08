################################################################################
# migrate_from_s3_to_oss
################################################################################

task "uploads:migrate_from_s3_to_oss" => :environment do
  require "db_helper"

  ENV["RAILS_DB"] ? migrate_from_s3_to_oss : migrate_all_from_s3_to_oss
end

def get_filename(url)
  begin
    uri = URI.parse("http:#{url}")
    f = uri.open("rb", read_timeout: 5, redirect: true, allow_redirections: :all)
    filename = if f.meta
      File.basename(uri.path)
    end
  rescue
    nil
  ensure
    f.try(:close!) rescue nil
  end
end

def guess_filename(url, raw)
  begin
    uri = URI.parse("http:#{url}")
    f = uri.open("rb", read_timeout: 5, redirect: true, allow_redirections: :all)
    filename = if f.meta && f.meta["content-disposition"]
      f.meta["content-disposition"][/filename="([^"]+)"/, 1].presence
    end
    filename ||= raw[/<a class="attachment" href="(?:https?:)?#{Regexp.escape(url)}">([^<]+)<\/a>/, 1].presence
    filename ||= File.basename(url)
    filename
  rescue
      nil
  ensure
    f.try(:close!) rescue nil
  end
end

def migrate_all_from_s3_to_oss
  RailsMultisite::ConnectionManagement.each_connection { migrate_from_s3_to_oss }
end

def migrate_from_s3_to_oss
  require "file_store/s3_store"

  puts "Running migrate_from_s3_to_oss...\n"

  # make sure S3 is disabled
  if SiteSetting.enable_s3_uploads
    puts "You must disable S3 uploads before running that task."
    return
  end

  # make sure OSS is enabled
  if !SiteSetting.enable_oss_uploads
    puts "You must enable OSS uploads before running that task."
    return
  end

  # make sure S3 bucket is set
  if SiteSetting.s3_upload_bucket.blank?
    puts "The S3 upload bucket must be set before running that task."
    return
  end

  # make sure S3 bucket is set
  if SiteSetting.oss_upload_bucket.blank?
    puts "The OSS upload bucket must be set before running that task."
    return
  end

  db = RailsMultisite::ConnectionManagement.current_db

  puts "Migrating uploads from S3 to OSS storage for '#{db}'...\n\n"

  s3_base_url = FileStore::S3Store.new.absolute_base_url
  max_file_size_kb = [SiteSetting.max_image_size_kb, SiteSetting.max_attachment_size_kb].max.kilobytes

  UserProfile.unscoped.find_each do |profile|
    if profile.profile_background
      profile.profile_background.match(/(#{Regexp.escape(s3_base_url)}\/(\S*)\/(\w+\.\w+))/) do |url, dummy, fn|
        puts "user_id: #{profile.user_id}"
        puts "profile_background URL: #{url}"
        if filename = get_filename(url)
          puts "filename: #{filename}"
          file = FileHelper.download("http:#{url}", 20.megabytes, "from_s3", true)
          if upload = Upload.create_for(profile.user_id || -1, file, filename, File.size(file))
            profile.profile_background = upload.url
            profile.save
            puts "OK :)"
          else
            puts "KO :("
          end
          puts upload.url, ""
        else
          puts "NO FILENAME :("
        end
      end
    end

    if profile.card_background
      profile.card_background.match(/(#{Regexp.escape(s3_base_url)}\/(\S*)\/(\w+\.\w+))/) do |url, dummy, fn|
        puts "user_id: #{profile.user_id}"
        puts "card_background URL: #{url}"
        if filename = get_filename(url)
          puts "filename: #{filename}"
          file = FileHelper.download("http:#{url}", 20.megabytes, "from_s3", true)
          if upload = Upload.create_for(profile.user_id || -1, file, filename, File.size(file))
            profile.card_background = upload.url
            profile.save
            puts "OK :)"
          else
            puts "KO :("
          end
          puts upload.url, ""
        else
          puts "NO FILENAME :("
        end
      end
    end
  end

  Post.unscoped.find_each do |post|
    if post.raw[s3_base_url]
      post.raw.scan(/(#{Regexp.escape(s3_base_url)}\/(\S*)\/(\w+\.\w+))/).each do |url, dummy, fn|
        begin
          puts "Post ID: #{post.id}"
          puts "Upload URL: #{url}"
          if filename = guess_filename(url, post.raw)
            puts "FILENAME: #{filename}"
            file = FileHelper.download("http:#{url}", 20.megabytes, "from_s3", true)
            if upload = Upload.create_for(post.user_id || -1, file, filename, File.size(file))
              post.raw = post.raw.gsub(/(https?:)?#{Regexp.escape(url)}/, upload.url)
              post.save
              post.rebake!
              puts "OK :)"
            else
              puts "KO :("
            end
            puts post.full_url, ""
          else
            puts "NO FILENAME :("
          end
        rescue => e
          puts "EXCEPTION: #{e.message}"
        end
      end
    end
  end

  puts "Done!\n\n"
end

################################################################################
# migrate to OSS
################################################################################

task "uploads:migrate_to_oss" => :environment do
  require "file_store/s3_store"
  require "file_store/local_store"
  require "db_helper"

  ENV["RAILS_DB"] ? migrate_to_oss : migrate_to_oss_all_sites
end

def migrate_to_oss_all_sites
  RailsMultisite::ConnectionManagement.each_connection { migrate_to_oss }
end

def migrate_to_oss
  # make sure s3 is enabled
  if !SiteSetting.enable_oss_uploads
    puts "You must enable OSS uploads before running that task"
    return
  end

  db = RailsMultisite::ConnectionManagement.current_db

  puts "Migrating uploads to OSS (#{SiteSetting.oss_upload_bucket}) for '#{db}'..."

  # will throw an exception if the bucket is missing
  local = FileStore::LocalStore.new
  oss = FileStore::OssStore.new
  s3 = FileStore::S3Store.new

  # Migrate all uploads
  Upload.where.not(sha1: nil)
        .where("url NOT LIKE '#{s3.absolute_base_url}%'")
        .find_each do |upload|
    # remove invalid uploads
    if upload.url.blank?
      upload.destroy!
      next
    end
    # store the old url
    from = upload.url
    # retrieve the path to the local file
    path = local.path_for(upload)
    # make sure the file exists locally
    if !path or !File.exists?(path)
      putc "X"
      next
    end

    begin
      file = File.open(path)
      content_type = `file --mime-type -b #{path}`.strip
      to = oss.store_upload(file, upload, content_type)
    rescue
      putc "X"
      next
    ensure
      file.try(:close!) rescue nil
    end

    # remap the URL
    DbHelper.remap(from, to)

    putc "."
  end
end
