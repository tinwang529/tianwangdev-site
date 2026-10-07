# tianwangdev.com

田旺（Tian Wang）的个人网站 —— 单页静态站点，部署在 Cloudflare Workers（静态资产），线上地址 <https://tianwangdev.com>。

## 内容

| 路径 | 说明 |
| --- | --- |
| `index.html` | 站点页面。单文件，无构建步骤、无外部依赖、无第三方脚本 |

## 本地预览

用浏览器直接打开 `index.html` 即可（无需安装任何工具）：

```powershell
Start-Process .\index.html
```

## 部署

改完 `index.html` 后，把这一份静态资产重新上传到 Cloudflare 上托管本站的 Worker 即可。
托管、DNS、以及裸域 `tianwangdev.com` → `www.tianwangdev.com` 的 301 跳转都在 Cloudflare 侧配置。

## 关于这个仓库

- 这里只放站点本身的源码，是好读、可公开的那部分。
- 发信脚本、同步助手等私人工具不在这个仓库。
