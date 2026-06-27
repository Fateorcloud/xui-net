# Volans xui 网络部署

独立的 xui/NAT 网络部署项目。只负责网络侧组件栈（xui 面板及可选的 NAT 出口代理），
应当部署到独立的服务器目录，通常为 `/opt/xui`。

如果服务器上还运行着其他项目，请与它们保持目录、`.env`、compose 文件与 service
单元相互隔离，互不影响。

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

本项目只部署 xui 及可选的 NAT 出口代理，不涉及任何其他应用栈（数据库、缓存、
对象存储、搜索、AI 平台等）。

请将真实的 `.env` 取值、SSH 密钥、xui 数据库以及生成的证书排除在 Git 之外。
