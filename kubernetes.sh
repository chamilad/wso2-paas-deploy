DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/base.sh

product=$1
version=$2
profiles=$3

function checkIfKubClusterUp() {
    if [ -z "$KUBERNETES_MASTER" ]; then
       echoError "KUBERNETES_MASTER is not set. Cannot contact Kubernetes API Server."
       exit 1
    else
       echoBold "KUBERNETES_MASTER is set to ${KUBERNETES_MASTER}."
    fi

    curl "${KUBERNETES_MASTER}/api/v1" > /dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        echoError "Cannot communicate with Kubernetes API Server: ${KUBERNETES_MASTER}/api/v1"
        askBold "Continue? (y/n): "
        read -r continue_v
        if [ "$continue_v" == "n" ]; then
            exit 1
        fi
    fi
}

##################################### START ####################################

verifyDockerfilesHome
verifyKubernetesHome
checkIfKubClusterUp

if [ $PLATFORM == "4.4.1" ]; then
  echoDim "Copying patch0005 for Carbon 4.4.1 product"
  mkdir -p "${PUPPET_HOME}/modules/wso2${product}/files/patches/repository/components/patches/patch0005/"
  cp -r "${PACKS_HOME}/carbon/kernel/4.4.1/patch0005/"* "${PUPPET_HOME}/modules/wso2${product}/files/patches/repository/components/patches/patch0005/"
fi

echoDim "Building Kubernetes Membership Scheme..."
pushd "${KUBERNETES_HOME}/common/kubernetes-membership-scheme" > /dev/null 2>&1
# get the current K8S Membership Scheme version
ver_line=$(sed '30q;d' ../../pom.xml)
kube_membership_scheme_version=$(grep -oPm1 "(?<=<version>)[^<]+" <<< "$ver_line")

mvn clean install > /dev/null 2>&1 || { echoError "Couldn't build Kubernetes Membership Scheme"; exit 1; }
popd > /dev/null 2>&1

echoDim "Setting Kubernetes Membeship Scheme version in Puppet..."
sed -i "s/.*kubernetes-membership-scheme-.*/  - repository\/components\/lib\/kubernetes-membership-scheme-${kube_membership_scheme_version}.jar/" $PUPPET_HOME/hieradata/dev/platform/kubernetes.yaml

pushd "${PUPPET_HOME}/modules/wso2${product}/files/configs/repository/components/lib/" > /dev/null 2>&1
echoDim "Copying Kubernetes Membership Scheme dependencies..."
rm -rf /tmp/kubernetes-membership-scheme*
unzip "${KUBERNETES_HOME}/common/kubernetes-membership-scheme/target/kubernetes-membership-scheme-${kube_membership_scheme_version}.zip" -d /tmp
cp /tmp/kubernetes-membership-scheme-$kube_membership_scheme_version/* .

echoDim "Copying MySQL Connector for Java..."
# TODO: configurable mysql connector jar
cp "${PACKS_HOME}/mysql-connector-java-5.1.38-bin.jar" mysql-connector-java-5.1.36-bin.jar

notifyMsg "Puppt changes done!" "PUPPET_HOME (${PUPPET_HOME}) populated with new artifacts" $puppet_icon
popd > /dev/null 2>&1

echoDim "Starting Docker image builds"
pushd "${DOCKERFILES_HOME}/wso2${product}" > /dev/null 2>&1

{
    bash build.sh -v "${version}" -y -r puppet -s kubernetes -l $profiles
    notifyMsg "Docker build complete!" "Check next steps." $docker_icon
}|| {
    echoError "Docker image build failed."
    notifyError "Docker build failed!" "Test steps not continued."
    exit 1
}

popd > /dev/null 2>&1

pushd "${KUBERNETES_HOME}" > /dev/null 2>&1
bash load-images.sh -p "wso2${product}"
popd > /dev/null 2>&1

pushd "${KUBERNETES_HOME}/wso2${product}" > /dev/null 2>&1
echo
echoDim "Deploying WSO2 ${product^^} ${version} on Kubernetes (${KUBERNETES_MASTER})..."

# check if product has distributed deployment in kubernetes artifacts
list_of_profiles=$(find ${KUBERNETES_HOME}/wso2${product}/ -name "wso2${product}*-controller.yaml" | cut -d'-' -f2)
if [ "$list_of_profiles" == "default" ]; then
  if [ "$profiles" != "default" ]; then
    echoError "Multiple profiles have been specified, but there are Kubernetes artifacts for only the default profile. Aborting!"
    exit 1
    # askBold "Continue? (y/n): "
    # read -r continue_v
    # if [ "$continue_v" != "y" ]; then
    #   exit 1
    # fi
  fi

  deploy_flags=""
else
  if [ "$profiles" == "default" ]; then
    deploy_flags=""
  else
    deploy_flags="-d"
  fi
fi

timeout --preserve-status 5m bash deploy.sh "$deploy_flags"
# bash deploy.sh "$deploy_flags"

if [ $? -ne 0 ]; then
    echo
    echoError "Kubernetes deployment didn't become active within 5 minutes"
    echo

    notifyError "Kubernetes deployment failed!" "Kubernetes deployment didn't become active within 5 minutes"

    kubectl get pods
    echo
else
    echo
    echoSuccess "Kubernetes deployment successful"
    echo

    notifyMsg "Kubernetes deployment successful!" "Kubernetes deployment successful" $kubernetes_icon

    # TODO: tail pod logs
fi

echo
askBold "Undeploy artifacts? (y/n): "
read -r undeploy_v
if [ $undeploy_v = "y" ]; then
    bash undeploy.sh -f
fi

popd > /dev/null 2>&1
