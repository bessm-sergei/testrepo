#!/bin/bash
while getopts "dircu:p:a:N:A:R:P:M:" opt
	do
		case $opt in
			d ) SCRIPT_MODE="SAFEDOWNLOAD";;
			i ) SCRIPT_MODE="SAFEYUMINSTALL";;
			r ) SCRIPT_MODE="SAFEYUMREMOVE";;
			c ) SCRIPT_MODE="SAFEDISTRCLEANUP";;
			u ) REPOUSER=$OPTARG;;
			p ) REPOPASS=$OPTARG;;
			N ) NEXUS_URL=$OPTARG;;
			A ) ARTIFACT=$OPTARG;;
			R ) REPONAME=$OPTARG;;
			P ) PACKAGENAME=$OPTARG;;
			M ) PACKAGEMANAGER=$OPTARG;;
			* ) exit 1;;
		esac
done
INTERACTIVE=$(tty)
if [ -z $SCRIPT_MODE ]; then echo -e "\nScript mode is not correct, please use [-d],[-i],[-r],[-c] only" && exit 1; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEDOWNLOAD" ] && [ -z "$NEXUS_URL" ]; then read -rp "Enter nexus URL: " NEXUS_URL; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEDOWNLOAD" ] && [ -z "$ARTIFACT" ]; then read -rp "Enter zip archive name: " ARTIFACT; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEDOWNLOAD" ] && [ -z "$REPOUSER" ]; then read -rp "Enter nexus user: " REPOUSER; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEDOWNLOAD" ] && [ -z "$REPOPASS" ]; then read -rsp "Enter user's password: " REPOPASS; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEYUMINSTALL" ] && [ -z "$REPONAME" ]; then read -rp "Enter REPO name: " REPONAME; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEYUMINSTALL" ] && [ -z "$PACKAGENAME" ]; then read -rp "Enter package name: " PACKAGENAME; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEYUMINSTALL" ] && [ -z "$PACKAGEMANAGER" ]; then read -rp "DNF or YUM (DNF by default): " PACKAGEMANAGER; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEYUMREMOVE" ] && [ -z "$PACKAGENAME" ]; then read -rp "Enter package name: " PACKAGENAME; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEYUMREMOVE" ] && [ -z "$PACKAGEMANAGER" ]; then read -rp "DNF or YUM (DNF by default): " PACKAGEMANAGER; fi
if [ ! -z "$INTERACTIVE" ] && [ "$SCRIPT_MODE" == "SAFEDISTRCLEANUP" ] && [ -z "$REPONAME" ]; then read -rp "Enter REPO name: " REPONAME; fi
if [ "$SCRIPT_MODE" == "SAFEDOWNLOAD" ] && ([ -z "$NEXUS_URL" ] || [ -z "$ARTIFACT" ] || [ -z "$REPOUSER" ] || [ -z "$REPOPASS" ]); then echo "Values can't be empty!" && exit 1; fi
if [ "$SCRIPT_MODE" == "SAFEYUMINSTALL" ] && ([ -z "$REPONAME" ] || [ -z "$PACKAGENAME" ]); then echo "Values can't be empty!" && exit 1; fi
if [ "$SCRIPT_MODE" == "SAFEYUMREMOVE" ] && ([ -z "$PACKAGENAME" ]); then echo "Values can't be empty!" && exit 1; fi
if [ "$SCRIPT_MODE" == "SAFEDISTRCLEANUP" ] && [ -z "$REPONAME" ]; then echo "Values can't be empty!" && exit 1; fi
SAFEDOWNLOAD () {
if [[ "$NEXUS_URL" != "${NEXUS_URL%[[:space:]]*}" || "$ARTIFACT" != "${ARTIFACT%[[:space:]]*}" || "$REPOUSER" != "${REPOUSER%[[:space:]]*}" || "$REPOPASS" != "${REPOPASS%[[:space:]]*}" ]]
	then echo -e "\nInput values should have no spaces!\n"
	exit 1
fi
RHEL_VERSION=$(cat /etc/os-release | grep VERSION_ID | awk -F"=\"" '{print $2}' | awk -F"." '{print $1}')
ALLOWED_REPOS=(https://{domain-nexus,infra.nexus,int.nexus,ext.nexus}.{sub1,sub2,ca}.domain.ru)
ENTERED_URL_CHECK=false
CREATEREPO_POSSIBILITY=false
if [ $RHEL_VERSION == 8 ] && (!(yum list installed | grep createrepo_c))
        then yum install -y createrepo_c
elif [ $RHEL_VERSION == 7 ] && (!(yum list installed | grep yum-utils))
        then yum install -y yum-utils
fi
for ALLOWED_URL in ${ALLOWED_REPOS[@]}
do
    [[ $NEXUS_URL == $ALLOWED_URL* ]] && ENTERED_URL_CHECK=true
done
if [ $ENTERED_URL_CHECK == "false" ]
	then echo "Repository ###$NEXUS_URL### denied"
	exit 1
fi
if [[ $NEXUS_URL == *\/ ]]
    then NEXUS_URL+=""
    else NEXUS_URL+="/"
fi
if [[ $ARTIFACT == *zip ]]
    then ARTIFACT+=""
    else ARTIFACT+=".zip"
fi
SUBDIR=$(echo $ARTIFACT | awk -F".zip" '{print $1}')
REPOFILE=$SUBDIR
if test -f /etc/yum.repos.d/$REPOFILE.repo
	then echo "Repository already exists, nothing to do"
	exit 0
	else echo "Start download archive"
fi
TEST_CONNECTION=$(curl -I --insecure --user $REPOUSER:$REPOPASS $NEXUS_URL$ARTIFACT | grep 'HTTP/1.1')
if grep -q "HTTP/1.1 200 OK" <<< $TEST_CONNECTION
        then echo -e "\nRemote file exists\n"
elif grep -q "HTTP/1.1 404 Not Found" <<< $TEST_CONNECTION
		then echo -e "\nRemote file does not exists\n"
        exit 1
elif grep -q "HTTP/1.1 401 Unauthorized" <<< $TEST_CONNECTION
		then echo -e "\nUsername or Password Authentication Failed\n"
		exit 1
elif grep -q "HTTP/1.1 403 Forbidden" <<< $TEST_CONNECTION
		then echo -e "\nForbidden\n"
		exit 1
fi
wget --user "$REPOUSER" --password "$REPOPASS" --no-check-certificate "$NEXUS_URL$ARTIFACT" -P "/opt/distr/rpmrepo/"
mkdir /opt/distr/rpmrepo/$SUBDIR/
setfacl -d -m o::r-x /opt/distr/rpmrepo/$SUBDIR/
unzip /opt/distr/rpmrepo/$ARTIFACT -d /opt/distr/rpmrepo/$SUBDIR/
rm /opt/distr/rpmrepo/$ARTIFACT
createrepo --database /opt/distr/rpmrepo/$SUBDIR/
touch /etc/yum.repos.d/$REPOFILE.repo
echo "[$REPOFILE]
name=$REPOFILE:###Local_Repository###
baseurl=/opt/distr/rpmrepo/$SUBDIR/
enabled=1
gpgcheck=0" > /etc/yum.repos.d/$REPOFILE.repo
yum makecache --disablerepo=* --enablerepo=$REPOFILE
}
SAFEYUMINSTALL () {
ALLOWED_REPOS_ARRAY=($(grep -l "###Local_Repository###" /etc/yum.repos.d/* | awk -F"/" '{print $4}' | awk -F".repo" '{print $1}'))
ALLOWED_REPOS=$(echo ${ALLOWED_REPOS_ARRAY[*]} | tr -s ‘\ ’ ‘,’)
DENIED_PACKAGE_NAMES=({enable-,disable-,enable,disable}repo)
if [[ "$REPONAME" != "${REPONAME%[[:space:]]*}" || "$PACKAGENAME" != "${PACKAGENAME%[[:space:]]*}" || "$PACKAGEMANAGER" != "${PACKAGEMANAGER%[[:space:]]*}" ]]
	then echo -e "\nInput values should have no spaces!\n"
	exit 1
fi
PACKAGEMANAGER=${PACKAGEMANAGER:-dnf}
ENTERED_REPO_CHECK=false
for DENIED in ${DENIED_PACKAGE_NAMES[@]}
do
    if grep -q "$DENIED" <<< "$PACKAGENAME"
		then ENTERED_PACKAGE_NAME_CHECK=false
	fi
done
if [[ $ENTERED_PACKAGE_NAME_CHECK == "false" ]]
	then echo "ERROR: Wrong package name!"
	exit 1
fi
for ALLOWED in ${ALLOWED_REPOS_ARRAY[@]}
do
    [[ $REPONAME == $ALLOWED ]] && ENTERED_REPO_CHECK=true
done
if [[ $ENTERED_REPO_CHECK == "false" ]]
	then echo "ERROR: Repository ###$REPONAME### denied! Allowed only:"
	printf "%s\n" "${ALLOWED_REPOS_ARRAY[@]}"
	exit 1
fi
if [ "$PACKAGEMANAGER" == "dnf" ]
        then dnf install -y $PACKAGENAME --disablerepo=* --enablerepo=$ALLOWED_REPOS
		elif [ "$PACKAGEMANAGER" == "yum" ]
		then yum install -y $PACKAGENAME --disablerepo=* --enablerepo=$ALLOWED_REPOS
		else echo "ERROR: Wrong package manager"
		exit 1
fi
}
SAFEYUMREMOVE () {
ALLOWED_REPOS_ARRAY=($(grep -l "###Local_Repository###" /etc/yum.repos.d/* | awk -F"/" '{print $4}' | awk -F".repo" '{print $1}'))
DENIED_PACKAGE_NAMES=({enable-,disable-,enable,disable}repo)
if [[ "$PACKAGEMANAGER" != "${PACKAGEMANAGER%[[:space:]]*}" || "$PACKAGENAME" != "${PACKAGENAME%[[:space:]]*}" ]]
	then echo -e "\nInput values should have no spaces!\n"
	exit 1
fi
PACKAGEMANAGER=${PACKAGEMANAGER:-dnf}
ENTERED_REPO_CHECK=false
for DENIED in ${DENIED_PACKAGE_NAMES[@]}
do
    if grep -q "$DENIED" <<< "$PACKAGENAME"
		then ENTERED_PACKAGE_NAME_CHECK=false
	fi
done
if [[ $ENTERED_PACKAGE_NAME_CHECK == "false" ]]
	then echo "ERROR: Wrong package name!"
	exit 1
fi
if [ "$PACKAGEMANAGER" == "dnf" ]
        then PROVIDED=$(dnf list installed | grep $PACKAGENAME | awk -F"@" '{print $2}')
		elif [ "$PACKAGEMANAGER" == "yum" ]
		then PROVIDED=$(yum list installed | grep $PACKAGENAME | awk -F"@" '{print $2}')
		else echo "Wrong package manager"
		exit
fi
if [ -z "$PROVIDED" ]
	then echo "Package not installed"
	exit
fi
for ALLOWED in ${ALLOWED_REPOS_ARRAY[@]}
do
    [[ $PROVIDED == $ALLOWED ]] && ENTERED_REPO_CHECK=true
done 
if [ $ENTERED_REPO_CHECK == "false" ]
	then echo "ERROR: Permissions denied! Allowed only packages, installed from local repositories:"
	printf "%s\n" "${ALLOWED_REPOS_ARRAY[@]}"
	exit 1
fi
if [ "$PACKAGEMANAGER" == "dnf" ]
        then dnf remove -y $PACKAGENAME
		echo "$PACKAGENAME removed"
		elif [ "$PACKAGEMANAGER" == "yum" ]
		then yum remove -y $PACKAGENAME
		echo "$PACKAGENAME removed"
		else echo "Wrong package manager"
		exit 1
fi
}
SAFEDISTRCLEANUP () {
ALLOWED_REPOS_ARRAY=($(grep -l "###Local_Repository###" /etc/yum.repos.d/* | awk -F"/" '{print $4}' | awk -F".repo" '{print $1}'))
ENTERED_REPO_CHECK=false
if [[ "$REPONAME" != "${REPONAME%[[:space:]]*}" ]]
	then echo -e "\nInput values should have no spaces!\n"
	exit 1
fi
if [[ $REPONAME == *zip ]]
    then REPONAME=$(echo $REPONAME | awk -F".zip" '{print $1}')
fi
for ALLOWED in ${ALLOWED_REPOS_ARRAY[@]}
do
    [[ $REPONAME == $ALLOWED ]] && ENTERED_REPO_CHECK=true
done
if [ $ENTERED_REPO_CHECK == "false" ]
	then echo "Repository ###$REPONAME### not listed as Local repository. Permissions denied!"
	exit 1
fi
rm -rf /opt/distr/rpmrepo/$REPONAME*
rm -f /etc/yum.repos.d/$REPONAME.repo
yum clean all --disablerepo=* --enablerepo=$REPONAME
yum makecache
}
if [ "$SCRIPT_MODE" == "SAFEDOWNLOAD" ]; then SAFEDOWNLOAD; fi
if [ "$SCRIPT_MODE" == "SAFEYUMINSTALL" ]; then SAFEYUMINSTALL; fi
if [ "$SCRIPT_MODE" == "SAFEYUMREMOVE" ]; then SAFEYUMREMOVE; fi
if [ "$SCRIPT_MODE" == "SAFEDISTRCLEANUP" ]; then SAFEDISTRCLEANUP; fi
