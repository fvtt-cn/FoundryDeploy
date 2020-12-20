#!/bin/bash

# FoundryVTT 安装脚本默认参数

SCRIPT_VERSION="1.3.2"

# 容器名
fvttname="fvtt"
caddyname="caddy"
fbname="filebr"
dashname="portainer"

# 网桥/挂载名
bridge="caddy_network"
fvttvolume="fvtt_data"
fvttapp="fvtt_appv"
caddyvolume="caddy_data"
dashvolume="portainer_data"

# 端口号（无域名使用）
fvttport="30000"
fbport="30001"
dashport="30002"

# 杂项，此处直接使用 PWD 有一定风险
config="$PWD/fvtt-config"
caddyfile="$PWD/Caddyfile"  # Caddy 配置
fbdatabase="$PWD/filebrowser.db" # FileBrowser 数据库
caddycpu=256 # Caddy CPU 使用百分比
fvttcpu=1024 # FoundryVTT CPU 使用百分比
fbcpu=256 # FileBrowser CPU 使用百分比
fbmemory="512M" # FileBrowser 内存使用上限，超过则 OOM Kill 重启容器
publicip=$(curl -s http://icanhazip.com) # 获取外网 IP 地址，不一定成功
dockersocket="/var/run/docker.sock"

# 以下为 cecho, credit to Tux
# ---------------------
cecho() {
    declare -A colors;
    colors=(\
        ['black']='\E[0;47m'\
        ['red']='\E[0;31m'\
        ['green']='\E[0;32m'\
        ['yellow']='\E[0;33m'\
        ['blue']='\E[0;34m'\
        ['magenta']='\E[0;35m'\
        ['cyan']='\E[0;36m'\
        ['white']='\E[0;37m'\
    );
 
    local defaultMSG="无";
    local defaultColor="black";
    local defaultNewLine=true;

    while [[ $# -gt 1 ]];
    do
    key="$1";
 
    case $key in
        -c|--color)
            color="$2";
            shift;
        ;;
        -n|--noline)
            local newLine=false;
        ;;
        *)
            # unknown option
        ;;
    esac
    shift;
    done
 
    message=${1:-$defaultMSG};   # Defaults to default message.
    color=${color:-$defaultColor};   # Defaults to default color, if not specified.
    newLine=${newLine:-$defaultNewLine};
 
    echo -en "${colors[$color]}";
    echo -en "$message";
    if [ "$newLine" = true ] ; then
        echo;
    fi
    tput sgr0 || :; #  Reset text attributes to normal without clearing screen.
 
    return;
}

warning() {
    cecho -c 'yellow' "$@";
}
 
error() {
    cecho -c 'red' "$@";
}
 
information() {
    cecho -c 'blue' "$@";
}

success() {
    cecho -c 'green' "$@";
}

echoLine() {
    cecho -c 'cyan' "========================"
}
# ---------------------

# 获取发行版名称，credit to docker
get_distribution() {
    lsb_dist=""
    # Every system that we officially support has /etc/os-release
    if [ -r /etc/os-release ]; then
        lsb_dist="$(. /etc/os-release && echo "$ID")"
    fi
    # Returning an empty string here should be alright since the
    # case statements don't act unless you provide an actual value
    echo "$lsb_dist"
}
# ---------------------

# FoundryVTT 容器化自动安装脚本
# By hmqgg (https://github.com/hmqgg)

cecho -c 'magenta' "FoundryVTT 容器化自动安装脚本 Ver.${SCRIPT_VERSION}"
cecho -c 'magenta' "By hmqgg (https://github.com/hmqgg)"
echoLine

# 检查 Root 权限
[ "$EUID" -ne 0 ] && error "错误：请使用 root 账户或 sudo 命令执行脚本" && exit 1

# 安装（默认步骤），或重建
if test -z "$@" || test "$@" == "recreate"; then

# 第一步，检查 Docker 安装
if [ -x "$(command -v docker)" ]; then
    information "Docker 已安装"
else
    warning "Docker 未安装，安装中..."
    curl -fsSL https://get.docker.com | sh -s -- --mirror Aliyun
    
    # CentOS 安装后启动 Docker 服务
    lsb_dist=$( get_distribution )
    lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

    case "$lsb_dist" in

        centos|rhel)
            echo "CentOS/RHEL，尝试启用并启动 Docker 服务"
            systemctl enable docker
            systemctl start docker
		;;
        
        *)
            # 非 CentOS/RHEL
            echo "非 CentOS/RHEL，服务已经启动"
        ;;

    esac
fi

# 安装后，仍需检查
[ ! -x "$(command -v docker)" ] && exit $?

# 确认 Docker 是否能启动容器，以 hello-world 镜像尝试
if ! docker run --rm hello-world; then
    error "错误：Docker 无法启动容器，请联系脚本作者"
    exit 2
fi

information "运行环境检查完毕无误"
echoLine

# 第二步，输入可配置参数
# 密码回显，方便初学者

useConfig="n"
# 如果配置文件存在，是否读取存储的配置
if [ -f "$config" ]; then
    read -p "是否直接使用已存储的上次部署使用的配置（FVTT 用户名、密码、域名、Web 文件管理器等；默认使用）[Y/n]：" useConfig
fi

if [ "$useConfig" != "n" -a "$useConfig" != "N" ]; then
    # 使用配置文件
    source $config
    ## 但仍然读取版本配置号
    [ -z "$username" -o -z "$password" ] && warning "配置文件未存储有效的 FVTT 的账号密码。输入版本号时，必须使用直链下载地址！！！" 
    read -p "请输入要安装的 FoundryVTT 的版本号，或 Linux 直链下载地址(http/https开头)【例：0.7.5】（可选。若无，直接回车，默认使用最新稳定版）：" version

    while [ -z "$username" -o -z "$password" ] && [[ $version != http* ]]; do
        warning "配置文件未存储有效的 FVTT 的账号密码。输入版本号时，必须使用直链下载地址！！！" 
        read -p "请输入要安装的 FoundryVTT 的 Linux 直链下载地址(http/https开头)：" version
    done
else
    warning "请输入以下参数，用于获取 FoundryVTT 下载链接及授权，并配置服务器（参数将会存储在 ${config} 下以便后续更新）"

    read -p "请输入已购买的 FoundryVTT 账号（可选。若无，直接回车，为空时版本号必须输入直链下载地址）：" username && [ -z "$username" ] || read -p "请输入该账号的密码：" password
    echoLine

    # 可选参数
    [ -z "$username" -o -z "$password" ] && warning "未输入有效的 FVTT 的账号密码。输入版本号时，必须使用直链下载地址！！！" 
    read -p "请输入要安装的 FoundryVTT 的版本号，或 Linux 直链下载地址(http/https开头)【例：0.7.5】（可选。若无，直接回车，默认使用最新稳定版）：" version

    while [ -z "$username" -o -z "$password" ] && [[ $version != http* ]]; do
        warning "未输入有效的 FVTT 的账号密码。输入版本号时，必须使用直链下载地址！！！（如果需要使用账号密码来配置，请按 Ctrl+C 并重新开始安装）" 
        read -p "请输入要安装的 FoundryVTT 的 Linux 直链下载地址(http/https开头)：" version
    done

    read -p "请输入自定义的 FoundryVTT 的管理密码（可选。若无，直接回车）：" adminpass
    read -p "请输入 FoundryVTT 将会使用的已绑定该服务器的域名（可选，需要绑定该服务器。若无，直接回车）：" domain
    read -p "请输入 FoundryVTT 使用 CDN 时的加速域名（可选，不能绑定该服务器。若无，直接回车）：" cdndomain
    read -p "请输入 GitHub 转发 Host 的 IP（可选。默认关闭。若无，直接回车）：" githost
    read -p "是否使用 Web 文件管理器来管理 FoundryVTT 的文件?（可选。推荐使用，默认开启）[Y/n]：" fbyn
    [ "$fbyn" != "n" -a "$fbyn" != "N" ] && read -p "请输入 Web 文件管理器将会使用的已绑定该服务器的域名（可选。若无，直接回车）：" fbdomain
    read -p "是否使用 Docker 网页仪表盘来管理服务器？（可选。默认关闭）[y/N]：" dashyn
    [ "$dashyn" == "y" -o "$dashyn" == "Y" ] && read -p "请输入 Docker 网页仪表盘将会使用的已绑定该服务器的域名（可选。若无，直接回车）：" dashdomain
fi

echoLine
warning "请确认以下所有参数是否输入正确！！！"
information -n "FVTT 账号：" && cecho -c 'cyan' $username
information -n "FVTT 密码：" && cecho -c 'cyan' $password
[ -n "$version" ] && ([[ $version == http* ]] && information -n "FVTT 下载地址：" || information -n "FVTT 安装版本：" && cecho -c 'cyan' $version)
[ -n "$adminpass" ] && information -n "FVTT 管理密码：" && cecho -c 'cyan' $adminpass
[ -n "$domain" ] && information -n "FVTT 域名：" && cecho -c 'cyan' $domain
[ -n "$cdndomain" ] && information -n "FVTT 加速域名：" && cecho -c 'cyan' $cdndomain
[ -n "$githost" ] && information -n "GitHub 转发 Host IP：" && cecho -c 'cyan' $githost
information -n "Web 文件管理器：" && [ "$fbyn" != "n" -a "$fbyn" != "N" ] && cecho -c 'cyan' "启用" || cecho -c 'cyan' "禁用"
[ -n "$fbdomain" ] && information -n "Web 文件管理器域名：" && cecho -c 'cyan' $fbdomain
information -n "Docker 仪表盘：" && [ "$dashyn" == "y" -o "$dashyn" == "Y" ] && cecho -c 'cyan' "启用" || cecho -c 'cyan' "禁用"
[ -n "$dashdomain" ] && information -n "Docker 仪表盘域名：" && cecho -c 'cyan' $dashdomain

# 检查端口占用
if test "$domain" || test "$fbdomain"; then
    # 使用域名，检查 80/443
    (echo >/dev/tcp/localhost/80) &>/dev/null && { error "80 端口被占用，无法使用域名部署" ; exit 2 ; } || information "80 端口未占用，可部署 HTTP"
    (echo >/dev/tcp/localhost/443) &>/dev/null && { error "443 端口被占用，无法使用域名部署" ; exit 2 ; } || information "443 端口未占用，可部署 HTTPS"
fi
if [ -z "$domain" ]; then
    # 检查 30000
    (echo >/dev/tcp/localhost/$fvttport) &>/dev/null && { error "${fvttport} 端口被占用，无法部署" ; exit 2 ; } || information "${fvttport} 端口未占用，可部署"
fi
if [ "$fbyn" != "n" -a "$fbyn" != "N" -a -z "$fbdomain" ]; then
    # 检查 30001
    (echo >/dev/tcp/localhost/$fbport) &>/dev/null && { error "${fbport} 端口被占用，无法部署" ; exit 2 ; } || information "${fbport} 端口未占用，可部署"
fi
if [ -z "$dashdomain" -a "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    # 检查 30002
    (echo >/dev/tcp/localhost/$dashport) &>/dev/null && { error "${dashport} 端口被占用，无法部署" ; exit 2 ; } || information "${dashport} 端口未占用，可部署"
fi

read -s -p "按下回车确认参数正确，否则按下 Ctrl+C 退出"
echo
echoLine

# 写入参数配置以便后续使用
cat <<EOF >$config
username="${username}"
password="${password}"
adminpass="${adminpass}"
domain="${domain}"
fbyn="${fbyn}"
fbdomain="${fbdomain}"
cdndomain="${cdndomain}"
dashyn="${dashyn}"
dashdomain="${dashdomain}"
githost="${githost}"
EOF

# 第三步，拉取镜像
information "拉取需要使用到的镜像（境内服务器可能较慢，耐心等待）"

docker pull felddy/foundryvtt:release && docker image inspect felddy/foundryvtt:release >/dev/null 2>&1 && success "拉取 FoundryVTT 成功" || { error "错误：拉取 FoundryVTT 失败" ; exit 3 ; }
docker pull caddy && docker image inspect caddy >/dev/null 2>&1 && success "拉取 Caddy 成功" || { error "错误：拉取 Caddy 失败" ; exit 3 ; }
if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
    docker pull filebrowser/filebrowser:alpine && docker image inspect filebrowser/filebrowser:alpine >/dev/null 2>&1 && success "拉取 FileBrowser 成功" || { error "错误：拉取 FileBrowser 失败" ; exit 3 ; }
fi
if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    docker pull portainer/portainer-ce && docker image inspect portainer/portainer-ce >/dev/null 2>&1 && success "拉取 Portainer 成功" || { error "错误：拉取 Portainer 失败" ; exit 3 ; }
fi

# 第四步，开始部署
# 创建网桥和挂载
docker network create $bridge || warning "错误：创建网桥 ${bridge} 失败。通常是因为已经创建，如果正在升级，请无视该警告"

docker volume create $fvttvolume || warning "警告：创建挂载 ${fvttvolume} 失败。通常是因为已经创建，如果正在升级，请无视该警告"
docker volume create $fvttapp || warning "警告：创建挂载 ${fvttapp} 失败。通常是因为已经创建，如果正在升级，请无视该警告"
docker volume create $caddyvolume || warning "警告：创建挂载 ${caddyvolume} 失败。通常是因为已经创建，如果正在升级，请无视该警告"
[ "$dashyn" == "y" -o "$dashyn" == "Y" ] && { docker volume create $dashvolume || warning "警告：创建挂载 ${dashvolume} 失败。通常是因为已经创建，如果正在升级，请无视该警告"; }

# 检查是否有同名容器
docker container inspect $fvttname >/dev/null 2>&1 && error "错误：FoundryVTT 已经启动过，请升级而非安装" && exit 5
docker container inspect $caddyname >/dev/null 2>&1 && error "错误：Caddy 已经启动过，请升级而非安装" && exit 5
[ "$fbyn" != "n" -a "$fbyn" != "N" ] && docker container inspect $fbname >/dev/null 2>&1 && error "错误：FileBrowser 已经启动过，请升级而非安装" && exit 5
[ "$dashyn" == "y" -o "$dashyn" == "Y" ] && docker container inspect $dashname >/dev/null 2>&1 && error "错误：Portainer 已经启动过，请升级而非安装" && exit 5

success "网桥、挂载创建成功，且无同名容器"
echoLine

# 如果不使用存储配置，重写 Caddy 配置
if [ "$useConfig" == "n" -o "$useConfig" == "N" ]; then
    if [ -n "$domain" ]; then
        # 有 Caddy 域名
cat <<EOF >$caddyfile
$domain {
    reverse_proxy ${fvttname}:30000
    encode zstd gzip
}

EOF
    else
        # 无 Caddy 域名
cat <<EOF >$caddyfile
:${fvttport} {
    reverse_proxy ${fvttname}:30000
    encode zstd gzip
}

EOF
    fi

    # FileBrowser
    if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
        if [ -n "$fbdomain" ]; then
        # 有 FB 域名
cat <<EOF >>$caddyfile
$fbdomain {
    reverse_proxy ${fbname}:80
    encode zstd gzip
}

EOF
        else
        # 无 FB 域名
cat <<EOF >>$caddyfile
:${fbport} {
    reverse_proxy ${fbname}:80
    encode zstd gzip
}

EOF
        fi
    fi

    if [ -n "$cdndomain" ]; then
    # CDN 域名，默认直接在 80 端口上 HOST HTTP。对境内服务器，应无备案问题，不然也用不了 CDN
cat <<EOF >>$caddyfile
http://${cdndomain} {
    reverse_proxy ${fvttname}:30000 {
        header_down Cache-Control "max-age=0" "max-age=0, s-maxage=31536000"
    }
    encode zstd gzip
}

EOF
    fi

    if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
        if [ -n "$dashdomain" ]; then
        # 有 Portainer 域名
cat <<EOF >>$caddyfile
$dashdomain {
    reverse_proxy ${dashname}:9000
    encode zstd gzip
}

EOF
        else
        # 无 Portainer 域名
cat <<EOF >>$caddyfile
:${dashport} {
    reverse_proxy ${dashname}:9000
    encode zstd gzip
}

EOF
        fi
    fi
fi

cat $caddyfile 2>/dev/null && success "Caddy 配置成功" || { error "错误：无法读取 Caddy 配置文件" ; exit 6 ; }
echoLine

# 启动容器
# Caddy，映射 UDP 端口，方便启用 HTTP/3
caddyrun="docker run -d --name=${caddyname} --restart=unless-stopped --network=${bridge} -c=${caddycpu} -v ${caddyvolume}:/data -v ${caddyfile}:/etc/caddy/Caddyfile -p ${fvttport}:${fvttport} -p ${fvttport}:${fvttport}/udp -p ${fbport}:${fbport} -p ${fbport}:${fbport}/udp "
[ -n "$domain" -o -n "$fbdomain" ] && caddyrun="${caddyrun}-p 80:80 -p 80:80/udp -p 443:443 -p 443:443/udp "
caddyrun="${caddyrun} caddy"
eval $caddyrun && docker container inspect $caddyname >/dev/null 2>&1 && success "Caddy 容器启动成功" || { error "错误：Caddy 容器启动失败" ; exit 7 ; }

# FVTT，使用 root:root 运行避免文件权限问题
fvttrun="docker run -d --name=${fvttname} --restart=unless-stopped --network=${bridge} -c=${fvttcpu} "
fvttrun="${fvttrun}-e FOUNDRY_UID='root' -e FOUNDRY_GID='root' -e CONTAINER_PRESERVE_CONFIG='true' "
fvttrun="${fvttrun}-v ${fvttvolume}:/data -v ${fvttapp}:/home/foundry/resources/app "
# 默认 Minify 静态 CSS/JS 文件
fvttrun="${fvttrun}-e FOUNDRY_MINIFY_STATIC_FILES='true' "

# 账号密码 / 直链下载地址
[ -n "$username" -a -n "$password" ] && fvttrun="${fvttrun}-e FOUNDRY_USERNAME='${username}' -e FOUNDRY_PASSWORD='${password}' "
[ -n "$version" ] && { [[ $version == http* ]] && fvttrun="${fvttrun}-e FOUNDRY_RELEASE_URL='${version}' " || fvttrun="${fvttrun}-e FOUNDRY_VERSION='${version}' "; }
[ -n "$githost" ] && fvttrun="${fvttrun}--add-host=github.com:${githost} --add-host=raw.githubusercontent.com:${githost} -e NODE_TLS_REJECT_UNAUTHORIZED=0 "
[ -n "$adminpass" ] && fvttrun="${fvttrun}-e FOUNDRY_ADMIN_KEY='${adminpass}' "
[ -n "$domain" ] && fvttrun="${fvttrun}-e FOUNDRY_HOSTNAME='${domain}' -e FOUNDRY_PROXY_SSL='true' -e FOUNDRY_PROXY_PORT='443' "
[ -z "$domain" ] && fvttrun="${fvttrun}-e FOUNDRY_PROXY_PORT='${fvttport}' "
fvttrun="${fvttrun} felddy/foundryvtt:release"
eval $fvttrun && docker container inspect $fvttname >/dev/null 2>&1 && success "FoundryVTT 容器启动成功" || { error "错误：FoundryVTT 容器启动失败" ; exit 7 ; }

# FileBrowser
if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
    # 如果没有数据库文件，创建一个
    [ ! -f $fbdatabase ] && truncate -s 0 $fbdatabase
    # 写死 fvttapp 映射路径为 /srv/APP
    fbrun="docker run -d --name=${fbname} --restart=unless-stopped --network=${bridge} -c=${fbcpu} -m=${fbmemory} -v ${fvttvolume}:/srv -v ${fvttapp}:/srv/APP -v ${fbdatabase}:/database.db filebrowser/filebrowser:alpine"
    eval $fbrun && docker container inspect $fbname >/dev/null 2>&1 && success "FileBrowser 容器启动成功" || { error "FileBrowser 容器启动失败" ; exit 7 ; }
fi

# Portainer
if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    dashrun="docker run -d --name=${dashname} --restart=unless-stopped --network=${bridge} -v ${dashvolume}:/data -v ${dockersocket}:/var/run/docker.sock portainer/portainer-ce"
    eval $dashrun && docker container inspect $dashname >/dev/null 2>&1 && success "Portainer 容器启动成功" || { error "Portainer 容器启动失败" ; exit 7 ; }
fi

echoLine

# 成功，列出访问方式
success "FoundryVTT 已成功部署！服务器设定如下："
echoLine
information -n "FoundryVTT 访问地址： " && [ -n "$domain" ] && cecho -c 'cyan' $domain || cecho -c 'cyan' "${publicip}:${fvttport}"
[ -n "$cdndomain" ] && information -n "FoundryVTT 加速访问地址： " && cecho -c 'cyan' $cdndomain
[ -n "$adminpass" ] && information -n "FVTT 管理密码：" && cecho -c 'cyan' $adminpass
if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
    information -n "Web 文件管理器访问地址： " && [ -n "$fbdomain" ] && cecho -c 'cyan' $fbdomain || cecho -c 'cyan' "${publicip}:${fbport}"
    cecho -c 'cyan' "Web 文件管理器下 APP 目录为 Foundry VTT 程序所在目录"
    # Web 文件管理器的用户名/密码可能在数据库里被修改
    [ -z "$@" ] && information -n "Web 文件管理器用户名/密码： " && cecho -c 'cyan' "admin/admin （建议登录后修改）"
fi
if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    information -n "Docker 仪表盘访问地址： " && [ -n "$dashdomain" ] && cecho -c 'cyan' $dashdomain || cecho -c 'cyan' "${publicip}:${dashport}"
    [ -z "$@" ] && cecho -c 'cyan' "Docker 仪表盘在第一次运行时需要设置密码"
fi
echoLine
fi

recreate() {
    # 空，进安装流程
    :
}

remove() {
    error -n "警告！！！使用该命令将删除所有容器和网桥，但是存档、文件等数据将保留，不过仍可能导致意外后果！" && read -p "[y/N]：" rmyn
    if [ "$rmyn" == "y" -o "$rmyn" == "Y" ]; then
        warning "删除中...（等待3秒，按下 Ctrl+C 立即中止）"
        sleep 3

        # 移除容器
        docker rm -f $fvttname
        docker rm -f $caddyname
        docker rm -f $fbname
        docker rm -f $dashname

        # 移除网桥
        docker network rm $bridge

        # 清理 Docker 多余镜像
        docker image prune -f

        success "删除完毕！（如果输出错误一般是网桥未成功删除，升级时可以忽略）"
    fi
}

restart() {
    error -n "警告！！！使用该命令将重启所有容器，可能导致意外后果！" && read -p "[y/N]：" restartyn
    if [ "$restartyn" == "y" -o "$restartyn" == "Y" ]; then
        warning "重启中...（等待3秒，按下 Ctrl+C 立即中止）"
        sleep 3

        docker restart $fvttname
        docker restart $caddyname
        docker restart $fbname
        docker restart $dashname

        success "重启完毕！"
    fi
}

clear() {
    error -n "警告！！！使用该命令将清除所有内容，包括 Caddy、 FVTT 所有游戏、存档、文件！" && read -p "[y/N]：" cleanyn && [ "$cleanyn" == "y" -o "$cleanyn" == "Y" ] && \
     error -n "再次警告！！！使用该命令将清除所有内容，包括 Caddy、 FVTT 所有游戏、存档、文件！" && read -p "[y/N]：" cleanyn
    if [ "$cleanyn" == "y" -o "$cleanyn" == "Y" ]; then
        warning "清除中...（等待3s，按下 Ctrl+C 立即中止）"
        sleep 3

        # 移除容器
        docker rm -f $fvttname
        docker rm -f $caddyname
        docker rm -f $fbname
        docker rm -f $dashname

        # 移除网桥、挂载
        docker network rm $bridge
        docker volume rm $caddyvolume $fvttvolume $fvttapp $dashvolume

        # 删除创建的文件
        rm $caddyfile $fbdatabase $config

        # 清理 Docker 多余镜像
        docker image prune -f

        success "清除完毕！"
    fi
}

"$@"

echo
