# tianwangdev.com

田旺（Tian Wang）的个人网站 —— 单页静态站点，部署在 Cloudflare Workers（静态资产），线上地址 <https://tianwangdev.com>。

## 内容

| 路径 | 说明 |
| --- | --- |
| `index.html` | 站点页面。单文件，无构建步骤、无外部依赖、无第三方脚本 |
| `tools/` | 「提交 / 收取」助手：双击 `tools\同步.bat` 打开菜单（提交并上传 / 收取更新 / 查看状态） |

## 本地预览

用浏览器直接打开 `index.html` 即可（无需安装任何工具）：

```powershell
Start-Process .\index.html
```

## 部署

改完 `index.html` 后，把这一份静态资产重新上传到 Cloudflare 上托管本站的 Worker 即可。
托管、DNS、以及裸域 `tianwangdev.com` → `www.tianwangdev.com` 的 301 跳转都在 Cloudflare 侧配置。

## 提交与收取

双击 `tools\同步.bat` 会打开菜单：

```
[1] 提交并上传    (git add / commit / push)
[2] 收取更新      (git fetch / pull)
[3] 查看状态
[0] 退出
```

**换设备后的标准动作**：先 `[2] 收取更新` 拿最新内容，改完 `index.html` 再 `[1] 提交并上传`。
同一时刻尽量只在一台设备上改，避免两边各改一份后合并麻烦。

命令行调用（在仓库目录下执行）：

```powershell
.\tools\sync.ps1 -Action status                # 只看状态
.\tools\sync.ps1 -Action pull                  # 只收取更新
.\tools\sync.ps1 -Action push -Message "说明"  # 只提交并上传
```

提交说明留空时自动用时间戳；收取用 `git pull --ff-only`，本地与远程分叉时不会强行合并，只提示后续处理命令
