# xui/NAT 网络部署

本项目部署一套独立的 xui 网络侧组件栈，以及一个可选的 NAT 出口代理。它与
LobeHub AI 平台项目刻意保持分离。

## 边界

| 组件 | 命令 | 作用 |
|---|---|---|
| xui | `sudo bash deploy.sh xui --yes` | 可选的 Reality/Xray 网络侧组件栈 |
| NAT 代理 | `sudo bash deploy.sh nat-proxy --yes` | 可选的 SSH SOCKS 隧道及本地 HTTP 代理 |
| 组合安装 | `sudo bash deploy.sh network --yes` | 依次执行 xui 和 NAT 安装 |

请将本项目部署到独立的服务器目录，例如 `/opt/xui`。不要把它的 `.env`、
compose 文件或 service 单元混入 `/opt/lobehub`。

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

## 安全须知

- 如果 `NAT_SSH_HOST` 属于私有信息，请勿提交。
- 请勿提交 SSH 密钥或 known-hosts 文件。
- 未经过深思熟虑的访问策略，请勿将 xui 面板公开暴露。
- NAT HTTP 代理监听 `127.0.0.1:7890`，仅供本地出站流量使用。
