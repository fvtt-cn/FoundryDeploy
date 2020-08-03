# FoundryDeploy
FoundryVTT 部署脚本

<img src="/fvtt-docker-script.png" width="200">

# 前置要求
- [x] 一台 Linux 服务器
- [ ] 服务器绑定域名（可选）


# 使用方法

## 下载脚本
首先，如果还没有下载脚本，则下载：
```bash
wget https://gitee.com/mitchx7/FoundryDeploy/raw/master/fvtt.sh
sudo chmod +x fvtt.sh
```

## 安装
直接运行脚本即可安装：
```bash
sudo ./fvtt.sh
```

## 重启
如果需要重启容器，请运行以下命令：
```bash
sudo ./fvtt.sh restart
```

## 升级
如果要升级 FoundryVTT 版本，请运行以下命令：
```bash
sudo ./fvtt.sh remove
```
删除容器后，再运行（此处最好指定版本号）：
```bash
sudo ./fvtt.sh recreate
```

## 清除
如果需要清除已部署的 FoundryVTT、Caddy、FileBrowser，请运行以下命令 **（使用该命令将清除所有内容，包括 Caddy、 FVTT 所有游戏、存档、文件！）**：
```bash
sudo ./fvtt.sh clear
```

# FAQ

> Q: 为什么显示安装成功后，仍然无法连接 FoundryVTT?
>
> A: 检查服务器防火墙设置。如果购买的是云服务，可以在网页控制台上检查对应端口是否开启。

> Q: 为什么不使用 Docker-Compose?
> 
> A: 避免进行更多安装步骤，国内服务器太难了。
