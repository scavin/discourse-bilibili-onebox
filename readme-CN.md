# discourse-bilibili-onebox

## 简介

| | | |
| --- | --- | --- |
| :discourse: | **摘要** | **Discourse Bilibili Onebox** 是一个可以让 Discourse 社区直接播放 Bilibili 视频的插件。 |
| :hammer_and_wrench: | **项目库链接** | [https://github.com/scavin/discourse-bilibili-onebox/](https://github.com/scavin/discourse-bilibili-onebox/) |
| :open_book: | **安装指南（英文）** | [How to install plugins in Discourse](https://meta.discourse.org/t/install-plugins-in-discourse/19157) |

代码很简单，由 AI 生成，已经在小众软件论坛使用。**不会**自动播放。

`[date=2025-11-20 timezone="Asia/Shanghai"]` 已支持 `b23.tv` 短链接

### 安装方式

在 `app.yml` 文件的 `Plugins go here` 部分

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

最后一行添加

```
- git clone https://github.com/scavin/discourse-bilibili-onebox.git
```

然后重建容器：

```
./launcher rebuild app
```

### 使用方式

直接在编辑器中粘贴 B 站视频即可，**需要单独一行**，支持从 B 站移动端分享的链接。具体如下：

* `https://www.bilibili.com/video/BV1Xw4m12744/?share_source=copy_web&vd_source=be7dd26febc616d50c50`
* `https://m.bilibili.com/video/BV1Xw4m12744?buvid=Z943139958166C09&is_story_h5=false&mid=bD8izjDQ%3D%3D&plat_id=147&share_from=ugc&share_medium=iphon`
* `https://www.bilibili.com/video/BV1Xw4m12744/`
* `https://www.bilibili.com/video/BV1Xw4m12744`
* `https://b23.tv/PAjRV1w`

此问题已修复。<s>目前有个 bug，不带 `/` 结尾的链接不会工作，手动加上 `/` 即可。</s>

### allowed iframes 设置

https://h1.appinn.me/file/1736215861521_Screen-20250107100857@2x.jpg

```
https://player.bilibili.com/
https://www.bilibili.com/
```

### 使用效果

https://meta.appinn.net/t/topic/55832

### 维护计划

在 B 站支持外链，且论坛正常的情况下会一直维护下去。

- [x] 计划支持短链接 `b23.tv`。

---

感谢 [Discourse 中文本地化服务集合](https://github.com/erickguan/discourse-chinese-localization-pack)。
