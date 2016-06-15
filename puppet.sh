DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/base.sh

product=$1
version=$2
profiles=$3

# TODO: check distributed setup, with mysql
echoDim "Verifying the default profile on Puppet Vagrant setup..."
sample_config_file="${PUPPET_MODULES_HOME}/vagrant/samples/wso2${product}/wso2${product}-${version}-default.config.yaml"

if [ ! -e $sample_config_file ]; then
    echoError "Sample file does not exist! $sample_config_file"
    notifyError "Sample file does not exist!" "Check if $sample_config_file exists."
    exit 1
fi

echoDim "Copying wso2${product}-${version}-default.config.yaml as the config.yaml for Vagrant test..."
cp $sample_config_file "${PUPPET_MODULES_HOME}/vagrant/config.yaml"

echoDim "Starting Puppet-Vagrant test environment for WSO2 ${product^^}:${version}:default"
notifyMsg "Vagrant Up" "Starting Puppet-Vagrant test environment for WSO2 ${product^^}:${version}:default" $vagrant_icon
pushd "${PUPPET_MODULES_HOME}/vagrant" > /dev/null 2>&1
{
    vagrant destroy -f && vagrant up && notifyMsg "Vagrant Up" "VM started. Check next steps!" $vagrant_icon
    machine_up=true
} || {
    notifyError "Vagrant Up" "Starting the test VM failed."
    machine_up=false
}

if [ $machine_up == true ]; then
    echo
    askBold "Add wso2::hostname to host machine's /etc/hosts file (requires sudo)? (y/n): "
    read -r hosts_v
    if [ "$hosts_v" == "y" ]; then
        vagrant_ip=$(grep "ip: " config.yaml | awk '{print $2}')
        addPuppetHostsEntry $product $version $vagrant_ip
    fi

    echo
    askBold "Tail WSO2 logs in the VM? (y/n): "
    read -r tail_v
    if [ "$tail_v" == "y" ]; then
        vagrant ssh -c 'ss=$(hostname -I | awk '\''{print $NF}'\'');ss="${ss// /}";sudo tail -n10000 -f /mnt/$ss/wso2'"${product}"'-'"${version}"'/repository/logs/wso2carbon.log' "${product}.dev.wso2.org"
    fi

    echo
    askBold "SSH to the VM? (y/n): "
    read -r ssh_v
    if [ "$ssh_v" == "y" ]; then
        vagrant ssh "${product}.dev.wso2.org"
    fi
fi

echo
askBold "Destroy VM? (y/n): "
read -r destroy_v
if [ "$destroy_v" == "y" ]; then
    echoDim "Destroying ${product}.dev.wso2.org"
    vagrant destroy -f
    rm -rfv "${PUPPET_MODULES_HOME}/vagrant/config.yaml"
fi

if [ "$hosts_v" == "y" ]; then
    echoDim "Removing /etc/hosts entry"
    sudo sed -i "/${vagrant_ip}   ${wso2_hostname}/d" /etc/hosts
fi

popd > /dev/null 2>&1
