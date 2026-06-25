# Volans xui 网络部署

这是从 LobeHub 部署套件中拆分出来的独立 xui/NAT 部署项目。它只负责网络侧的
组件栈，应当部署到独立的服务器目录，通常为 `/opt/xui`。

LobeHub 项目不依赖本仓库。如果两者部署在同一台服务器上，请保持目录相互独立：

```text
/opt/lobehub  LobeHub AI 平台
/opt/xui      xui 及可选的 NAT 出口代理
```

## 部署

```bash
cp .env.example .env
nano .env
sudo bash deploy.sh xui --yes
```

如需同时安装可选的 NAT 出口代理：

```bash
sudo bash deploy.sh nat-proxy --yes
```

或者一并安装两者：

```bash
sudo bash deploy.sh network --yes
```

## 边界

本项目不会安装 LobeHub、PostgreSQL、Redis、RustFS、SearXNG、NewAPI、
Open WebUI 或任何图床站点。

请将真实的 `.env` 取值、SSH 密钥、xui 数据库以及生成的证书排除在 Git 之外。
