# FoundryDeploy
FoundryVTT 部署脚本

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
