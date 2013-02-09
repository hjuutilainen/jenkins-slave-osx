#!/bin/bash

JENKINS_HOME=`dirname $0`
JENKINS_CONF=${JENKINS_HOME}/Library/Preferences/org.jenkins-ci.slave.jnlp.conf
JENKINS_SLAVE=`hostname -s | tr '[:upper:]' '[:lower:]'`
JENKINS_MASTER=http://jenkins
JENKINS_PORT=''
JENKINS_USER=''
JENKINS_TOKEN=''
OSX_KEYCHAIN=jenkins.keychain
OSX_KEYCHAIN_PASS=:${JENKINS_HOME}/.keychain_pass
JAVA_ARGS=''
JAVA_TRUSTSTORE=${JENKINS_HOME}/Library/jenkins.truststore
JAVA_TRUSTSTORE_PASS=''

if [ -f ${JENKINS_CONF} ]; then
	chmod 400 ${JENKINS_CONF}
	source ${JENKINS_CONF}
fi

while [ $# -gt 0 ]; do
	case $1 in
		--node=*)
			JENKINS_SLAVE=${1#*=}
			;;
		--master=*)
			JENKINS_MASTER=${1#*=}
			;;
		--jnlp-port=*)
			JENKINS_PORT=":${1#*=}"
			;;
		--user=*)
			JENKINS_USER=${1#*=}
			;;
		--keychain=*)
			OSX_KEYCHAIN=${1#*=}
			;;
		--java-args=*)
			JAVA_ARGS=${1#*=}
			;;
	esac
	shift
done

JENKINS_JNLP_URL=${JENKINS_MASTER}${JENKINS_PORT}/computer/${JENKINS_SLAVE}/slave-agent.jnlp

# Download slave.jar. This ensures that everytime this daemon is loaded, we get the correct slave.jar
# from the Master. We loop endlessly to get the jar, so that if we start before networking, we ensure
# the jar gets loaded anyway.
echo "Getting slave.jar from ${JENKINS_MASTER}"
RESULT=-1
while [ true ]; do
	curl --url ${JENKINS_MASTER}/jnlpJars/slave.jar -o ${JENKINS_HOME}/slave.jar
	RESULT=$?
	if [ $RESULT -eq 0 ]; then
		break
	else
		sleep 60
	fi
done

echo "Launching slave process at ${JENKINS_JNLP_URL}"
RESULT=-1
while [ true ]; do
	# read the password for the OS X Keychain
	# also secure the password to the greatest extent possible
	# there is no way to secure the keychain from administrators
	if [[ -f $OSX_KEYCHAIN_PASS ]]; then
		chmod 400 $OSX_KEYCHAIN_PASS
		source $OSX_KEYCHAIN_PASS
		security unlock-keychain -p ${OSX_KEYCHAIN_PASS} ${OSX_KEYCHAIN}
	fi
	# If we use a trustStore for the Jenkins Master certificates, we need to pass it
	# and its password to the java process that runs the slave. The password is stored
	# in the OS X Keychain that we use for other purposes.
	if [[ -f $JAVA_TRUSTSTORE ]]; then
		JAVA_TRUSTSTORE_PASS=`security find-generic-password -w -a jenkins -s java_truststore ${OSX_KEYCHAIN}`
		JAVA_ARGS="${JAVA_ARGS} -Djavax.net.ssl.trustStore=${JAVA_TRUSTSTORE} -Djavax.net.ssl.trustStorePassword=${JAVA_TRUSTSTORE_PASS}" 
	fi
	# The user and API token are required for Jenkins >= 1.498
	if [ ! -z ${JENKINS_USER} ]; then
		JENKINS_TOKEN=`security find-generic-password -w -a ${JENKINS_USER} -s ${JENKINS_SLAVE} ${OSX_KEYCHAIN}`
		JENKINS_USER="-jnlpCredentials ${JENKINS_USER}:"
	fi
	[[ -f $OSX_KEYCHAIN_PASS ]] && security lock-keychain ${OSX_KEYCHAIN}
	java ${JAVA_ARGS} -jar ${JENKINS_HOME}/slave.jar -jnlpUrl ${JENKINS_JNLP_URL} ${JENKINS_USER}${JENKINS_TOKEN}
	RESULT=$?
	if [ $RESULT -eq 0 ]; then
		break
	else
		sleep 60
	fi
done
echo "Quitting"
