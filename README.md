# Volans xui-net

自包含的网络侧栈，一条命令在自己的服务器上部署 **xui 面板**（基于
[3x-ui](https://github.com/MHSanaei/3x-ui) 的 Xray/Reality 入站），并可选附带一个
**NAT 出口代理**（到境外 VPS 的 SSH SOCKS 隧道 + 本地 HTTP 代理）。

- **xui 面板**：Docker Compose 部署 3x-ui；面板默认只绑 `127.0.0.1`（不公开暴露，经
  SSH 隧道访问），可选自带 Cloudflare 隧道实现域名访问。
- **NAT 出口代理（可选）**：当本机所在地区被某些境外服务封锁时，提供一个走境外 VPS
  出口的本地 HTTP 代理 `127.0.0.1:7890`，供本机其他服务按需使用。

> 本项目只管网络侧，自成一体，与服务器上其他项目互不相关。

## 前置要求

- 一台 Linux 服务器，有 `root` 权限。
- 已安装 **Docker** 与 **Docker Compose v2**（`docker compose version` 能正常输出）。
  本项目不负责安装 Docker。

## 部署 xui 面板

> 以下命令都在你的 **Linux 服务器**上执行（直接在本机，或通过 SSH 登录的远程服务器皆可）。

### 1. 获取项目

在服务器上克隆本仓库并进入目录：

```bash
git clone https://github.com/Fateorcloud/xui-net.git
cd xui-net
```

### 2. 准备配置

```bash
cp .env.example .env
nano .env
```

至少修改这几项（其余可用默认值）：

| 变量 | 说明 |
|---|---|
| `XUI_ADMIN_USERNAME` | 面板管理员用户名（**必须改**，不能留 `CHANGE_ME_*`） |
| `XUI_ADMIN_PASSWORD` | 面板管理员密码（**必须改**） |
| `XUI_PANEL_PORT` | 面板端口，默认 `12053`（仅绑本机回环） |
| `XUI_REALITY_PORT` | Reality 入站端口，默认 `31444`（需在防火墙/安全组放行） |

### 3. 安装

```bash
sudo bash deploy.sh xui --yes
```

脚本会：把模板渲染进 `/opt/xui` → `docker compose up -d` 启动容器 → 等面板就绪 →
写入你设的管理员账号与端口 → 重启面板。数据持久化在 `/opt/xui/db`、`/opt/xui/cert`。

### 4. 访问面板

面板只绑在 `127.0.0.1:<XUI_PANEL_PORT>`（仅本机回环，不对公网开放）。按你的情况二选一：

- **服务器本机就有桌面浏览器**：直接打开 `http://localhost:12053`。
- **远程 / 无桌面的服务器**：在你能开浏览器的电脑上建一条 SSH 隧道，把服务器的面板
  端口映射到本地：

  ```bash
  ssh -L 12053:127.0.0.1:12053 用户@服务器地址
  ```

  保持该窗口，再用浏览器打开 `http://localhost:12053`。

登录用 `.env` 里设的账号密码，随后在面板内**手动配置 Reality 入站**。

> 想用域名（如 `xui.example.com`）访问面板、并加一层验证？见
> [docs/network-components.md](docs/network-components.md) 的「自带 Cloudflare 隧道」。

## 部署 NAT 出口代理（可选）

仅当你需要"让本机部分流量从境外 VPS 出口"时才需要。在 `.env` 设
`ENABLE_NAT_PROXY=true` 并填好 `NAT_SSH_*`（境外 VPS 的主机/端口/用户/密钥），然后：

```bash
sudo bash deploy.sh nat-proxy --yes
```

装好后本地 HTTP 代理在 `127.0.0.1:7890`。消费方在各自项目里设
`HTTP_PROXY=http://127.0.0.1:7890` 即可使用。详见
[docs/network-components.md](docs/network-components.md)。

## 命令一览

| 命令 | 作用 |
|---|---|
| `sudo bash deploy.sh xui --yes` | 安装或修复 xui 面板 |
| `sudo bash deploy.sh nat-proxy --yes` | 安装或修复 NAT 出口代理 |
| `sudo bash deploy.sh network --yes` | 依次执行以上两者 |

命令是幂等的：重复执行用于修复/更新，挂载卷里的数据（面板库、证书）不会丢失。

## 边界与安全

- 本项目只部署 xui 及可选的 NAT 出口代理，不涉及任何其他应用栈（数据库、缓存、
  对象存储、搜索、AI 平台等）。
- 面板默认不公开；如需公开，请配合反向代理/隧道并加访问验证。
- 请将真实的 `.env`、SSH 密钥、xui 数据库与生成的证书排除在 Git 之外
  （`.gitignore` 已涵盖）。
