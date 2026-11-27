<div align="center">

<img src="App/Assets.xcassets/BrandIcon.imageset/BrandIcon.png" width="128" height="128" alt="幻彩希阅读" />

# 幻彩希阅读

**搜书快一点，读书舒服一点。**

一款优先兼容阅读书源的 iOS 阅读器

![iOS 15+](https://img.shields.io/badge/iOS-15%2B-315C50)
![Swift](https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white)
[![GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue)](LICENSE)

[下载安装](#下载安装) · [主要功能](#主要功能) · [应用截图](#应用截图) · [书源说明](#书源说明) · [问题反馈](https://github.com/hcx1002/legado-ios/issues)

</div>

**幻彩希阅读**是一款面向 iOS / iPadOS 的阅读应用，由 [幻彩希](https://github.com/hcx1002) 基于 [Aminark/legado-ios](https://github.com/Aminark/legado-ios) 二次开发与维护，优先兼容阅读（Legado）书源，同时支持本地 TXT / EPUB 电子书阅读。

> **免责声明**：本应用不提供、内置或分发任何网络书源与在线书库。书源需由用户自行获取或编写后导入。

## 下载安装

支持 **iOS / iPadOS 15.0 及以上**。

- **IPA 下载**：前往 [GitHub Releases](https://github.com/hcx1002/legado-ios/releases) 下载 `.ipa` 文件，使用自己的签名工具或自签证书安装。
- **巨魔安装**：已支持 [TrollStore](https://github.com/opa334/TrollStore) 的设备可直接安装 IPA。
- **源码构建**：使用 macOS 和 Xcode 打开 `Legado.xcodeproj` 编译运行，详见 [开发指南](docs/DEVELOPMENT.md)。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| 阅读书源 | 支持 JSON、文件、URL、`legado://` 链接和二维码导入，支持书源分组、编辑、调试与自定义书源登录 |
| 快速搜书 | 多书源并发搜索、结果缓存与同书多源合并 |
| 书架管理 | 列表/网格视图、自定义分组、章节更新、换源与本地阅读进度持久化 |
| 阅读体验 | 字号、行距、边距、字体导入、日夜主题联动、仿真/平移/滚动翻页、音量键翻页、目录与书签 |
| 段评与章评 | 支持 `ruleReview` 本章评论，并兼容书源内联 SVG 段评/本章说卡片，点击可半屏查看评论 |
| 本地阅读 | TXT 自定义目录规则；基于 Readium 支持无 DRM EPUB 2/3 原书排版与纯文本朗读模式切换 |
| 语音朗读 | 支持系统语音朗读与自定义 HTTP TTS 配置 |
| 阅读工具 | 替换净化规则、阅读记录、阅读时长统计、离线缓存管理与 RSS 订阅 |

## 应用截图

<table>
  <tr>
    <td align="center"><strong>书架</strong><br /><a href="docs/images/bookshelf.png"><img src="docs/images/bookshelf.png" width="230" alt="幻彩希阅读书架" /></a></td>
    <td align="center"><strong>搜书</strong><br /><a href="docs/images/search.png"><img src="docs/images/search.png" width="230" alt="幻彩希阅读搜索结果与缓存展示" /></a></td>
    <td align="center"><strong>书源管理</strong><br /><a href="docs/images/sources.png"><img src="docs/images/sources.png" width="230" alt="幻彩希阅读书源管理" /></a></td>
  </tr>
  <tr>
    <td align="center"><strong>日间阅读</strong><br /><a href="docs/images/reader.png"><img src="docs/images/reader.png" width="230" alt="幻彩希阅读纸色主题" /></a></td>
    <td align="center"><strong>夜间阅读</strong><br /><a href="docs/images/reader-dark.png"><img src="docs/images/reader-dark.png" width="230" alt="幻彩希阅读夜间主题" /></a></td>
    <td align="center"><strong>我的</strong><br /><a href="docs/images/profile.png"><img src="docs/images/profile.png" width="230" alt="幻彩希阅读个人中心" /></a></td>
  </tr>
</table>

<details>
<summary>查看更多截图：发现、阅读统计、关于</summary>

<table>
  <tr>
    <td align="center"><strong>发现</strong><br /><a href="docs/images/explore.png"><img src="docs/images/explore.png" width="230" alt="幻彩希阅读发现页面" /></a></td>
    <td align="center"><strong>阅读统计</strong><br /><a href="docs/images/statistics.png"><img src="docs/images/statistics.png" width="230" alt="幻彩希阅读统计页面" /></a></td>
    <td align="center"><strong>关于</strong><br /><a href="docs/images/about.png"><img src="docs/images/about.png" width="230" alt="幻彩希阅读关于页面" /></a></td>
  </tr>
</table>

</details>

## 快速开始

1. 安装应用后，进入「我的 → 书源管理」导入阅读书源，或直接在书架导入本地 TXT / EPUB 文件。
2. 在书架顶部点击搜索查找书籍，加入书架后即可开始阅读。
3. 在阅读页点击屏幕中央呼出菜单，可调整排版、主题、翻页方式、音量键翻页、书签与朗读设置。

## 书源说明

幻彩希阅读仅提供书源解析、书籍管理和阅读功能，**不提供、内置或分发网络书源**。在线书籍正文、封面、简介及订阅内容均由第三方网站提供，版权归原作者或合法权利人所有。请仅在合法授权范围内使用并支持正版阅读。

## 上游致谢

本项目基于 [Aminark](https://github.com/Aminark) 开源的 [legado-ios](https://github.com/Aminark/legado-ios)（以及上游 [LegadoTeam/legado](https://github.com/LegadoTeam/legado)）进行二次开发与维护，感谢原作者及开源社区的贡献。

## 反馈与贡献

遇到问题或有功能建议，欢迎提交 [Issue](https://github.com/hcx1002/legado-ios/issues) 或 Pull Request，详情见 [贡献指南](CONTRIBUTING.md)。反馈前请先去除日志和书源规则中的账号、Cookie、Token 等个人敏感信息。

## 开源许可

本项目采用 **GNU GPL v3** 许可协议，详见 [LICENSE](LICENSE)；第三方组件与材料许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
