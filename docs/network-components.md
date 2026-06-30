# xui-net（xui/NAT 网络栈）

本项目部署一套独立的 xui 网络侧组件栈，以及一个可选的 NAT 出口代理。

## 边界

| 组件 | 命令 | 作用 |
|---|---|---|
| xui | `sudo bash deploy.sh xui --yes` | 可选的 Reality/Xray 网络侧组件栈 |
| NAT 代理 | `sudo bash deploy.sh nat-proxy --yes` | 可选的 SSH SOCKS 隧道及本地 HTTP 代理 |
| 组合安装 | `sudo bash deploy.sh network --yes` | 依次执行 xui 和 NAT 安装 |

请将本项目部署到独立的服务器目录，例如 `/opt/xui`。与服务器上其他项目保持
`.env`、compose 文件及 service 单元相互隔离。

## 启用

编辑 `.env`：

```env
ENABLE_XUI=true
XUI_ADMIN_USERNAME=CHANGE_ME_XUI_ADMIN
XUI_ADMIN_PASSWORD=CHANGE_ME_XUI_PASSWORD
XUI_REALITY_PORT=31444

ENABLE_NAT_PROXY=true
NAT_SSH_HOST=<nat-server-hostname>
NAT_SSH_PORT=22
NAT_SSH_USER=root
NAT_SSH_KEY_PATH=/root/.ssh/nat_ed25519
```

执行：

```bash
sudo bash deploy.sh network --yes
```

如果其他本地服务需要使用 NAT 代理，请在该服务的环境变量中设置：

```env
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,.local
```

> 使用 `network_mode: host` 的容器可直接访问宿主机的 `127.0.0.1:7890`，无需任何
> docker 网关绑定或 `host.docker.internal`。

### 选择性路由：只让部分流量走 NAT

`HTTP_PROXY` 会让**所有**出站默认经 NAT 出口，`NO_PROXY` 中列出的域名则**直连**。
典型场景：服务器在受限地区（如香港），某些境外 API（如 OpenAI）从本地直连会被拒，
需要经 NAT 的合规出口；而本地或就近的服务则应直连以降低延迟。把希望直连的域名追加到
`NO_PROXY` 即可：

```env
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
# 逗号分隔；前导点匹配子域。列出的域名直连，其余走 NAT。
NO_PROXY=localhost,127.0.0.1,::1,.local,.example-direct.com
```

> 基于 undici 的 Node 应用（含使用 `EnvHttpProxyAgent` / `global-agent` 的程序）
> 会尊重 `NO_PROXY`；Node 24+ 也可用 `NODE_USE_ENV_PROXY=1` 让内置 `fetch` 读取这些变量。

### 让（桥接网络的）docker 容器使用代理：内网绑定（纵深防御）

`network_mode: host` 的容器能直接用 `127.0.0.1:7890`；但**桥接网络里的容器**（例如本项目
xui 容器内的 xray 分流）不行 —— 容器内的 `127.0.0.1` 指的是它自己，够不到宿主机，只能通过
**docker 网关地址**访问宿主机服务。

做法：把 privoxy 监听地址设成 **回环 + docker 网关** 两个内网地址（空格分隔），并放行对应网段：

```env
# 同时服务宿主机程序(127.0.0.1)与本网络容器(经网关 172.19.0.1)
NAT_HTTP_LISTEN="127.0.0.1:7890 172.19.0.1:7890"
# 放行容器所在 docker 网段（公网因属私有地址本就到不了）
NAT_HTTP_ALLOW_CIDR=172.19.0.0/16
# 固定网段，保证网关 172.19.0.1 不随网络重建而漂移
XUI_NETWORK_SUBNET=172.19.0.0/16
```

`deploy.sh nat-proxy` 会据此为每个地址生成一条 `listen-address`，并为非回环地址加 ufw 放行。

**为什么不用 `0.0.0.0:7890`**：`0.0.0.0` 会连**公网网卡**一起监听，代理是否安全就**全靠防火墙**
这一道 —— ufw 一旦失效/被改就成了公网开放代理。绑内网地址则让代理**根本不在公网监听**，公网
物理上到不了（`172.19.0.1` 不可路由），ufw 只承担"让容器能进"的功能，不再是唯一防线。

> 开机时序：docker 网关 `172.19.0.1` 要等 Docker 建好网络才存在。脚本会安装 privoxy 的
> systemd drop-in（`After=docker.service` + `Restart=on-failure`），若开机早于网络就绪会自动
> 重试，避免 privoxy 起不来。

## 安全须知

- 如果 `NAT_SSH_HOST` 属于私有信息，请勿提交。
- 请勿提交 SSH 密钥或 known-hosts 文件。
- 未经过深思熟虑的访问策略，请勿将 xui 面板公开暴露。
- NAT HTTP 代理默认只监听 `127.0.0.1:7890`（仅本地）。如需供容器使用，按上文绑定**内网地址**
  （回环 + docker 网关），**不要绑 `0.0.0.0`**，以免代理暴露到公网。

## 可选：xui 自带 Cloudflare 隧道（域名访问面板）

xui 面板默认只绑 `127.0.0.1`，需经 SSH 隧道访问。若想用域名访问，可启用 compose 里可选的
`cloudflared` 服务，给 xui 一条**自己的**隧道，与服务器上其他项目的隧道完全独立 ——
符合本项目网络侧自包含的边界。

1. 在 Cloudflare Zero Trust 后台新建一条隧道（例如 `hk1-xui`），复制它的 **token**。
2. 把 token 填入 `.env` 的 `XUI_TUNNEL_TOKEN`，启动连接器：

   ```bash
   docker compose --profile tunnel up -d
   ```

3. 在该隧道下添加路由：`xui.<你的域名>` → 服务类型 `HTTP`、URL `http://xui-3xui:12053`。
   连接器与 xui 容器同处一个 docker 网络，按容器名直达，无需 host 网络或宿主机端口映射。
4. 强烈建议在 Cloudflare Access 给该域名加一层邮箱/SSO 验证；并把面板 `webBasePath`
   改成不易猜的路径，降低被扫描爆破的风险。

