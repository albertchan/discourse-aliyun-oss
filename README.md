discourse-aliyun-oss
====================

A Discourse plugin for uploading to static assets to Aliyun's OSS.

_Warning_: This plugin is still experimental so try it in development mode
before doing anything serious with it!

## Installation

* Edit your web template by adding the gem dependency and the project clone url:

```
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - mkdir -p plugins
          - git clone https://github.com/albertchan/discourse-aliyun-oss.git
```

* Rebuild your web container so that the plugin installs

## Migration

If you're currently using s3 for storing avatars, uploaded images and
attachments and want to move away from s3 completely, you'll need to run the
`migrate_from_s3_to_oss` migration task.

How to use:

* Disable the `enable_s3_uploads` site setting
* SSH into your server
* `cd /var/discourse`
* `./launcher enter app`
* `cd /var/www/discourse && su discourse -c 'bundle exec rake uploads:migrate_from_s3_to_oss'`

## Contributing

Pull requests welcome! See CONTRIBUTING.md
