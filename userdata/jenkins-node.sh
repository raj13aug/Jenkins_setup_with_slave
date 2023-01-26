#!/bin/bash

set -x

sudo yum install java-11-openjdk -y
sudo yum -y install git
sudo yum -y install wget
sudo yum install xmlstarlet -y
sudo sleep 120


function slave_setup()

{
    # Wait till jar file gets available
    ret=1
    while (( $ret != 0 )); do
        sudo wget -O /opt/jenkins-cli.jar http://${jenkins_url}:8080/jnlpJars/jenkins-cli.jar
        ret=$?

        echo "jenkins cli ret [$ret]"
    done

    ret=1
    while (( $ret != 0 )); do
        sudo wget -O /opt/slave.jar http://${jenkins_url}:8080/jnlpJars/slave.jar
        ret=$?

        echo "jenkins slave ret [$ret]"
    done
    
    sudo mkdir -p /opt/jenkins-slave
    sudo chown -R ec2-user:ec2-user /opt/jenkins-slave

    # Register_slave
    JENKINS_URL="http://${jenkins_url}:8080"

    USERNAME="${jenkins_username}"
    
    # PASSWORD=$(cat /tmp/secret)
    PASSWORD="${jenkins_password}"

    SLAVE_IP=$(ip -o -4 addr list ${device_name} | head -n1 | awk '{print $4}' | cut -d/ -f1)
    NODE_NAME=$(echo "jenkins-slave-linux-$SLAVE_IP" | tr '.' '-')
    NODE_SLAVE_HOME="/opt/jenkins-slave"
    EXECUTORS=2
    SSH_PORT=22

    CRED_ID="$NODE_NAME"
    LABELS="linux"
    USERID="ec2-user"

    cd /opt
    
    # Creating CMD utility for jenkins-cli commands
    jenkins_cmd="java -jar /opt/jenkins-cli.jar -s $JENKINS_URL -auth $USERNAME:$PASSWORD"

    # Waiting for Jenkins to load all plugins
    while (( 1 )); do

      count=$($jenkins_cmd list-plugins 2>/dev/null | wc -l)
      ret=$?

      echo "count [$count] ret [$ret]"

      if (( $count > 0 )); then
          break
      fi

      sleep 30
    done

    # Delete Credentials if present for respective slave machines
    #$jenkins_cmd delete-credentials system::system::jenkins _ $CRED_ID

    # Generating cred.xml for creating credentials on Jenkins server
    cat > /tmp/cred.xml <<EOF
<com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey plugin="ssh-credentials@1.16">
  <scope>GLOBAL</scope>
  <id>$CRED_ID</id>
  <description>Generated via Terraform for $SLAVE_IP</description>
  <username>$USERID</username>
  <privateKeySource class="com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey\$DirectEntryPrivateKeySource">
    <privateKey>${worker_pem}</privateKey>
  </privateKeySource>
</com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey>
EOF

    # Creating credential using cred.xml
    cat /tmp/cred.xml | $jenkins_cmd create-credentials-by-xml system::system::jenkins _
    jenkins_cmd="java -jar /opt/jenkins-cli.jar -s http://jenkins.robofarming.link:8080/ -auth admin:password"

    # For Deleting Node, used when testing
    $jenkins_cmd delete-node $NODE_NAME
    
    # Generating node.xml for creating node on Jenkins server
    cat > /tmp/node.xml <<EOF
<slave>
  <name>$NODE_NAME</name>
  <description>Linux Slave</description>
  <remoteFS>$NODE_SLAVE_HOME</remoteFS>
  <numExecutors>$EXECUTORS</numExecutors>
  <mode>NORMAL</mode>
  <retentionStrategy class="hudson.slaves.RetentionStrategy\$Always"/>
  <launcher class="hudson.plugins.sshslaves.verifiers.NonVerifyingKeyVerificationStrategy" plugin="ssh-slaves@1.5">
    <host>$SLAVE_IP</host>
    <port>$SSH_PORT</port>
    <credentialsId>$CRED_ID</credentialsId>
  </launcher>
  <label>$LABELS</label>
  <nodeProperties/>
  <userId>$USERID</userId>
</slave>
EOF

  sleep 10
  
  # Creating node using node.xml
  cat /tmp/node.xml | $jenkins_cmd create-node $NODE_NAME
}

### script begins here ###

slave_setup

echo "Done"
exit 0   