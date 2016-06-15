# TODO: use of docker compose
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/base.sh

product=$1
version=$2
profiles=$3

##################################### START ####################################

verifyDockerfilesHome

echoDim "Starting Docker image builds"
pushd "${DOCKERFILES_HOME}/wso2${product}" > /dev/null 2>&1
{
    bash build.sh -v "${version}" -q -r puppet
    notifyMsg "Docker build complete!" "Starting Docker run." $docker_icon
} || {
    echoError "Docker image build failed."
    notifyError "Docker build failed!" "Test steps not continued."
    exit 1
}

echo
echoDim "Adding an /etc/hosts entry..."
addPuppetHostsEntry $product $version "127.0.0.1" # TODO: Consider mapped portss

echoDim "Running Docker image"
bash run.sh -v $version

echo
echo
askBold "Stop container? (y/n): "
read -r stop_container_v

if [ "$stop_container_v" == "y" ]; then
    bash stop.sh
    echoDim "Container stopped."
    echo
fi

echoDim "Cleaning.."
removeAddedHostsEntry
popd > /dev/null 2>&1
