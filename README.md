discourse-aliyun-oss
====================

A Discourse plugin for uploading to static assets to Aliyun's OSS.

## Installation

* Edit your web template and install the gem dependency:

```
run:
  - exec: echo "Beginning of custom commands"
  - exec: gem install aliyun-sdk
```

* Edit your web template and add the project clone url:

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
* `cd plugins/discourse-aliyun-oss/lib/tasks`
* `rake uploads:migrate_from_s3_to_oss`
* `rake posts:rebake`

## Contributing

Pull requests welcome! See CONTRIBUTING.md
