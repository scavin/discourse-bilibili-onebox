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

* `https://www.bilibili.com/video/BV1WEgJzMEK3/?spm_id_from=333.1387.homepage.video_card.click`
* `https://www.bilibili.com/video/BV1WEgJzMEK3/?spm_id_from=333.1387.homepage.video_card.click&vd_source=b0a719e1950c150a97859195679d417a`
* `https://www.bilibili.com/video/BV1WEgJzMEK3/`
* `https://www.bilibili.com/video/BV1WEgJzMEK3`
* `https://b23.tv/hiS7rgR`

The old bug where URLs without a trailing slash refused to render has been fixed.

### Allowed iframes

![Allowed iframes configuration](./Screen-20250107100857@2x.jpg)

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
