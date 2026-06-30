#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vless2mihomo —— 把 VLESS 分享链接转换为 mihomo (Clash.Meta) 代理 YAML。

用法：
  python3 scripts/vless2mihomo.py 'vless://...'                 # 单个 -> proxies 片段
  python3 scripts/vless2mihomo.py 'vless://A' 'vless://B'        # 多个
  cat links.txt | python3 scripts/vless2mihomo.py               # 从 stdin（每行一个）
  python3 scripts/vless2mihomo.py --full 'vless://...'          # 输出含分流规则的完整配置
  python3 scripts/vless2mihomo.py --full -o clash.yaml 'vless://...'   # 写入文件

支持 security: reality / tls / 无加密；transport: tcp / ws / grpc。
flow 为空则不输出（与 3x-ui 空 flow 的 Reality 入站匹配）。仅用 Python 标准库，无依赖。
"""
import argparse
import sys
import urllib.parse as up

# --full 模式下，这些境外 AI 域名强制走代理（其余按 GEOIP 国内直连/海外代理）
AI_SUFFIXES = [
    "openai.com", "chatgpt.com", "oaiusercontent.com",
    "anthropic.com", "claude.ai",
    "gemini.google.com", "generativelanguage.googleapis.com", "aistudio.google.com",
    "perplexity.ai", "x.ai", "grok.com",
]


def parse_vless(link):
    """vless://uuid@server:port?query#name -> (uuid, server, port, query_dict, name)"""
    link = link.strip()
    if not link.startswith("vless://"):
        raise ValueError("不是 vless 链接")
    u = up.urlparse(link)
    uuid = up.unquote(u.username or "")
    server = u.hostname or ""
    port = u.port or 443
    q = {k: v[-1] for k, v in up.parse_qs(u.query).items()}
    name = up.unquote(u.fragment) if u.fragment else "%s:%s" % (server, port)
    if not uuid or not server:
        raise ValueError("链接缺少 uuid 或 server")
    return uuid, server, port, q, name


def to_proxy(link):
    """把一条 vless 链接转成 mihomo 代理 dict。"""
    uuid, server, port, q, name = parse_vless(link)
    net = q.get("type", "tcp")
    sec = q.get("security", "none")
    p = {
        "name": name,
        "type": "vless",
        "server": server,
        "port": port,
        "uuid": uuid,
        "network": net,
        "udp": True,
    }
    if q.get("flow"):
        p["flow"] = q["flow"]

    if sec == "reality":
        p["tls"] = True
        p["servername"] = q.get("sni", q.get("peer", ""))
        p["client-fingerprint"] = q.get("fp", "chrome")
        ro = {}
        if q.get("pbk"):
            ro["public-key"] = q["pbk"]
        if q.get("sid"):
            ro["short-id"] = q["sid"]
        p["reality-opts"] = ro
    elif sec in ("tls", "xtls"):
        p["tls"] = True
        if q.get("sni"):
            p["servername"] = q["sni"]
        if q.get("fp"):
            p["client-fingerprint"] = q["fp"]
        if q.get("alpn"):
            p["alpn"] = up.unquote(q["alpn"]).split(",")

    if net == "ws":
        ws = {}
        if q.get("path"):
            ws["path"] = up.unquote(q["path"])
        if q.get("host"):
            ws["headers"] = {"Host": q["host"]}
        if ws:
            p["ws-opts"] = ws
    elif net == "grpc":
        if q.get("serviceName"):
            p["grpc-opts"] = {"grpc-service-name": up.unquote(q["serviceName"])}
    return p


def _scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "null"
    s = str(v)
    needs_quote = (
        s == "" or s != s.strip()
        or ": " in s or s.endswith(":") or " #" in s
        or s[0] in "!&*?|>%@`\"'#,[]{}-"
    )
    if needs_quote:
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return s


def _emit(obj, indent=0):
    """极简 YAML 序列化（够用于本脚本的 dict/list/标量结构）。"""
    pad = "  " * indent
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, (dict, list)) and v:
                out.append("%s%s:" % (pad, k))
                out += _emit(v, indent + 1)
            elif isinstance(v, (dict, list)):
                out.append("%s%s: %s" % (pad, k, "{}" if isinstance(v, dict) else "[]"))
            else:
                out.append("%s%s: %s" % (pad, k, _scalar(v)))
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                sub = _emit(item, indent + 1)
                out.append("%s- %s" % (pad, sub[0].lstrip()))
                out += sub[1:]
            else:
                out.append("%s- %s" % (pad, _scalar(item)))
    return out


def proxies_yaml(proxies):
    return "\n".join(_emit({"proxies": proxies}))


def full_yaml(proxies):
    names = [p["name"] for p in proxies]
    cfg = {
        "mixed-port": 7890,
        "allow-lan": False,
        "mode": "rule",
        "log-level": "info",
        "ipv6": False,
        "dns": {
            "enable": True,
            "listen": "127.0.0.1:1053",
            "ipv6": False,
            "enhanced-mode": "fake-ip",
            "fake-ip-range": "198.18.0.1/16",
            "nameserver": ["223.5.5.5", "119.29.29.29"],
            "fallback": ["1.1.1.1", "8.8.8.8"],
        },
        "proxies": proxies,
        "proxy-groups": [
            {"name": "PROXY", "type": "select", "proxies": names + ["DIRECT"]},
        ],
        "rules": (
            ["GEOIP,LAN,DIRECT,no-resolve"]
            + ["DOMAIN-SUFFIX,%s,PROXY" % d for d in AI_SUFFIXES]
            + ["GEOIP,CN,DIRECT", "MATCH,PROXY"]
        ),
    }
    return "\n".join(_emit(cfg))


def main():
    ap = argparse.ArgumentParser(description="VLESS 链接 -> mihomo YAML")
    ap.add_argument("links", nargs="*", help="vless:// 链接（可多个）；留空则从 stdin 逐行读")
    ap.add_argument("--full", action="store_true",
                    help="输出含分流规则的完整配置（默认只输出 proxies 片段）")
    ap.add_argument("-o", "--output", help="写入文件（默认打印到 stdout）")
    args = ap.parse_args()

    raw = list(args.links) if args.links else sys.stdin.read().splitlines()
    raw = [ln.strip() for ln in raw if ln.strip()]
    if not raw:
        ap.error("没有输入链接（用参数传入，或从 stdin 提供）")

    proxies, errs = [], 0
    for ln in raw:
        try:
            proxies.append(to_proxy(ln))
        except Exception as e:  # noqa: BLE001
            sys.stderr.write("跳过无法解析的链接: %s ... (%s)\n" % (ln[:40], e))
            errs += 1
    if not proxies:
        sys.exit("没有可用的代理，全部解析失败")

    text = (full_yaml(proxies) if args.full else proxies_yaml(proxies)) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(text)
        sys.stderr.write("已写入 %s（%d 个节点%s）\n"
                         % (args.output, len(proxies), "，%d 个失败" % errs if errs else ""))
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
