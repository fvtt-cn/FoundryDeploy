#!/bin/bash

# FoundryVTT 安装脚本默认参数

SCRIPT_VERSION="1.5.0"

# 容器名
fvttname="fvtt"
caddyname="caddy"
fbname="filebr"
dashname="portainer"

optimname="optimimages"

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

# 镜像名
fvttimage="felddy/foundryvtt:release"
caddyimage="library/caddy"
fbimage="filebrowser/filebrowser:alpine"
dashimage="portainer/portainer-ce"

optimimage="varnav/optimize-images"

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

optimempty="optimimages_empty"

# $FORCE_GLO 用于强制全球

# ---------------------
# 以下为 cecho, credit to Tux
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

ecyan() {
    cecho -c 'cyan' "$@"
}

echoLine() {
    ecyan "========================"
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
# 判断是否需要使用 Docker Hub 镜像
can_curl_google() {
    local ret_code=$(curl -s -I --connect-timeout 1 www.google.com -w %{http_code} | tail -n1)
    if [ "$ret_code" -eq "200" ]; then
        echo ""
    else
        echo "docker.mirrors.ustc.edu.cn/"
    fi
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
    installDocker="curl -fsSL https://get.docker.com | sh"
    [ "${FORCE_GLO,,}" = true ] || installDocker="${installDocker} -s -- --mirror Aliyun"
    eval $installDocker

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
[ ! -x "$(command -v docker)" ] && error "错误：安装 Docker 失败，请查看使用教程 FAQ 或联系脚本作者" && exit $?

# 确认 Docker 是否能启动容器，以 hello-world 镜像尝试
if ! docker run --rm hello-world; then
    error "错误：Docker 无法启动容器，请查看使用教程 FAQ 或联系脚本作者"
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
    read -p "是否使用 Web 文件管理器来管理 FoundryVTT 的文件?（可选。推荐使用，默认开启）[Y/n]：" fbyn
    [ "$fbyn" != "n" -a "$fbyn" != "N" ] && read -p "请输入 Web 文件管理器将会使用的已绑定该服务器的域名（可选。若无，直接回车）：" fbdomain
    read -p "是否使用 Docker 网页仪表盘来管理服务器？（可选。默认关闭）[y/N]：" dashyn
    [ "$dashyn" == "y" -o "$dashyn" == "Y" ] && read -p "请输入 Docker 网页仪表盘将会使用的已绑定该服务器的域名（可选。若无，直接回车）：" dashdomain
fi

echoLine
warning "请确认以下所有参数是否输入正确！！！"
information -n "FVTT 账号：" && ecyan $username
information -n "FVTT 密码：" && ecyan $password
[ -n "$version" ] && ([[ $version == http* ]] && information -n "FVTT 下载地址：" || information -n "FVTT 安装版本：" && ecyan $version)
[ -n "$adminpass" ] && information -n "FVTT 管理密码：" && ecyan $adminpass
[ -n "$domain" ] && information -n "FVTT 域名：" && ecyan $domain
[ -n "$cdndomain" ] && information -n "FVTT 加速域名：" && ecyan $cdndomain
information -n "Web 文件管理器：" && [ "$fbyn" != "n" -a "$fbyn" != "N" ] && ecyan "启用" || ecyan "禁用"
[ -n "$fbdomain" ] && information -n "Web 文件管理器域名：" && ecyan $fbdomain
information -n "Docker 仪表盘：" && [ "$dashyn" == "y" -o "$dashyn" == "Y" ] && ecyan "启用" || ecyan "禁用"
[ -n "$dashdomain" ] && information -n "Docker 仪表盘域名：" && ecyan $dashdomain

# 检查端口占用
if test "$domain" || test "$fbdomain"; then
    # 使用域名，检查 80/443
    (echo >/dev/tcp/localhost/80) &>/dev/null && { error "错误：80 端口被占用，无法使用域名部署" ; exit 2 ; } || information "80 端口未占用，可部署 HTTP"
    (echo >/dev/tcp/localhost/443) &>/dev/null && { error "错误：443 端口被占用，无法使用域名部署" ; exit 2 ; } || information "443 端口未占用，可部署 HTTPS"
fi
if [ -z "$domain" ]; then
    # 检查 30000
    (echo >/dev/tcp/localhost/$fvttport) &>/dev/null && { error "错误：${fvttport} 端口被占用，无法部署" ; exit 2 ; } || information "${fvttport} 端口未占用，可部署"
fi
if [ "$fbyn" != "n" -a "$fbyn" != "N" -a -z "$fbdomain" ]; then
    # 检查 30001
    (echo >/dev/tcp/localhost/$fbport) &>/dev/null && { error "错误：${fbport} 端口被占用，无法部署" ; exit 2 ; } || information "${fbport} 端口未占用，可部署"
fi
if [ -z "$dashdomain" -a "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    # 检查 30002
    (echo >/dev/tcp/localhost/$dashport) &>/dev/null && { error "错误：${dashport} 端口被占用，无法部署" ; exit 2 ; } || information "${dashport} 端口未占用，可部署"
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
EOF

# 第三步，拉取镜像
information "拉取需要使用到的镜像（境内服务器可能较慢，耐心等待）"

dockermirror=`can_curl_google`
[ "${FORCE_GLO,,}" = true ] && dockermirror=""

[ -n "$dockermirror" ] && warning "切换为 USTC Docker Hub 镜像源（境内加速）" || warning "使用默认的官方 Docker Hub 源"

docker pull ${dockermirror}${fvttimage} && docker tag ${dockermirror}${fvttimage} ${fvttimage} && docker image inspect ${fvttimage} >/dev/null 2>&1 && success "拉取 FoundryVTT 成功" || { error "错误：拉取 FoundryVTT 失败" ; exit 3 ; }
docker pull ${dockermirror}${caddyimage} && docker tag ${dockermirror}${caddyimage} ${caddyimage} && docker image inspect ${caddyimage} >/dev/null 2>&1 && success "拉取 Caddy 成功" || { error "错误：拉取 Caddy 失败" ; exit 3 ; }
if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
    docker pull ${dockermirror}${fbimage} && docker tag ${dockermirror}${fbimage} ${fbimage} && docker image inspect ${fbimage} >/dev/null 2>&1 && success "拉取 FileBrowser 成功" || { error "错误：拉取 FileBrowser 失败" ; exit 3 ; }
fi
if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    docker pull ${dockermirror}${dashimage} && docker tag ${dockermirror}${dashimage} ${dashimage} && docker image inspect ${dashimage} >/dev/null 2>&1 && success "拉取 Portainer 成功" || { error "错误：拉取 Portainer 失败" ; exit 3 ; }
fi

# 第四步，开始部署
# 创建网桥和挂载
docker network create $bridge || warning "警告：创建网桥 ${bridge} 失败。通常是因为已经创建，如果正在升级，请无视该警告"

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

# 重写 Caddy 配置
if [ -n "`awk '/#FvttCnScriptStart/,/#FvttCnScriptEnd/' ${caddyfile} 2>/dev/null | grep .`" ]; then
    # 删除标记内部分
    sed --in-place '/#FvttCnScriptStart/,/#FvttCnScriptEnd/d' ${caddyfile}
else
    # 强行清空已有 Caddyfile
    if [ -n "`grep "reverse_proxy ${fvttname}:30000" ${caddyfile} 2>/dev/null`" ]; then
        error -n "警告！！！确认是否清除 Caddyfile 所有内容（默认回车清除，否则输入n回车取消安装）" && read -p "[Y/n]：" cfrmyn
        if [ "$cfrmyn" != "n" -a "$cfrmyn" != "N" ]; then
            truncate -s 0 $caddyfile
        else
            error "错误：已放弃修改 Caddyfile。如需部署，请重试并允许清除 Caddyfile"
            exit 6
        fi
    fi
fi

# 写 Caddyfile 标记头部
echo >> caddyfile
echo "#FvttCnScriptStart" >> $caddyfile

# Foundry VTT 反代
[ -n "$domain" ] && echo "${domain} {" >> $caddyfile || echo ":${fvttport} {" >> $caddyfile
cat <<EOF >>$caddyfile
    reverse_proxy ${fvttname}:30000
    encode zstd gzip
}

EOF

# FileBrowser 反代
if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
    [ -n "$fbdomain" ] && echo "${fbdomain} {" >> $caddyfile || echo ":${fbport} {" >> $caddyfile
cat <<EOF >>$caddyfile
    reverse_proxy ${fbname}:80
    encode zstd gzip
}

EOF
fi

# Portainer 反代
if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    [ -n "$dashdomain" ] && echo "${dashdomain} {" >> $caddyfile || echo ":${dashport} {" >> $caddyfile
cat <<EOF >>$caddyfile
    reverse_proxy ${dashname}:9000
    encode zstd gzip
}

EOF
fi

# CDN 域名反代。默认直接在 80 端口上 HOST HTTP。对境内服务器，应无备案问题，不然也用不了 CDN
# 重写 s-maxage 使 CDN 无视 max-age=0 ，仍然缓存
if [ -n "$cdndomain" ]; then
cat <<EOF >>$caddyfile
http://${cdndomain} {
    reverse_proxy ${fvttname}:30000 {
        header_down Cache-Control "max-age=0" "max-age=0, s-maxage=31536000"
    }
    encode zstd gzip
}

EOF
fi

# 写 Caddyfile 标记尾部
echo "#FvttCnScriptEnd" >> $caddyfile

cat $caddyfile 2>/dev/null && success "Caddy 配置成功" || { error "错误：无法读取 Caddy 配置文件" ; exit 6 ; }
echoLine

# 启动容器
# Caddy，映射 UDP 端口，方便启用 HTTP/3
caddyrun="docker run -d --name=${caddyname} --restart=unless-stopped --network=${bridge} -c=${caddycpu} -v ${caddyvolume}:/data -v ${caddyfile}:/etc/caddy/Caddyfile "
caddyrun="${caddyrun}-p ${fvttport}:${fvttport} -p ${fvttport}:${fvttport}/udp -p ${fbport}:${fbport} -p ${fbport}:${fbport}/udp -p ${dashport}:${dashport} -p ${dashport}:${dashport}/udp "
[ -n "$domain" -o -n "$fbdomain" ] && caddyrun="${caddyrun}-p 80:80 -p 80:80/udp -p 443:443 -p 443:443/udp "
caddyrun="${caddyrun} ${caddyimage}"
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
[ -n "$adminpass" ] && fvttrun="${fvttrun}-e FOUNDRY_ADMIN_KEY='${adminpass}' "
[ -n "$domain" ] && fvttrun="${fvttrun}-e FOUNDRY_HOSTNAME='${domain}' -e FOUNDRY_PROXY_SSL='true' -e FOUNDRY_PROXY_PORT='443' "
[ -z "$domain" ] && fvttrun="${fvttrun}-e FOUNDRY_PROXY_PORT='${fvttport}' "
fvttrun="${fvttrun} ${fvttimage}"
eval $fvttrun && docker container inspect $fvttname >/dev/null 2>&1 && success "FoundryVTT 容器启动成功" || { error "错误：FoundryVTT 容器启动失败" ; exit 7 ; }

# FileBrowser
if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
    # 如果没有数据库文件，创建一个
    [ ! -f $fbdatabase ] && truncate -s 0 $fbdatabase
    # 写死 fvttapp 映射路径为 /srv/APP
    fbrun="docker run -d --name=${fbname} --restart=unless-stopped --network=${bridge} -c=${fbcpu} -m=${fbmemory} -v ${fvttvolume}:/srv -v ${fvttapp}:/srv/APP -v ${fbdatabase}:/database.db ${fbimage}"
    eval $fbrun && docker container inspect $fbname >/dev/null 2>&1 && success "FileBrowser 容器启动成功" || { error "FileBrowser 容器启动失败" ; exit 7 ; }
fi

# Portainer
if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    dashrun="docker run -d --name=${dashname} --restart=unless-stopped --network=${bridge} -v ${dashvolume}:/data -v ${dockersocket}:/var/run/docker.sock ${dashimage}"
    eval $dashrun && docker container inspect $dashname >/dev/null 2>&1 && success "Portainer 容器启动成功" || { error "Portainer 容器启动失败" ; exit 7 ; }
fi

echoLine

# 成功，列出访问方式
success "FoundryVTT 已成功部署！服务器设定如下："
echoLine
information -n "FoundryVTT 访问地址： " && [ -n "$domain" ] && ecyan $domain || ecyan "${publicip:-服务器地址}:${fvttport}"
[ -n "$cdndomain" ] && information -n "FoundryVTT 加速访问地址： " && ecyan $cdndomain
[ -n "$adminpass" ] && information -n "FVTT 管理密码：" && ecyan $adminpass
if [ "$fbyn" != "n" -a "$fbyn" != "N" ]; then
    information -n "Web 文件管理器访问地址： " && [ -n "$fbdomain" ] && ecyan $fbdomain || ecyan "${publicip:-服务器地址}:${fbport}"
    ecyan "Web 文件管理器下 APP 目录为 Foundry VTT 程序所在目录"
    # Web 文件管理器的用户名/密码可能在数据库里被修改
    [ -z "$@" ] && information -n "Web 文件管理器用户名/密码： " && ecyan "admin/admin （建议登录后修改）"
fi
if [ "$dashyn" == "y" -o "$dashyn" == "Y" ]; then
    information -n "Docker 仪表盘访问地址： " && [ -n "$dashdomain" ] && ecyan $dashdomain || ecyan "${publicip:-服务器地址}:${dashport}"
    [ -z "$@" ] && ecyan "Docker 仪表盘在第一次运行时需要设置密码"
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
        docker rm -f $optimname

        # 移除网桥
        docker network rm $bridge

        # 清理 Caddyfile
        if [ -n "`awk '/#FvttCnScriptStart/,/#FvttCnScriptEnd/' ${caddyfile} 2>/dev/null | grep .`" ]; then
            # 删除标记内部分
            sed --in-place '/#FvttCnScriptStart/,/#FvttCnScriptEnd/d' ${caddyfile}
        fi

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
        docker restart $optimname

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
        docker rm -f $optimname

        # 移除网桥、挂载
        docker network rm $bridge
        docker volume rm $caddyvolume $fvttvolume $fvttapp $dashvolume $optimempty

        # 删除创建的文件
        rm $caddyfile $fbdatabase $config

        # 清理 Docker 多余镜像
        docker image prune -f

        success "清除完毕！"
    fi
}

check() {
    success "以下是核心容器运行状态；容器状态需要显示为 running，可访问性需要显示为 healthy"
    information -n "FoundryVTT  容器状态：" && ecyan "`docker inspect --format '{{json .State.Status}}' ${fvttname} 2>&1 | tail -1`"
    information -n "FoundryVTT  可访问性：" && ecyan "`docker inspect --format '{{json .State.Health.Status}}' ${fvttname} 2>&1 | tail -1`"
    information -n "Caddy       容器状态：" && ecyan "`docker inspect --format '{{json .State.Status}}' ${caddyname} 2>&1 | tail -1`"
    echoLine

    success "以下是可选配置项的状态；如若部署时没有选择安装，则显示 Error: No such object 为正常情况"
    information -n "FileBrowser 容器状态：" && ecyan "`docker inspect --format '{{json .State.Status}}' ${fbname} 2>&1 | tail -1`"
    information -n "Portainer   容器状态：" && ecyan "`docker inspect --format '{{json .State.Status}}' ${dashname} 2>&1 | tail -1`"
    echoLine

    success "以下是 FVTT 软件下载状态；可以正常访问时需要显示为 下载完毕/可以运行"
    local installing=`docker logs ${fvttname} 2>/dev/null | grep 'Installing Foundry Virtual Tabletop' -n | cut -f1 -d: | tail -1`
    local downloading=`docker logs ${fvttname} 2>/dev/null | grep 'Downloading Foundry Virtual Tabletop' -n | cut -f1 -d: | tail -1`
    local exists=`docker logs ${fvttname} 2>/dev/null | grep 'Foundry Virtual Tabletop.*is installed' -n | cut -f1 -d: | tail -1`
    information -n "FoundryVTT  下载状态：" && [ "${installing:--1}" -lt "${downloading:-0}" -a "${exists:--1}" -lt "${downloading:-0}" ] && warning "未完成" || ecyan "下载完毕"
    local appDir=`docker volume inspect --format '{{ .Mountpoint }}' ${fvttapp} 2>/dev/null | head -1`
    information -n "FoundryVTT  文件状态：" && [ -f "${appDir}/main.js" ] && ecyan "可以运行" || error "文件缺失"
    echoLine

    success "以下是 FVTT 杂项检查；"
    information -n "FVTT-CN     脚本版本：" && cecho -c 'magenta' "自动部署脚本 Ver.${SCRIPT_VERSION}"
    local loginSucce=`docker logs ${fvttname} 2>&1 | grep 'Successfully logged in as'`
    local loginTries=`docker logs ${fvttname} 2>/dev/null | grep 'Using FOUNDRY_USERNAME and FOUNDRY_PASSWORD to authenticate' | wc -l`
    information -n "FoundryVTT  登录状态："
    [ -n "$loginSucce" ] && ecyan "登录成功" || { [ "${loginTries:-0}" -gt 1 ] && error "登录失败" || warning "未尝试登入";  }
    information -n "FoundryVTT  脚本配置：" && [ -f "$config" ] && ecyan "已存储安装参数" || warning "未存储安装参数"
    # 没有完成安装，但是有在下载，尾部应当是最新下载状态
    [ -z "$installing" -a -n "$downloading" ] && information "FoundryVTT  下载速度：" || information "FoundryVTT  最新日志："
    docker logs ${fvttname} 2>/dev/null | tail -10
    [ -z "$installing" -a -n "$downloading" ] && echo "（从左至右）总进度 | 总体积 | 下载进度 | 已下载 | 上传进度 | 已上传 | 平均下载速度 | 上传速度 | 总时间 | 已下载时间 | 剩余时间 | 当前下载速度"
}

do_optim() {
    dockermirror=`can_curl_google`
    [ "${FORCE_GLO,,}" = true ] && dockermirror=""

    [ -n "$dockermirror" ] && warning "切换为 USTC Docker Hub 镜像源（境内加速）" || warning "使用默认的官方 Docker Hub 源"
    docker pull ${dockermirror}${optimimage} && docker tag ${dockermirror}${optimimage} ${optimimage} && docker image inspect ${optimimage} >/dev/null 2>&1 && success "拉取 Optimize-Images 成功" || { error "错误：拉取 Optimize-Images 失败" ; exit 101 ; }
    
    # 运行，忽略 modules/systems
    docker volume create ${optimempty} || warning "警告：创建挂载 ${optimempty} 失败。通常是因为已经创建，可无视该警告"
    optimrun="docker run -itd --name=${optimname} --restart=on-failure --network=none -v $fvttvolume:/data -v ${optimempty}:/data/Data/modules/ -v ${optimempty}:/data/Data/systems/ --watch-directory /data"
    eval $optimrun && docker container inspect $optimname >/dev/null 2>&1 && success "Optimize-Images 容器启动成功" || { error "Optimize-Images 容器启动失败" ; exit 102 ; }
}

undo_optim() {
    error -n "警告！！！使用该命令将移除图片优化容器" && read -p "[y/N]：" optimrmyn
    if [ "$optimrmyn" == "y" -o "$optimrmyn" == "Y" ]; then
        # 移除容器
        docker rm -f $optimname
        # 移除挂载
        docker volume rm $optimempty

        success "移除图片优化容器完毕！"
    fi
}

"$@"

echo
