# discourse-bilibili-onebox

## Introduction

| | | |
| --- | --- | --- |
| :discourse: | **Summary** | **Discourse Bilibili Onebox** lets any Discourse community play Bilibili videos inline without leaving the topic. |
| :hammer_and_wrench: | **Repository** | [https://github.com/scavin/discourse-bilibili-onebox/](https://github.com/scavin/discourse-bilibili-onebox/) |
| :movie_camera: | **Demo** | [https://meta.appinn.net/t/topic/55832](https://meta.appinn.net/t/topic/55832) |
| :open_book: | **Install guide** | [How to install plugins in Discourse](https://meta.discourse.org/t/install-plugins-in-discourse/19157) |

The code is intentionally tiny (AI-assisted) and already powers the Appinn community. Videos **never** autoplay.

`[date=2025-11-20 timezone="Asia/Shanghai"]` Support for `b23.tv` short links is available.

### Installation

Edit `app.yml` and locate the `Plugins go here` section:

```
## Plugins go here
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - mkdir -p plugins
          - git clone https://github.com/discourse/docker_manager.git
```

Add the plugin clone command to the end of that block:

```
- git clone https://github.com/scavin/discourse-bilibili-onebox.git
```

Then rebuild:

```
./launcher rebuild app
```

### Usage

Paste a Bilibili URL on its own line inside the composer. Links copied from the mobile share dialog also work. Examples:

* `https://www.bilibili.com/video/BV1Xw4m12744/?share_source=copy_web&vd_source=be7dd26febc616d50c50`
* `https://m.bilibili.com/video/BV1Xw4m12744?buvid=Z943139958166C09&is_story_h5=false&mid=bD8izjDQ%3D%3D&plat_id=147&share_from=ugc&share_medium=iphon`
* `https://www.bilibili.com/video/BV1Xw4m12744/`
* `https://www.bilibili.com/video/BV1Xw4m12744`
* `https://b23.tv/PAjRV1w`

The old bug where URLs without a trailing slash refused to render has been fixed.

### Allowed iframes

Screenshot reference: <https://h1.appinn.me/file/1736215861521_Screen-20250107100857@2x.jpg>

```
https://player.bilibili.com/
https://www.bilibili.com/
```

### Demo

https://meta.appinn.net/t/topic/55832

### Maintenance plan

Maintenance continues as long as Bilibili allows embeds and the Appinn forum keeps running.

- [x] Add `b23.tv` short-link support

---

Thanks to [Discourse 中文本地化服务集合](https://github.com/erickguan/discourse-chinese-localization-pack).
