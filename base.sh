#!/bin/bash

export vagrant_icon=$DIR/img/vagrant_icon.png
export puppet_icon=$DIR/img/puppet_icon.png
export kubernetes_icon=$DIR/img/kubernetes_icon.png
export docker_icon=$DIR/img/docker_icon.png

function echoDim () {
    if [ -z "$2" ]; then
        echo $'\e[2m'"${1}"$'\e[0m'
    else
        echo -n $'\e[2m'"${1}"$'\e[0m'
    fi
}

function echoError () {
    echo $'\e[1;31m'"${1}"$'\e[0m'
}

function echoSuccess () {
    echo $'\e[1;32m'"${1}"$'\e[0m'
}

function echoDot () {
    echoDim "." "append"
}

function echoBold () {
    echo $'\e[1m'"${1}"$'\e[0m'
}

function askBold () {
    echo -n $'\e[1m'"${1}"$'\e[0m'
}

# $1 Message header
# $2 Message
function notifyError () {
    notifyMsg $1 $2 software-update-urgent
}

# $1 Message header
# $2 Message
# $3 Message icon
function notifyMsg () {
    if [ $OSTYPE == "linux-gnu" ]; then
        notify-send -i $3 "$1" "$2"
    fi
    # TODO: for Mac as well
}

# return 0 if the given command exists, returns 1 if not
# $1 command name
function checkCommandExists(){
    command -v $1 >/dev/null 2>&1 || { echo >&2 "$1 is required, but not intalled."; return 1; }
}

# $1 IP address
# $2 Hostname
function addHostsEntry () {
    echoDim "Adding $1:$2 to /etc/hosts"
    export hosts_entry="$1 ${wso2_hostname}"
    export PT_HOSTS_ENTRY=$wso2_hostname
    echo $hosts_entry | sudo tee -a /etc/hosts >> /dev/null
    echoDim "Hosts entry added"
    echo
}

# $1 Product code
# $2 Version
# $3 IP Address
function addPuppetHostsEntry () {
    wso2_hostname=$(cat "${PUPPET_HOME}/hieradata/dev/wso2/wso2${1}/${2}/default/default.yaml" | grep wso2::hostname)
    if [ -z "$wso2_hostname" ]; then
        echoError "wso2::hostname is not defined in ${PUPPET_HOME}/hieradata/dev/wso2/wso2${1}/${2}/default.yaml. Not setting /etc/hosts entry."
    elif [[ $wso2_hostname == *"::ipaddress"* ]]; then
        echoError "wso2::hostname is defined as the IP address of the VM. Not setting /etc/hosts entry"
    elif [[ $wso2_hostname == *"::clientcert"* ]]; then
        echoError "wso2::hostname is defined as the Node's existing hostname, not setting /etc/hosts entry"
    elif [[ $wso2_hostname == *"::fqdn"* ]]; then
        echoError "wso2::hostname is defined as the Node's FQDN, not setting /etc/hosts entry"
    else
        IFS=':' read -a tmp_arr <<< "$wso2_hostname"
        wso2_hostname=${tmp_arr[-1]}
        wso2_hostname="${wso2_hostname// /}"

        addHostsEntry $3 wso2_hostname
        echo
        echoBold "Hosts entry added. Access Carbon console through https://${wso2_hostname}:9443/carbon"
    fi
}

function removeAddedHostsEntry () {
    if [ -z PT_HOSTS_ENTRY ]; then
        echoError "No hosts file entries have been added. Skipping..."
        return 1
    fi

    echoDim "Removing /etc/hosts entry: \"${PT_HOSTS_ENTRY}\""
    sudo sed -i "/$PT_HOSTS_ENTRY/d" /etc/hosts
    unset PT_HOSTS_ENTRY
}

function version_gt() {
    test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"
}


########################## Verification Functions ##############################
# Check if each repository exists, if not clone and switch to specified release

function verifyPuppetModulesHome(){
    echoDim "Verifying PUPPET_MODULES_HOME exists..."
    if [ ! -d $PUPPET_MODULES_HOME ]; then
        echoError "Invalid Puppet location [${PUPPET_MODULES_HOME}]. "
        askBold "Clone? (y/n): "
        read -r clone_puppet

        {
            if [ $clone_puppet == "y" ]; then
                parent_dir=$(dirname $PUPPET_MODULES_HOME)
                pushd $parent_dir > /dev/null 2>&1
                git clone https://github.com/wso2/puppet-modules.git && echoBold "wso2/puppet-modules cloned!"
                popd > /dev/null 2>&1
            fi
        } || {
            echoError "Error while cloning wso2/puppet-modules. Check PUPPET_MODULES_HOME."
            exit 1
        }
    fi

    echoDim "Verifying PUPPET_MODULES_HOME is at the required version [$PUPPET_MODULES_VERSION]..."
    pushd $PUPPET_MODULES_HOME > /dev/null 2>&1
    if [ "$PUPPET_MODULES_VERSION" != "latest" ]; then
        compare_version="heads/v$PUPPET_MODULES_VERSION"
    else
        compare_version="master"
    fi

    {
        git_version=$(git rev-parse --abbrev-ref HEAD) # heads/v2.0.0
        if [ $git_version != $compare_version ]; then
            # following returns the number of modified or new files
            git_dirty_files=$(git status --porcelain 2>/dev/null| grep "^??" | wc -l)
            if [ $git_dirty_files != "0" ]; then
                echoError "wso2/puppet-modules is not at the specified version [$PUPPET_MODULES_VERSION], and cannot be automatically switched because there are local uncommitted changes."
                exit 1
            else
                git checkout -b v$PUPPET_MODULES_VERSION
                echo "Switched to local branch v$PUPPET_MODULES_VERSION"
            fi
        fi
    } || {
        echoError "Error while verifying Puppet Modules version. Check $PUPPET_MODULES_HOME."
        exit 1
    }

    popd > /dev/null 2>&1
}

function verifyDockerfilesHome () {
    if [ ! -d $DOCKERFILES_HOME ]; then
        echoError "Invalid Dockerfiles location [$DOCKERFILES_HOME]."
        askBold "Clone? (y/n): "
        read -r clone_dockerfiles

        {
            if [ $clone_dockerfiles == "y" ]; then
                parent_dir=$(dirname $DOCKERFILES_HOME)
                pushd $parent_dir > /dev/null 2>&1
                git clone https://github.com/wso2/dockerfiles.git && echoBold "wso2/dockerfiles cloned!"
                popd > /dev/null 2>&1
            fi
        } || {
            echoError "Error while cloning wso2/dockerfiles. Check DOCKERFILES_HOME."
            exit 1
        }
    fi

    echoDim "Verifying DOCKERFILES_HOME is at the required version [$DOCKERFILES_VERSION]..."
    pushd $DOCKERFILES_HOME > /dev/null 2>&1
    if [ "$DOCKERFILES_VERSION" != "latest" ]; then
        compare_version="heads/v$DOCKERFILES_VERSION"
    else
        compare_version="master"
    fi

    {
        git_version=$(git rev-parse --abbrev-ref HEAD) # heads/v2.0.0
        if [ $git_version != $compare_version ]; then
            # following returns the number of modified or new files
            git_dirty_files=$(git status --porcelain 2>/dev/null| grep "^??" | wc -l)
            if [ $git_dirty_files != "0" ]; then
                echoError "wso2/dockerfiles is not at the specified version [$DOCKERFILES_VERSION], and cannot be automatically switched because there are local uncommitted changes."
                exit 1
            else
                git checkout -b v$DOCKERFILES_VERSION
                echo "Switched to local branch v$DOCKERFILES_VERSION"
            fi
        fi
    } || {
        echoError "Error while verifying Dockerfiles version. Check $DOCKERFILES_HOME."
        exit 1
    }

    popd > /dev/null 2>&1
}

function verifyKubernetesHome () {
    if [ ! -d $KUBERNETES_HOME ]; then
        echoError "Invalid Kubernetes Artifacts location [$KUBERNETES_HOME]."
        askBold "Clone? (y/n): "
        read -r clone_kube

        {
            if [ $clone_kube == "y" ]; then
                parent_dir=$(dirname $KUBERNETES_HOME)
                pushd $parent_dir > /dev/null 2>&1
                git clone https://github.com/wso2/kubernetes-artifacts.git && echoBold "wso2/kubernetes-artifacts cloned!"
                popd > /dev/null 2>&1
            fi
        } || {
            echoError "Error while cloning wso2/kubernetes-artifacts. Check KUBERNETES_HOME."
            exit 1
        }
    fi

    echoDim "Verifying KUBERNETES_HOME is at the required version [$KUBERNETES_VERSION]..."
    pushd $KUBERNETES_HOME > /dev/null 2>&1
    if [ "$KUBERNETES_VERSION" != "latest" ]; then
        compare_version="heads/v$KUBERNETES_VERSION"
    else
        compare_version="master"
    fi

    {
        git_version=$(git rev-parse --abbrev-ref HEAD) # heads/v2.0.0
        if [ $git_version != $compare_version ]; then
            # following returns the number of modified or new files
            git_dirty_files=$(git status --porcelain 2>/dev/null| grep "^??" | wc -l)
            if [ $git_dirty_files != "0" ]; then
                echoError "wso2/kubernetes-artifacts is not at the specified version [$KUBERNETES_VERSION], and cannot be automatically switched because there are local uncommitted changes."
                exit 1
            else
                git checkout -b v$KUBERNETES_VERSION
                echo "Switched to local branch v$KUBERNETES_VERSION"
            fi
        fi
    } || {
        echoError "Error while verifying Kubernetes Artifacts version. Check $KUBERNETES_HOME."
        exit 1
    }

    popd > /dev/null 2>&1
}
