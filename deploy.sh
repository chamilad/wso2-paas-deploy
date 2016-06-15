#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/base.sh

config_file_path=$DIR/conf.sh
me=$(basename "$0")

if [ ! -f $config_file_path ]; then
    echoError "Configuration [$config_file_path] file could not be found. Aborting!"
    exit 1
fi

source $config_file_path

# usage output
function showUsageAndExit(){
    echoBold "Deploy WSO2 Products on PaaS platforms with WSO2 Puppet Modules with WSO2 Dockerfiles, WSO2 Kubernetes Artifacts, and WSO2 Mesos Artifacts"
    echo
    echoBold "Usage: ./${me} -v [product_code:product_version] [OPTIONS]"
    echo
    echo
    echoBold "Options:"
    echo -e " \t-p  - Deployment platform. The value specified will be used as the deployment script name to be invoked. ex: \"-p mesos\" will invoke mesos.sh"
    echo -e " \t-l  - Specify the list of profiles to use for testing. \"|\" delimitted."
    echo -e " \t-s  - Persist temporarily prepared PUPPET_HOME."
    echo -e " \t-o  - Clean and repopulate PUPPET_HOME."
    echo -e " \t-h  - Show usage"
    echo
    echo
    echoBold "Example:"
    echo "./${me} -v esb:4.9.0"
    echo "./${me} -v esb:4.9.0 -p docker"
    echo "./${me} -v esb:4.9.0 -p kubernetes"

    exit 0
}

# check if PUPPET_HOME exists
# if not, build PUPPET_MODULES_HOME and populates PUPPET_HOME
function setupPuppetHome(){
    # check if PUPPET_HOME exists
    if [ -d $PUPPET_HOME ]; then
        if [ $override_puppet == false ]; then
            echoDim "PUPPET_HOME [$PUPPET_HOME] already exists and not to be overridden."
            return
        fi
    fi

    # TODO: create a temporary puppet home and persist if specified, /tmp/puppet_home_$(uuidgen)

    echoDim "Cleaning existing PUPPET_HOME..."
    pushd "${PUPPET_HOME}" > /dev/null 2>&1
    rm -rf "${PUPPET_HOME}"/manifests
    rm -rf "${PUPPET_HOME}"/modules
    rm -rf "${PUPPET_HOME}"/hiera*
    rm -rf "${PUPPET_HOME}"/LICENSE
    rm -rf "${PUPPET_HOME}"/README*

    verifyPuppetModulesHome

    echoDim "Building wso2/puppet-modules..."
    pushd "${PUPPET_MODULES_HOME}" > /dev/null 2>&1

    mvn clean install &> /dev/null || { echoError "Puppet Modules build failed."; exit 1; }
    popd > /dev/null 2>&1

    echoDim "Populating new build..."
    unzip "${PUPPET_MODULES_HOME}/target/wso2-puppet-modules-"*.zip &> /dev/null || { echoError "Error populating new build"; exit 1; }

    echoDim "Copying packs..."
    # TODO: get jdk version from file
    cp "${PACKS_HOME}/jdk-7u80-linux-x64.tar.gz" "${PUPPET_HOME}"/modules/wso2base/files/
    cp "${PACKS_HOME}/wso2${product}-${version}.zip" "${PUPPET_HOME}/modules/wso2${product}/files/"
    echoBold "Packs copied to PUPPET_HOME"
    popd > /dev/null 2>&1
}

# check if critical input values are absent and panic if so
function checkRequiredInput() {
    if [ -z $product ]; then
        echoError "Specify product code and version as \"-v [code]:[version]\". Ex: \"./${me} -v esb:4.9.0\""
        exit 1
    fi

    if [ -z $version ]; then
        echoError "Specify product code and version as \"-v [code]:[version]\". Ex: \"./${me} -v esb:4.9.0\""
        exit 1
    fi
}

# $1 product code
# $2 version
function checkProductPlatform () {
    export PLATFORM=$(grep "wso2${1}:${2}" $DIR/release-matrix.txt | awk '{print $1}')

    if [ -z $PLATFORM ]; then
      echoError "Platform version for WSO2${1^^}:${2} not found. Check input."
      exit 1
    fi

    if version_gt "4.4.1" $PLATFORM; then
        echoError "${me} only supports WSO2 Carbon 4.4.1 or greater. Found $PLATFORM."
        exit 1
    fi

    echoDim "WSO2${1^^}:${2} is based on ${PLATFORM}"
}

##################################### START ####################################
# default values
profiles='default'
deployment_platform=""
override_puppet=false

while getopts :v:l:p:o FLAG; do
    case $FLAG in
        v)
            prod_version=$OPTARG
            IFS=':' read -a prod_v_array <<< "$prod_version"
            product="${prod_v_array[0]}"
            version="${prod_v_array[1]}"
            ;;
        p)
            deployment_platform=$OPTARG
            ;;
        l)
            profiles=$OPTARG
            ;;
        h)
            showUsageAndExit
            ;;
        o)
            override_puppet=true
            ;;
        \?)
            showUsageAndExit
            ;;
    esac
done

checkRequiredInput
checkProductPlatform $product $version
setupPuppetHome

if [ -z $deployment_platform ] || [ $deployment_platform == "" ]; then
    echoSuccess "Done"
    exit 0
fi

if [ ! -f $DIR/$deployment_platform.sh ]; then
    echoError "Cannot find test implementation $DIR/${deployment_platform}.sh. Aborting!"
    exit 1
else
    # TODO: support multiple tests at once
    bash $DIR/$deployment_platform.sh $product $version $profiles
fi
