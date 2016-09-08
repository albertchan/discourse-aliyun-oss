# name: emedia-aliyun-oss
# about: Upload files to Aliyun OSS
# version: 0.0.1
# authors: Albert Chan for Emedia Developers

require "aliyun/oss"
require_dependency "file_helper"
require_dependency "file_store/base_store.rb"

enabled_site_setting :enable_oss_uploads

after_initialize do

  # A helper class for Aliyun OSS SDK
  load File.expand_path("../lib/oss_helper.rb", __FILE__)

  # A plugin to upload user files to Aliyun OSS
  module FileStore
    class OssStore < ::FileStore::BaseStore
      TOMBSTONE_PREFIX ||= "tombstone/"

      def initialize(oss_helper=nil)
        @oss_helper = oss_helper || OssHelper.new(oss_bucket, TOMBSTONE_PREFIX)
      end

      def store_upload(file, upload, content_type = nil)
        path = get_path_for_upload(upload)
        store_file(file, path, filename: upload.original_filename, content_type: content_type, cache_locally: true)
      end

      def store_optimized_image(file, optimized_image)
        path = get_path_for_optimized_image(optimized_image)
        store_file(file, path)
      end

      # options
      #   - filename
      #   - content_type
      #   - cache_locally
      def store_file(file, path, opts={})
        filename     = opts[:filename].presence
        content_type = opts[:content_type].presence
        # cache file locally when needed
        cache_file(file, File.basename(path)) if opts[:cache_locally]
        # stored uploaded are public by default
        options = { acl: "public-read" }
        # add a "content disposition" header for "attachments"
        options[:content_disposition] = "attachment; filename=\"#{filename}\"" if filename && !FileHelper.is_image?(filename)
        # add a "content type" header when provided
        options[:content_type] = content_type if content_type
        # if this fails, it will throw an exception
        path = @oss_helper.upload(file, path, options)
        # return the upload url
        "#{absolute_base_url}/#{path}"
      end

      def remove_file(url, path)
        return unless has_been_uploaded?(url)
        # copy the removed file to tombstone
        @oss_helper.remove(path, true)
      end

      def has_been_uploaded?(url)
        return false if url.blank?

        base_hostname = URI.parse(absolute_base_url).hostname
        return true if url[base_hostname]

        return false if SiteSetting.oss_cdn_url.blank?
        cdn_hostname = URI.parse(SiteSetting.oss_cdn_url || "").hostname
        cdn_hostname.presence && url[cdn_hostname]
      end

      def absolute_base_url
        # see https://help.aliyun.com/document_detail/31837.html for
        # OSS endpoints by region
        bucket = @oss_helper.oss_bucket_name
        @absolute_base_url ||= if SiteSetting.oss_region == "oss-cn-shenzhen"
          "//#{bucket}.oss-cn-shenzhen.aliyuncs.com"
        else
          "//#{bucket}.#{SiteSetting.oss_region}.aliyuncs.com"
        end
      end

      def upload_path
        "/uploads/#{RailsMultisite::ConnectionManagement.current_db}"
      end

      def external?
        true
      end

      def path_for(upload)
        url = upload.try(:url)
        FileStore::LocalStore.new.path_for(upload) if url && url[/^\/[^\/]/]
      end

      def cdn_url(url)
        return url if SiteSetting.oss_cdn_url.blank?
        schema = url[/^(https?:)?\/\//, 1]
        url.sub("#{schema}#{absolute_base_url}", SiteSetting.oss_cdn_url)
      end

      def cache_avatar(avatar, user_id)
        source = avatar.url.sub(absolute_base_url + "/", "")
        destination = avatar_template(avatar, user_id).sub(absolute_base_url + "/", "")
        @oss_helper.copy(source, destination)
      end

      def avatar_template(avatar, user_id)
        UserAvatar.external_avatar_url(user_id, avatar.upload_id, avatar.width)
      end

      def oss_bucket
        raise Discourse::SiteSettingMissing.new("oss_upload_bucket") if SiteSetting.oss_upload_bucket.blank?
        SiteSetting.oss_upload_bucket.downcase
      end
    end
  end

  if SiteSetting.enable_oss_uploads && !SiteSetting.enable_s3_uploads

    Discourse.module_eval do
      def self.store
        puts "# =========================\n"
        puts "# emedia-aliyun-oss        \n"
        puts "# =========================\n"
        FileStore::OssStore.new
      end
    end
  end
end
