class OssHelper

  class SettingMissing < StandardError; end

  attr_reader :oss_bucket_name

  def initialize(oss_upload_bucket, tombstone_prefix='', options={})
    @oss_options = default_oss_options.merge(options)
    @oss_region = SiteSetting.oss_region

    @oss_bucket_name, @oss_bucket_folder_path = begin
      raise Discourse::InvalidParameters.new("oss_bucket") if oss_upload_bucket.blank?
      oss_upload_bucket.downcase.split("/".freeze, 2)
    end

    @tombstone_prefix =
      if @oss_bucket_folder_path
        File.join(@oss_bucket_folder_path, tombstone_prefix)
      else
        tombstone_prefix
      end

    check_missing_options
  end

  def upload(file, path, options={})
    path = get_path_for_oss_upload(path)
    oss_bucket.put_object(path) do | stream |
      stream << file.read
    end
    path
  end

  def remove(oss_filename, copy_to_tombstone=false)
    bucket = oss_bucket

    # delete the file
    bucket.delete_object(get_path_for_oss_upload(oss_filename)).delete
  end

  def update_tombstone_lifecycle(grace_period)
    return if @tombstone_prefix.blank?
  end

  private

  def get_endpoint(region)
    "http://#{region}.aliyuncs.com"
  end

  def get_path_for_oss_upload(path)
    path = File.join(@oss_bucket_folder_path, path) if @oss_bucket_folder_path
    path
  end

  def default_oss_options
    opts = {}
    opts[:endpoint] = get_endpoint(SiteSetting.oss_region)
    opts[:access_key_id] = SiteSetting.oss_access_key_id
    opts[:access_key_secret] = SiteSetting.oss_access_key_secret

    opts
  end

  def oss_resource
    Aliyun::OSS::Client.new(@oss_options)
  end

  def oss_bucket
    bucket = oss_resource.get_bucket(@oss_bucket_name)
    bucket
  end

  def check_missing_options
    raise SettingMissing.new("access_key_id") if @oss_options[:access_key_id].blank?
    raise SettingMissing.new("access_key_secret") if @oss_options[:access_key_secret].blank?
    raise SettingMissing.new("region") if @oss_region.blank?
  end
end
