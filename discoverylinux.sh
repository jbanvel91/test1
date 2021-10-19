#!/bin/bash
# LINUX

## Program: discoverylinux.sh
## Author: ATADATA - 2016
##
## Copyright: Property of ATADATA, Copyright (c) 2015 ATADATA Corporation, Atlanta, Georgia. All Rights Reserved.
##           Use of this material without the express consent of ATADATA or assignees is unlawful
##           and subject to prosecution to the fullest extent of the law.
##
## Version: 2.00.81
usage() {
  echo "VALIDATION MODE"
  echo "Usage: $0 [SERVER_ID] [JOB_ID] [CONSOLE_URL]"
  echo "  [SERVER_ID]: server unique identifier"
  echo "  [JOB_ID]: job unique identifier"
  echo "  [CONSOLE_URL]: valid console root url (example: http://127.0.0.1)"
  echo
  echo "DISCOVERY MODE"
  echo "Usage: $0 [SERVER_ID] [JOB_ID] [CONSOLE_URL] [HOURS] [INTERVAL] [DISCOVERY_FAIL_THRESHOLD] [WEBSERVER_DISCOVERY] [DISCOVERYTYPE] [DISKGROWTHINTERVAL]"
  echo "  [SERVER_ID]: server unique identifier"
  echo "  [JOB_ID]: job unique identifier"
  echo "  [CONSOLE_URL]: valid console root url (example: http://127.0.0.1)"
  echo "  [HOURS]: how long the script should run"
  echo "  [INTERVAL]: wait time (in minutes) between discovery executions"
  echo "  [DISCOVERY_FAIL_THRESHOLD]: how much data lose can be accepted"
  echo "  [DISCOVERYTYPE]: Manual or Normal"

  exit 1
}

# exit and remove crontab entry if exists
discovery_monitor_exit() {
  # remove lock file to allow future executions
  \rm -f ${DIR}/discovery_monitor
  \rm -f $LOCK_FILE
  \rm -f $stepfile
  (crontab -l 2>/dev/null | grep -v discovery_monitor) | crontab -
  exit "$1"
}

discovery_monitor () {
  echo "
export PATH=$PATH
if [ -f $LOCK_FILE ] && ! ps aux |awk '{print \$2}'|grep \$(cat $LOCK_FILE) >/dev/null; then
  ${DIR}/discoverylinux.sh ${*}
elif [ ! -f $LOCK_FILE ] && [ -f $stepfile ] && [ ! -f $DIR/PauseDiscovery.txt ]; then
  ${DIR}/discoverylinux.sh ${*}
fi" > "${DIR}"/discovery_monitor
  chmod 755 "${DIR}"/discovery_monitor
}

# helper method to convert file to JSON array
json_array() {
  set +x # disable debugging
  unset array
  array="["
  while [ $# -gt 0 ]; do
   x=${1//\\/\\\\}
   array=$array\"${x//\"/\\\"}\"
   [ $# -gt 1 ] && array=$array,
   shift
  done
  array=$array]
  echo $array
  [[ $R -lt 2 ]] && set -x # enable debugging again
}

json_array_from_file() {
  set +x # disable debugging
  unset array
  # nawk will perfom:
  # 1) count amount of lines to avoid adding a "," at the end of the JSON
  # 2) replace \(backslash) characters with double backslash
  # 3) replace "(double quotes) with backslashed double quotes to avoid breaking JSON
  # 4) replace * with backslashed * to prevent bash to interpret it and use it as wilcard. This is needed to remove special characters like tabs. The below sed will replace back the *.
  array=[$(awk 'FNR==NR{tot=NR; next} {gsub(/%/,"%%");gsub(/\\/,"\\\\");gsub(/"/,"\\\"");gsub(/\*/,"\\*"); printf "\""$0"\"" } FNR!=tot{printf ","}' $1 $1)]
  echo $array | sed 's/\\\*/*/g;'
  [[ $R -lt 2 ]] && set -x # enable debugging again
}

# helper method to convert file to JSON objects array
json_object_array() {
  set +x # disable debugging
  unset array
  array="["
  while [ $# -gt 0 ]; do
   x=${1//\\/\\\\}
   array=$array${x}
   [ $# -gt 1 ] && array=$array,
   shift
  done
  array=$array]
  echo $array
  [[ $R -lt 2 ]] && set -x # enable debugging again
}

# helper method for json_generator
json_generator_usage() {
  echo "Method must receive arguments in groups of 3: [FILE] [TYPE] [KEY]"
  echo "  [INPUT]: valid source file, or a string if type is [literal]"
  echo "  [TYPE]: literal, file, array, objectsArray, number, boolean"
  echo "  [KEY]: key name for json element"
}

# JSON objects generator
json_generator() {
  (( ARGS=$#%3 )) # %3 == "module of 3" calculate if arguments are multiple of 3
  [[ $ARGS -ne 0 && $# -gt 0 ]] && echo "Invalid number of arguments" && json_generator_usage && return 1

  JSON="{ "
  while [ $# -gt 0 ]; do
    INPUT="$1"
    TYPE=$2
    KEY=$3
    shift; shift; shift

    [[ -z $KEY ]] && "KEY cannot be empty" && json_generator_usage && return 2

    case $TYPE in
      'objectsArray' )
        [[ ! -f $INPUT ]] && echo "FILE [$INPUT] is not a valid file" && json_generator_usage && return 2
        IFS=$'\n' read -d '' -r -a objects_array < $INPUT
        JSON_OBJECT="\"$KEY\": $(json_object_array "${objects_array[@]}")"
        ;;
      'array' )
        [[ ! -f $INPUT ]] && echo "FILE [$INPUT] is not a valid file" && json_generator_usage && return 2
        declare -a lines
        while read line;do
          lines+=("$line");
        done < $INPUT
        JSON_OBJECT="\"$KEY\": $(json_array_from_file $INPUT)"
        ;;
      'file' )
        if [[ -f $INPUT ]]; then
          IFS=$'\n' read -d '' -r line < $INPUT
          JSON_OBJECT="\"$KEY\":\"${line//\"/\\\"}\""
        fi
        ;;
      'number' )
        JSON_OBJECT="\"$KEY\":${INPUT}"
        ;;
      'literal')
        JSON_OBJECT="\"$KEY\":\"${INPUT//\"/\\\"}\""
        ;;
      'nullvalue')
        JSON_OBJECT="\"$KEY\":${INPUT//\"/\\\"}"
        ;;
      'json_file')
        if [[ -f $INPUT ]]; then
          IFS=$'\n' read -d '' -r json < $INPUT
          JSON_OBJECT="\"$KEY\":${json}"
        fi
        ;;
      'boolean') # example: true, false
        JSON_OBJECT="\"$KEY\":${INPUT}"
			  ;;
        'objectsArrayParsing' )
          [[ ! -f $INPUT ]] && echo "FILE [$INPUT] is not a valid file" && json_generator_usage && return 2
          IFS=$'\n' read -d '' -r -a objects_array < $INPUT
          for i in "${objects_array[@]}"; do echo "{$i}" >> new_array ; done
          IFS=$'\n' read -d '' -r -a objects_array < new_array
          rm -rf new_array
          JSON_OBJECT="\"$KEY\": $(json_object_array "${objects_array[@]}")"
        ;;
      '*' ) echo "TYPE [$TYPE] is not a valid type" && json_generator_usage && return 3
        ;;
    esac
    # append a comma if there are more objects to append, close json otherwise
    [[ $# -gt 0 ]] && JSON_OBJECT="$JSON_OBJECT, " || JSON_OBJECT="$JSON_OBJECT }"

    # add object to json
    JSON=${JSON}${JSON_OBJECT}
  done

  echo "${JSON}"
}

# JSON objects generator with ServerId and JobId prefix
job_json_generator() {
  json_generator "$@" | sed "s/^{/{ \"ServerId\":${SERVER_ID}, \"JobId\":${JOB_ID}, /"
}

# JSON objects generator with ServerId and JobId prefix
data_json_generator() {
  local json_error=$1
  shift
  job_json_generator "$@" > ${atatempdir}/job-$$.json
  if [[ $json_error == "null" ]]; then
    json_generator ${atatempdir}/job-$$.json json_file Data | sed "s/^{ /{ \"HasError\":false, \"Error\":null, /"
  else
    json_generator ${atatempdir}/job-$$.json json_file Data | sed "s/^{ /{ \"HasError\":true, \"Error\":\"${json_error}\", /"
  fi
}
data_json_generator_iteration() {
  local json_error=$1
  shift
  json_generator "$@" > ${atatempdir}/job-$$.json
  if [[ $json_error == "null" ]]; then
     sed  "s/^{ /{ \"HasError\":false, \"Error\":null, \"StackTrace\":null, /" ${atatempdir}/job-$$.json
  else
    sed  "s/^{ /{ \"HasError\":true, \"Error\":${json_error}, \"StackTrace\":null, /" ${atatempdir}/job-$$.json
  fi
}
data_json_generator_hostname() {
  local json_error=$1
  shift
  json_generator "$@" | sed "s/^{/{ \"JobId\":${JOB_ID}, /" > ${atatempdir}/job-$$.json
  if [[ $json_error == "null" ]]; then
    json_generator ${atatempdir}/job-$$.json json_file Data | sed "s/^{ /{ \"HasError\":false, \"Error\":null, \"StackTrace\":null, /"
  else
    json_generator ${atatempdir}/job-$$.json json_file Data | sed "s/^{ /{ \"HasError\":true, \"Error\":\"${json_error}\", \"StackTrace\":null, /"
  fi
}
# wrapper for docker JSON object
docker_json_data() {
	DOCKER_INTERFACES_FILE=$atatempdir/DOCKER/DockerIfConfigToJSON.$$

  DOCKER_INFO=$(docker ps --format "{{.ID}};{{.Image}};{{.Status}};{{.Ports}};{{.Names}}" | grep "^$1")
  IFS=";"
  set -- $DOCKER_INFO # convert semi-colon separated values into variables
  unset IFS
  ContainerIpAddress=$(head -1 $atatempdir/DOCKER/IpConfig-${1}.txt | cut -d\- -f 1)
  ContainerId=$1
  ImageName=$2
  Status=$3
  [[ -z "$4" ]] && Ports="None" || Ports=$4
  Names=$5

  DockerCommand=$(docker inspect -f "{{.Path}} {{.Args}}" $1)
  Command=$(echo $DockerCommand | sed 's/\[\(.*\)\]$/\1/')

	cat /dev/null > $DOCKER_INTERFACES_FILE
  IFS=";"
  while read network_info; do
    set -- $network_info
    json_generator $1 literal Interface $2 literal IPAddress $3 literal Netmask $4 literal MACAddress >> $DOCKER_INTERFACES_FILE
  done < $atatempdir/DOCKER/IFConfig-$1.txt
  unset IFS

  # Generate fixed JSON_TEXT_OPTS for json_generator
  unset JSON_TEXT_OPTS
  for key in ContainerId ContainerIpAddress ImageName  Ports Names;do
    JSON_TEXT_OPTS="$JSON_TEXT_OPTS ${!key} literal $key"
  done

  # consider the scenario where DOCKER_INTERFACES_FILE is empty because $atatempdir/DOCKER/IFConfig-$1.txt did not get generated
  # JSON_TEXT_OPTS doesn't count as a single argument, it expands to multiple text key-value options
# [[ -s $DOCKER_INTERFACES_FILE ]] && data_json_generator null $JSON_TEXT_OPTS "$Command" literal Command "$Status" literal Status $DOCKER_INTERFACES_FILE objectsArray IfConfig DOCKER/SystemInfo-${ContainerId}.txt array SystemInfo
[[ -s $DOCKER_INTERFACES_FILE ]] && json_generator $JSON_TEXT_OPTS "$Command" literal Command "$Status" literal Status $DOCKER_INTERFACES_FILE objectsArray IfConfig DOCKER/SystemInfo-${ContainerId}.txt array SystemInfo
}

# wrapper for DiskInfo JSON object
diskinfo_json_data() {
	local json_error=$1
  DISKTYPEJSON="DiskType.json"
  cat /dev/null > $DISKTYPEJSON
  while read line; do
    disk=$(echo $line | cut -d' ' -f1)
    info=$(echo $line | cut -d' ' -f2-)
    if [[ -z $info ]];then
          info='null'
        else
          info="$info"
    fi
    if grep -iq $disk DiskInformation.txt ;then
      sed -i "/$disk/ s/$/,\"Caption\":\"$info\"/" DiskInformation.txt

    fi
  #  json_generator "$disk" literal DiskName "$info" literal DiskType >> $DISKTYPEJSON
  done < DiskType.txt

  #data_json_generator $json_error DiskPart.txt array Lines $DISKTYPEJSON objectsArray DiskTypeLines
  data_json_generator_iteration "$json_error" DiskInformation.txt objectsArrayParsing Data
}
validation_json_data() {
        local json_error=$1
        local inputfile=$2
  VALIDJSON="vali-$$.json"
  cat /dev/null > $VALIDJSON
  echo -n "{" > $VALIDJSON
  last_line=$(wc -l < $inputfile)
  current_line=0
  while read line; do
    Key=$(echo $line | awk -F ":" '{print $1}')
    Value=$(echo $line |  awk -F ":" '{$1=""; print $0}')
    current_line=$(($current_line + 1))
    if [[ $current_line -ne $last_line ]]; then
      echo -n "\"$Key\": \"$Value\", ">> $VALIDJSON
    else
      echo -n  "\"$Key\": \"$Value\"" >> $VALIDJSON
    fi
  done < $inputfile
  echo -n "}" >> $VALIDJSON
  data_json_generator $json_error $VALIDJSON objectsArray Data
}

error_check() {
  errorvalue=$1
  errorstring='null'
  fcount=$(echo $errorvalue | awk '{ print NF}')
  if [[ $fcount -gt 1 ]];then
    for i in $errorvalue;do
      grep -iq $i $log_file
      if [[ $? -eq 0 ]]; then
		    errorstring="\"ERROR\""
	    else
	  	  errorstring=$errorstring
      fi
    done
    strsize=$(echo $errorstring | wc -c)
    if [[ $strsize -gt 1 ]];then
      error=$errorstring
    else
      error='null'
    fi
  else
    grep -iq $errorvalue $log_file
    if [[ $? -eq 0 ]];then
      errorstring=$(grep -i $errorvalue $log_file | tail -1 | awk -F")" '{print $2}')
      error=\"$errorstring\"
    else
      error='null'
	 fi
 fi
}
#helper method to send info to the console
# updates JOB_STATUS when console response is false
send_data() {
  [[ -z $1 || -z $2 ]] && echo "URL and JSON_DATA arguments are required" && return 1
  URL=$1
  JSON_DATA=$2
  [[ -z $3 ]] && CURL_METHOD="POST" || CURL_METHOD=$3

  # some helper files
  JSON_FILE=$atatempdir/json_file.$$
  CURL_RESULT_FILE=$atatempdir/console_post.$$

  echo "Posting $JSON_DATA" | tee -a $json_log_file
  if [[ -f $JSON_DATA ]]; then
     cat $JSON_DATA > $JSON_FILE
  else
    echo $JSON_DATA > $JSON_FILE
  fi

  # discard curl standard output but save standard error if any
  # get http_code and check the result to determine if something happened from console side
  if [[ $JOB_NAME_ID -eq $DISCOVERY ]] &&  [[ $URL == $AFFINITY_BULK_URL ]]  ; then
    IDS="?jobId=$JOB_ID&serverId=$SERVER_ID&typeOfData=$TYPE_DATA&discoveryIteration=$DiscoveryCount"
  else
    IDS="?jobId=$JOB_ID&serverId=$SERVER_ID"
  fi

  if [ $CURL_FALLBACK -eq 0 ]; then
    HTTP_CODE=$($CURL -k -X $CURL_METHOD -H 'Content-Type: application/json' -S -s -d "@$JSON_FILE" ${CONSOLE_URL}${BASE_PATH}${URL}${IDS} -w %{http_code} -o $CURL_RESULT_FILE)
  else
    HTTP_CODE=$($CURL $CURL_METHOD "$JSON_FILE" ${CONSOLE_URL}${BASE_PATH}${URL}${IDS} $CURL_RESULT_FILE)
  fi

  if [[ $HTTP_CODE != "200" ]];then
    echo "($(date -u +'%m/%d/%Y %H:%M:%S)') Could not send data to ${CONSOLE_URL}${BASE_PATH}${URL}" | tee -a $log_file
    return 3
  fi
  if [[ $(cat $CURL_RESULT_FILE) == "false" ]];then
    echo "($(date -u +'%m/%d/%Y %H:%M:%S)') Unable to update ${URL} records in database" | tee -a $log_file
    JOB_STATUS=$FAILED
    return 2
  fi
  [[ $CURL_METHOD == "POST" ]] &&  echo "($(date -u +'%m/%d/%Y %H:%M:%S)') Successfully sent data to ${CONSOLE_URL}${BASE_PATH}${URL}" | tee -a $log_file

}

variable_definition() {
  # arguments assignment
  SERVER_ID=$1
  JOB_ID=$2
  CONSOLE_URL=$3
  [[ $# -gt 3 ]] && HOURS=$4 || HOURS=0
  [[ $# -gt 4 ]] && INTERVAL=$5 || INTERVAL=15
  [[ $# -gt 5 ]] && DISCOVERY_FAIL_THRESHOLD=$6 || DISCOVERY_FAIL_THRESHOLD=50
  [[ $# -gt 6 ]] && WEBDISCOVERY=$7 || WEBDISCOVERY='False'
  [[ $# -gt 7 ]] && DISCOVERYTYPES=$8 || DISCOVERYTYPES="NORMAL"
  [[ $# -gt 8 ]] && DISKGROWTHINTERVAL=$9 || DISKGROWTHINTERVAL=0
  ((SECS_INTERVAL=INTERVAL*60))

  DISCOVERYTYPE=$(echo $DISCOVERYTYPES | tr [:lower:] [:upper:])
  # export paths to reach the binaries in case of SUDO
  export PATH=$PATH:/usr/sbin:/sbin

  # set the variables
  DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  atatempdir="$DIR/atadataoutput"
  webserverdir="${atatempdir}/WEB/"
  stepfile="${DIR}/step.out"
  usr=$(id -nu)
  FAILPRE=Prechecks_FAILEDLog.txt
  FAILPREMIG=Prechecks_FAILEDLog_MIG.txt
  [[ $HOURS -ne 0 ]] && REPEATS=$(($HOURS*60/$INTERVAL)) || REPEATS=0
  R=1
  LOCK_FILE=${atatempdir}/discovery.pid
  CURL=$(which curl)

  #adding variables for diskgrowth

  if [ $DISKGROWTHINTERVAL -gt 0 ]; then
    RunsPerHour=$((60/$INTERVAL))
    RunsPerDay=$((24*$RunsPerHour))
    DiskIterVal=$(($RunsPerDay*$DISKGROWTHINTERVAL))
  fi

  JOB_ERROR_DESCRIPTION="null"

  RUNNING=0

  # Job statuses validation
  SUCCESS=1
  FAILED=3

  # job statuses discovery
  SCAN_COMPLETE=5
  DISCOVERY_ERROR=6


  # Initial job status
  JOB_STATUS=$RUNNING

  # Job names
  VALIDATION=1
  DISCOVERY=2

  # determine job name
  [[ $HOURS -eq 0 ]] && JOB_NAME_ID=$VALIDATION || JOB_NAME_ID=$DISCOVERY

  BASE_PATH="/api/"
  VALIDATIONFACTORS_URL="Host/ValidationFactors"
  CONNECTION_URL="MigrationJob/CheckConsoleConnection"
  DATA_COLLECTION_BULK_URL="Host/BulkDataCollection"
  AFFINITY_BULK_URL="Discovery/BulkDataCollection"
  JOBEVENT_STATUS_URL="Discovery/UpdateJobEventStatus"
  JOBEVENT_PAUSE_STATUS_URL="Discovery/UpdateJobStatusPaused"
  JOBEVENT_RESUME_STATUS_URL="Discovery/UpdateJobStatusResumed"

  if [[ $JOB_NAME_ID -eq $VALIDATION ]]; then
    JOB_COMPLETION_URL="Host"
    LOG_NAME="validation"
  else
    LOG_NAME="discovery"
    JOB_COMPLETION_URL="Discovery"
  fi

  log_file=${atatempdir}/${LOG_NAME}-${JOB_ID}-logs-$(date +%Y%m%d).txt
  full_log_file=${atatempdir}/${LOG_NAME}-${JOB_ID}-logs_full-$(date +%Y%m%d).txt
  json_log_file="${atatempdir}/json-${JOB_ID}-log-$(date +%Y%m%d).txt"
	json_error="${atatempdir}/json-${JOB_ID}-error-$(date +%Y%m%d).txt"

}

# Check if curl works with https or has ssl issues, then replace it with go alternative
curl_ssl_test() {
  CURL_FALLBACK=0
  mv ${DIR}/discoverylinuxCurl ${atatempdir}/
  if echo $CONSOLE_URL | grep -q "https://"; then
    $CURL ${CONSOLE_URL}${BASE_PATH}healthcheck -k
    if [ $? -eq 35 ]; then
      echo "Cannot communicate to the console, trying with TLSv1" | tee -a $log_file
      #doing one more test just in case curl is not using higher tls by default
      $CURL ${CONSOLE_URL}${BASE_PATH}healthcheck -k -tls1
      if [ $? -ne 0 ]; then
        echo "replacing curl with golang binary due to SSL/TLS issue" | tee -a $log_file
        CURL="${atatempdir}/discoverylinuxCurl"
        CURL_FALLBACK=1
      else
        echo "Communication to the console via TLSv1 is successful" | tee -a $log_file
      fi
    fi
  fi
}
offline_discovery() {
  if [ $CURL_FALLBACK -eq 0 ]; then
    HTTP_CODE=$($CURL -k -X GET  ${CONSOLE_URL}${BASE_PATH}${CONNECTION_URL} -s -w %{http_code} -o $CURL_RESULT_FILE)
  else
    HTTP_CODE=$($CURL GET  ${CONSOLE_URL}${BASE_PATH}${CONNECTION_URL} $CURL_RESULT_FILE)
  fi
  if [[ $HTTP_CODE != "200" ]] ||  [[ $(cat $CURL_RESULT_FILE) == "false" ]]  ; then
    echo "Hostapi is offline and the iteration data is backing up" | tee -a $log_file
    Mdate=$(date +%s)
    cp $discovery_bulk_json $atatempdir/OFFLN/discovery_bulk_iter_${R}_${Mdate}.json
  elif [[ ! -z "$(ls -A $atatempdir/OFFLN/)" ]]; then
    echo "Hostapi connection is back, sending iteration data from backup" | tee -a $log_file
    for i in $(find ${atatempdir}/OFFLN/ -type f ); do
      TYPE_DATA=2
			DiscoveryCount=$R
      send_data $AFFINITY_BULK_URL $i
      mv $i ${atatempdir}/OFFLNBACKUP #directory created for manual discovery. but now this is for just backing up the data after sending.
    done
  fi
}
#perform pre checks before any
validation_process() {

  ################################################################################
  # Start Pre-checks

  echo "******************" | tee -a $log_file
  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Performing Pre-checks" | tee -a $log_file
  echo "******************" | tee -a $log_file


  #echo "OS: $OS" >> $atatempdir/$FAILPRE  cancelled as per the new requirements
  #echo "HOSTNAME: `hostname`" >> $atatempdir/$FAILPR
  #echo "Context: VALIDATION" >> $atatempdir/$FAILPRE
  echo ""

  #Check the locale information and change it back to english if it's not
  if [[ $LANG != "en_US.UTF-8" ]]; then
          export LANG=en_US.UTF-8
  fi

  #Check if server has cciss mounted
  if df -h | grep -i cciss; then
  	grepvar="grep -v "p[0-9]"| cut -d "/" -f2"
  else
  	grepvar="grep -v [0-9]$"
  fi
  #get_distro

  # Script should return short name for each distribution
  # for Centos/RHEL el5, el6, el7
  # For Ubuntu ubuntu12.04, ubuntu14.04
  # For debian deb7, deb8
  # for SuSE sles11.3, sles11.2, opensuse13.1
  # For Amazon Linux AMI, amzn2016.03, amzn2015.03
  # For Fedora fc24, fc23, fc22

  version=""
  if [ -f /etc/redhat-release ]; then
  	if [ -f /etc/centos-release ]; then
  		if cat /etc/centos-release |grep -iq linux; then
  			 version="el`cat /etc/centos-release | cut -d " " -f 4 | cut -d "." -f 1`"
  			 ver=`cat /etc/centos-release | cut -d " " -f 4|awk -F "." '{ print $1"."$2}'`
  		else
  			version="el`cat /etc/centos-release | cut -d " " -f 3 | cut -d "." -f 1`"
  			ver=`cat /etc/centos-release | cut -d " " -f 3|awk -F "." '{ print $1"."$2}'`
  		fi
  	else
  		if cat /etc/redhat-release |grep -iq fedora;then
  			version="fc`cat /etc/redhat-release | cut -d " " -f 3`"
  		elif cat /etc/redhat-release | grep -iq centos;then
  				 version="el`cat /etc/redhat-release |cut -d " " -f 3 | cut -d "." -f 1`"
  				 ver=`cat /etc/redhat-release |cut -d " " -f 3|awk -F "." '{ print $1"."$2}'`
  		else
  				 version="el`cat /etc/redhat-release | cut -d " " -f 7 | cut -d "." -f 1`"
  				 ver=`cat /etc/redhat-release | cut -d " " -f 7| cut -d "." -f 2|awk -F "." '{ print $1"."$2}'`
  		fi
  	fi
  fi

  if [ -f /etc/os-release ]; then
  	if cat /etc/os-release |grep -wq "sles" || cat /etc/os-release |grep -wq "opensuse" || cat /etc/os-release |grep -wq "Debian" || cat /etc/os-release |grep -wq "Ubuntu" || cat /etc/os-release |grep -wq "amzn"; then
  		if cat /etc/os-release |grep -wq "Leap"; then
  			version_id=`cat /etc/os-release|grep -w "VERSION_ID"|awk -F"=" '{print $2}'|sed 's/"//g'`
  			id=`cat /etc/os-release|grep -w "ID"|awk -F"=" '{print $2}'|sed 's/"//g'`
  			version=$id$version_id"Leap"
  		else
  			version_id=`cat /etc/os-release|grep -w "VERSION_ID"|awk -F"=" '{print $2}'|sed 's/"//g'`
  			id=`cat /etc/os-release|grep -w "ID"|awk -F"=" '{print $2}'|sed 's/"//g'`
  			version="$id$version_id"
  		fi
  	fi
  elif [ -f /etc/debian_version ]; then
  	version="debian`cat /etc/debian_version|cut -d"." -f1`"
  fi

  if [ -f /etc/system-release ] && [ ! -f /etc/redhat-release ] && [ ! -f /etc/centos-release ] && [ ! -f /etc/os-release ]; then
  	 version="amzn`cat /etc/system-release | cut -d " " -f 5`"
  fi
  distro=$version

  #Check SUDO
  id=`id -u`
  if [[ $id -ne 0 ]]; then
  	which dzdo > /dev/null 2>&1
  	if [ $? -eq 0 ]; then
  		SUDO=$(which dzdo)
  		$SUDO crontab -l -u root
  		if [ $? != 0 ]; then
        $SUDO crontab -l -u root  2>$atatempdir/err.txt
        grep -iq "no crontab for root" $atatempdir/err.txt
        if [ $? -ne 0 ];then
          unset SUDO
        fi
  		fi
  	fi

  	which pbrun > /dev/null 2>&1
  	if [ $? -eq 0 ] && [ -z $SUDO ]; then
  		SUDO=$(which pbrun)
  		$SUDO crontab -l -u root
  		if [ $? != 0 ]; then
        $SUDO crontab -l -u root  2>$atatempdir/err.txt
        grep -iq "no crontab for root" $atatempdir/err.txt
        if [ $? -ne 0 ];then
          unset SUDO
        fi
      fi
  	fi

    which suexec > /dev/null 2>&1
    if [ $? -eq 0 ] && [ -z $SUDO ]; then
      SUDO=$(which suexec)
      $SUDO crontab -l -u root
      if [ $? != 0 ]; then
        $SUDO crontab -l -u root  2>$atatempdir/err.txt
        grep -iq "no crontab for root" $atatempdir/err.txt
        if [ $? -ne 0 ];then
          unset SUDO
        fi
      fi
    fi
    if [ -z $SUDO ]; then
      which sudo > /dev/null 2>&1
  	  if [ $? != 0 ]; then
  		  unset SUDO
  	  else
  		  SUDO=$(which sudo)
  		  #Check inside sudoers.d for user, all this because grep /* does not work with sudo inside sudoers.d since it opens new shell and does not have permissions
  		  cnt=0
  		  cntn=0
  		  cntd=0
  		  found=0
  		  # These if statements will check if there is an alias for $usr on sudoers and/or sudoers.d
  	  	# If there is, that alias will be used to check if there is a NOPASSWD for that alias.
  		  # Otherwise, the user will be used.
        $SUDO -ll > ${atatempdir}/SudoCommandList.txt
        # If 0, !requiretty is set, either by default or explicit in sudoers file
        notty=$?

        # to not allow any kind of sudo configuration to not escape permission issue.
        $SUDO passwd -S root
        nosudo=$?

  		  if [ $($SUDO cat /etc/sudoers | grep -w $usr | grep -v "^#" |  wc -l) -gt 0 ]; then
  			  usralias=$($SUDO cat /etc/sudoers | grep -w $usr | grep -w User_Alias | grep -v "^#" | awk '{print $2}' | head -1 )
  			  if [ ! -z $usralias ]; then
  				  echo "******************" | tee -a $log_file
  				  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) $usralias is the alias for $usr (sudoers)" | tee -a $log_file
  				  echo "******************" | tee -a $log_file
  			  fi
  		  else
  			  for i in `$SUDO ls /etc/sudoers.d`; do
  				  if [ $found != "1" ]; then
  					  if [ $($SUDO cat /etc/sudoers.d/$i | grep -w $usr | grep -v "^#" |  wc -l) -gt 0 ]; then
  						  usralias=$($SUDO cat /etc/sudoers.d/$i | grep -w $usr | grep -w User_Alias | grep -v "^#" | awk '{print $2}' | head -1 )
  						  if [ ! -z $usralias ]; then
  							  echo "******************" | tee -a $log_file
  							  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) $usralias is the alias for $usr (/etc/sudoers.d/$i)" | tee -a $log_file
  							  echo "******************" | tee -a $log_file
  							  found=1
  							  break
  						  fi
  					  fi
  				  fi
  			  done
  		  fi
  	  fi

  	  if [ -z $usralias ]; then
  		  usralias=$usr
  	  fi
  	  for i in `$SUDO ls /etc/sudoers.d`; do
  		  if $SUDO cat /etc/sudoers.d/$i | grep -w $usralias|grep -vq "^#"; then
  			  cnt=$((cnt+1))
  			  if $SUDO cat /etc/sudoers.d/$i | grep -v "^#" | grep -w $usralias | grep NOPASSWD; then
  				  cntn=$((cntn+1))
  				  if [ "$($SUDO cat /etc/sudoers.d/$i |grep -v "^#"| grep -i 'defaults.*\!requiretty')" ]; then
  					  cntd=$((cntd+1))
  				  fi
  			  fi
  		  fi
  	  done
  	  if $SUDO cat /etc/sudoers | grep -v "^#" | grep -w $usralias || [ $cnt != 0 ]; then
  		  if $SUDO cat /etc/sudoers | grep -v "^#" | grep -w $usralias | grep NOPASSWD || [ $cntn != 0 ]; then
  			  if [ "$($SUDO cat /etc/sudoers | grep -v "^#" | grep -i 'defaults.*\!requiretty')" ] || [ $cntd != 0 ] || [ $notty -eq 0 ]; then
  				  echo "******************" | tee -a $log_file
  				  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) SUDO is correctly configured for user $usr" | tee -a $log_file
  				  echo "******************" | tee -a $log_file
  			  else

  				  echo "SUDO profile HAS NOT 'Default !requiretty' configured" >> $atatempdir/$FAILPRE
  				  echo "Error: User does not have required privilege to collect all the data elements. SUDO profile HAS NOT 'Default !requiretty' configured. Script will continue to run" | tee -a $log_file
  			  fi
  		  else
  			  echo "SUDO needs to be configured with NO PASSWD for user $usr" >> $atatempdir/$FAILPRE
  			  echo "Error: User does not have required privilege to collect all the data elements. SUDO needs to be configured with NO PASSWD for user $usr .Script will continue to run" | tee -a $log_file
  		  fi
  	  elif cat /etc/nsswitch.conf | grep -v "^#"| grep sudoers|grep -i ldap || cat /etc/nsswitch.conf | grep -v "^#"| grep sudoers|grep -i sss; then
  		  #We check which method is being used by sudo if it is the file /etc/sudoers or if it is ldap
  		  #We do it this way because the sudoers file can be used but not specified in the nsswitch.conf file
  		  #nsswitch.conf file can have more than one entry, it can have files or ldap or sss and use all of them

  		  #We validate the LDAP entries
  		  if cat ${atatempdir}/SudoCommandList.txt | grep -i '!authenticate' || grep -i 'NOPASSWD' ${atatempdir}/SudoCommandList.txt ; then
  			  if  cat ${atatempdir}/SudoCommandList.txt | grep -i '!requiretty' || [ $notty -eq 0 ]; then
  				  echo "******************" | tee -a $log_file
  				  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) SUDO is correctly configured for user $usr" | tee -a $log_file
  				  echo "******************" | tee -a $log_file
  			  else
  				  echo "SUDO profile HAS NOT '!requiretty' configured" >> $atatempdir/$FAILPRE
  				  echo "Error: User does not have required privilege to collect all the data elements. Script will continue to run" | tee -a $log_file

  			  fi
  		  else
  			  echo "SUDO needs to be configured with NO PASSWD for user $usr" >> $atatempdir/$FAILPRE
  			  echo "Error: User does not have required privilege to collect all the data elements. Script will continue to run" | tee -a $log_file

  		  fi
    	else
  	  	grpsc=0
  		  grpsr=0
  		  grpsp=0
  		  for group in `groups`; do
  			  if $SUDO cat /etc/sudoers | grep -v "^#" | grep -w $group; then
  				  if $SUDO cat /etc/sudoers | grep -v "^#" | grep -w $group | grep NOPASSWD; then
  					  if [ "$($SUDO cat /etc/sudoers | grep -v "^#" | grep -i 'defaults.*\!requiretty')" ]; then
  						  grpsc=1
  					  else
  						  grpsr=1
  					  fi
  				  else
  					  grpsp=1
  				  fi
  			  fi
  		  done
  		  if [ $grpsc -eq 1 ] || [ $notty -eq 0 ] && [ $nosudo -eq 0 ]; then
  			  echo "******************" | tee -a $log_file
  			  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) SUDO is correctly configured for user $usr" | tee -a $log_file
  			  echo "******************" | tee -a $log_file
  	  	elif [ $grpsr -eq 1 ] || [ $notty -eq 1 ] || [ $nosudo -eq 1 ]; then
  		  	echo "SUDO profile HAS NOT 'Default !requiretty' configured for user $usr in group $group" >> $atatempdir/$FAILPRE
  			  echo "Error: User does not have required privilege to collect all the data elements. SUDO profile HAS NOT 'Default !requiretty' configured. Script will continue to run" | tee -a $log_file
  		  elif [ $grpsp -eq 1 ]; then
  			  echo "SUDO needs to be configured with NO PASSWD for user $usr in group" >> $atatempdir/$FAILPRE
  			  echo "Error: User does not have required privilege to collect all the data elements. SUDO needs to be configured with NO PASSWD for user $usr .Script will continue to run" | tee -a $log_file
  		  fi
  	  fi

  	  #This will check the sudoers.d and sudoers configuration to see if there are more than one line present for the required user.
    	sudoersdlines=$($SUDO cat /etc/sudoers.d/$i | grep -w $usr|grep -cv "^#")
  	  sudoerslines=$($SUDO cat /etc/sudoers | grep -w $usr|grep -cv "^#")
  	  if [ $sudoersdlines -gt "1" ] || [ $sudoerslines -gt "1" ]; then
  		  echo "******************" | tee -a $log_file
  		  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING: There are more than one line present for $usr on the sudo configuration." | tee -a $log_file
  		  echo "******************" | tee -a $log_file
  	  fi
   fi
 fi
  #this is the portion for sudo,dzdo,pbrun,suexec
  id=`id -u`
  if [[ $id -ne 0 ]] ; then
    if [[ -z $SUDO ]]; then
      echo "Sudo $SUDO User does not have required privilege to collect all the data elements. Please check your SUDO, DZDO, PBRUN or suexec configuration" >> $atatempdir/$FAILPRE
      echo "Error: User does not have required privilege to collect all the data elements. Script will continue to run" | tee -a $log_file
    else
      $SUDO crontab -l -u root
      if [ $? != 0 ]; then
        $SUDO crontab -l -u root  2>$atatempdir/err.txt
        grep -iq "no crontab for root" $atatempdir/err.txt
        if [ $? -ne 0 ];then
          echo "Sudo $SUDO User does not have required privilege to collect all the data elements. Please check your SUDO, DZDO, PBRUN or suexec configuration" >> $atatempdir/$FAILPRE
        fi
      fi
    fi
  fi

  #Check if the PATHs are configured correctly
  PATHREQ=0
  for i in $(echo $PATH | tr ":" "\n")
  do
    if [ "$i" = "/usr/sbin" ]  || [ "$i" = "/sbin" ]; then
      PATHREQ=$((PATHREQ+1))
    else
      PATHREQ=$((PATHREQ+0))
    fi
  done
  if [ $PATHREQ -gt 0 ]; then
    echo " Path has a CORRECT setting" > /dev/null 2>&1
  else
    #echo "ATAvision | Path NEEDS to be exported" >> $atatempdir/$FAILPRE
		echo "Path NEEDS to be exported" >> $atatempdir/$FAILPRE

  fi


  #Check the filesystems requirements
  avspacetmp=`df -k $DIR | awk '!/Used/ {print $4}'`
  if [ $avspacetmp -lt 204800 ]; then
    #echo "ATAvision | The Filesystem where the tool is executed doesn't have 200 Mb free space" >> $atatempdir/$FAILPRE
    #echo "ATAmotion | The Filesystem where the tool is executed doesn't have 200 Mb free space" >> $atatempdir/$FAILPRE
		echo "The Filesystem where the tool is executed does not have 200 Mb free space" >> $atatempdir/$FAILPRE
    echo "The Filesystem where the tool is executed does not have 200 Mb free space" >> $atatempdir/$FAILPRE
  fi

  #Check if the required packages are installed
  pcurl=0
  pnc=0
  which curl > /dev/null 2>&1
  if [ $? != 0 ]; then
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING ATAmotion| curl is NOT installed" | tee -a $log_file
  	echo "******************" | tee -a $log_file
    pcurl=1
  fi

  #Checking access against repositories using curl
  os=$distro
  rep1=0
  if [ $pcurl -eq 0 ]; then
  	if [[ $os = el* ]]; then
  		for repo in `yum repolist -v 2>/dev/null | grep Repo-mirrors | awk '{print $3 }'`; do
  			if curl --connect-timeout 5 -s $repo --insecure > /dev/null ; then
  				echo "OK : $repo is accessible "
  			else
  				echo "******************" | tee -a $log_file
  				echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING ATAmotion | $repo is NOT accessible." | tee -a $log_file
  				echo "******************" | tee -a $log_file
  				rep1=1
  			fi
  		done
  	fi
  	if [[ $os == *suse* ]] || [[ $os == *sles* ]]; then
  		for repo in `zypper lr -u 2>/dev/null | awk '{print $11 }' | grep -v URI 2>/dev/null`; do
  			if curl --connect-timeout 5 -s $repo --insecure > /dev/null ; then
  				echo "OK : $repo is accessible "
  			else
  				echo "******************" | tee -a $log_file
  				echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING ATAmotion | $repo is NOT accessible." | tee -a $log_file
  				echo "******************" | tee -a $log_file
  				rep1=1
  			fi
  		done
  	fi
  	if [[ $os == *deb* ]] || [[ $os == *ubuntu* ]]; then
  		#Creating repolist
  		> $PWD/repo_debian
  		grep -ir -h ^deb /etc/apt/sources.list.d/* 2> /dev/null | awk '{print $2}' >> $PWD/repo_debian
  		grep -ir -h ^deb /etc/apt/sources.list 2> /dev/null | awk '{print $2}' >> $PWD/repo_debian
  		for repo in `cat $PWD/repo_debian`; do
  			if curl --connect-timeout 5 -s $repo --insecure > /dev/null ; then
  				echo "OK : $repo is accessible "
  			else
  				echo "******************" | tee -a $log_file
  				echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING ATAmotion | $repo is NOT accessible." | tee -a $log_file
  				echo "******************" | tee -a $log_file
  				rep1=1
  			fi
  		done
  	fi
  fi

  which killall > /dev/null 2>&1
  if [ $? != 0 ]; then
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING ATAmotion| psmisc is NOT installed" | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	if [[ $rep1 -eq 1 ]]; then
  		echo "psmisc is NOT installed" >> $atatempdir/$FAILPREMIG
  	fi
  fi
  which rsync > /dev/null 2>&1
  if [ $? != 0 ]; then
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING ATAmotion| rsync is NOT installed" | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	if [[ $rep1 -eq 1 ]]; then
  		echo "rsync is NOT installed" >> $atatempdir/$FAILPREMIG
  	fi
  fi
  which nc > /dev/null 2>&1
  if [ $? != 0 ]; then
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) WARNING ATAmotion| netcat is NOT installed" | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	if [[ $rep1 -eq 1 ]]; then
  		echo "nc is NOT installed" >> $atatempdir/$FAILPREMIG
  	fi
  	pnc=1
  fi
  #if [[ "${DISCOVERYTYPE}" == "MANUAL" ]]; then
  #  Mdate=$(date +%s)
  #  echo "$(job_json_generator $FAILPRE array Lines)" > ${atatempdir}/MANUAL/Prechecks_${Mdate}_00.json
  #else
    #validationcheck
  #  send_data $VALIDATIONFACTORS_URL "$(job_json_generator $FAILPRE array Lines)"
  if [[ $JOB_NAME_ID -eq $DISCOVERY  ]]; then
    send_data $JOBEVENT_STATUS_URL "$(job_json_generator  40 number DiscoveryStatus 39 number DiscoveryLastStatus null nullvalue ErrorDescription 0 number IterationProgressPercent)"
  fi
  #id=`id -u`
  #if [[ $id -ne 0 ]];then
    #sudocmd=$(echo $SUDO |  awk -F "/" '{print $NF}')
    #grep -iq "Text" $FAILPRE
    #if [[ $? -eq 0 ]]; then
    #  error="Error"
    #  validation_json_data $error $FAILPRE >$atatempdir/data-$$.json
    #  json_generator $atatempdir/data-$$.json json_file Precheck_Host >  $atatempdir/JSON/Precheck_Host.json
    #else
    #  error="null"
    #  validation_json_data $error $FAILPRE >$atatempdir/data-$$.json
    #  json_generator $atatempdir/data-$$.json json_file Precheck_Host > $atatempdir/JSON/Precheck_Host.json
    #fi
  #else
  #  error="null"
  #  validation_json_data $error $FAILPRE >$atatempdir/data-$$.json
  #  json_generator $atatempdir/data-$$.json json_file Precheck_Host > $atatempdir/JSON/Precheck_Host.json
  #fi
    #send_data $VALIDATIONFACTORS_URL
    awk '{print "\"ValidationLog\":\""$0"\",\"AffectedJobType\":2"}' $atatempdir/$FAILPRE > failpre-logs.txt
    awk '{print "\"ValidationLog\":\""$0"\",\"AffectedJobType\":3"}' $atatempdir/$FAILPREMIG >> failpre-logs.txt

    if [[ -s $FAILPRE ]] || [[ -s $FAILPREMIG ]] ; then
      error="null"
      data_json_generator_iteration null failpre-logs.txt objectsArrayParsing Data >$atatempdir/precheck-$$.json
    #  data_json_generator_iteration $error $atatempdir/precheck-$$.json json_file Data > $atatempdir/data-$$.json
      json_generator $atatempdir/precheck-$$.json json_file ServerValidationStatus >  $atatempdir/JSON/ServerValidationStatus.json
    else
      error="null"
      touch $atatempdir/precheck-$$.json
      data_json_generator_iteration $error $atatempdir/precheck-$$.json objectsArrayParsing Data > $atatempdir/data-$$.json
      json_generator $atatempdir/data-$$.json json_file ServerValidationStatus >  $atatempdir/JSON/ServerValidationStatus.json
    fi
  #else

  #  error="null"
  #  echo "" >$atatempdir/precheck-$$.json
  #  data_json_generator_iteration $error $atatempdir/precheck-$$.json objectsArrayParsing Data > $atatempdir/data-$$.json
  #  json_generator $atatempdir/data-$$.json json_file ServerValidationStatus >  $atatempdir/JSON/ServerValidationStatus.json
  #fi
  #fi
}

data_collection() {
  ################################################################################
  # Start validation process

  echo "******************" | tee -a $log_file
  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Getting inventory information..." | tee -a $log_file
  echo "******************" | tee -a $log_file


  #ARP data
  which arp > /dev/null 2>&1
  if [ $? = 0 ]; then
  	arp -a >> arp.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EARP: Error retrieving ARP information: command arp not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch arp.txt 2>&1
  fi

  #PRTCONF data
	if which dmidecode >/dev/null 2>&1; then
		$SUDO dmidecode | grep -wv ^Last >> ComputerSystemProduct.txt
	  if [[ $? -ne 0 ]]; then
	    echo "******************" | tee -a $log_file
			echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EDMI: Error retrieving computer system information: Command dmidecode is failing" | tee -a $log_file
			echo "******************" | tee -a $log_file
			touch ComputerSystemProduct.txt
	  fi
	elif which hwinfo >/dev/null 2>&1; then
		$SUDO hwinfo | grep -wv ^Last >> ComputerSystemProduct.txt
	  if [[ $? -ne 0 ]]; then
	    echo "******************" | tee -a $log_file
	    echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EDMI: Error retrieving computer system information: Command dmidecode is missing and hwinfo is failing" | tee -a $log_file
	    echo "******************" | tee -a $log_file
	    touch ComputerSystemProduct.txt
	  fi
	else
		echo "******************" | tee -a $log_file
		echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EDMI: Error retrieving computer system information: Command dmidecode or hwinfo not found." | tee -a $log_file
		echo "******************" | tee -a $log_file
		touch ComputerSystemProduct.txt
	fi

  #DISK information
  #SAN

  lsblk > /dev/null 2>&1
  statuslsblk=$?
  touch $atatempdir/dismapth.tmp
  if [ "$statuslsblk" == '0' ]; then
    #List all disks first except powerpath, then list powerpath
    for grepopt in -iv -i; do
    	for disko in `$SUDO lsblk -n --nodeps -o NAME |grep $grepopt emcpower | grep -v 'dm-' |grep -v loop| grep -iv ram| grep -vi mapper|grep -iv "^sr"|grep -iv "^fd"`; do
    		diskmapth=`$SUDO multipath -l /dev/${disko}`
    		mpathstate=$?
    		if [ $mpathstate -eq 0 ];then
    			diskmapth=`$SUDO multipath -l /dev/${disko}| head -1 | awk '{print $1}'`
    			if [ -z $diskmapth ]; then
    				diskmapth="samandruli"
    			fi
    		else
    			diskmapth="samandruli"
    		fi
    		if [ $diskmapth == "samandruli" ] || ! grep $diskmapth $atatempdir/dismapth.tmp; then
    			echo $disko
    			#Check if pvs is present
    			$SUDO pvs > /dev/null 2>&1
    			if [ $? -eq 0 ];then
    				#if lvm is present check if the disk are in lvm
    				pvsym=0
    				disksym="`ls -l /dev |grep -w "${disko}"| grep ^l | awk '{print $9}'`"
    				if [ ! -z $disksym ]; then
    					if $SUDO pvs -o pv_name| grep -v PV | grep -w $disksym ; then
    						pvsym=1
    					fi
    				fi
    				pvluks=0
    				#if blkid | grep $disko | grep -i crypto_LUKS; then
    				#	for i in `blkid | grep $disko| grep crypto_LUKS| awk -F "UUID" '{print $2}'| awk -F\" '{print $2}'`; do
    				#		diskluk=`$SUDO pvs -o pv_name| grep -v PV |grep -i $i`
    				#		if [ ! -z $diskluk ]; then
    				#			if $SUDO pvs -o pv_name| grep -v PV | grep -w $diskluk ; then
    				#				pvluks=$((pvluks+1))
    				#			fi
    				#		fi
    				#	done
    				#fi
    				pvmpath=0
    				if [ $diskmapth != "samandruli" ]; then
    					echo $diskmapth >> $atatempdir/dismapth.tmp
    					if $SUDO pvs -o pv_name| grep -v PV | grep -w $diskmapth ; then
    						pvmpath=1
    					fi
    				fi

    				if $SUDO pvs |grep -iq $disko || [ $pvsym == "1" ] || [ $pvluks != "0" ] || [ $pvmpath == "1" ]; then
    					#if the disk use lvm proceed
    					size="`cat /proc/partitions | grep -w $disko | awk '{print $3}'`"
    					usedsize=0
    					if [ $pvluks != "0" ]; then
    						lukUUID=`blkid | grep $disko| grep crypto_LUKS| awk -F "UUID" '{print $2}'| awk -F\" '{print $2}'`
    						pvdisk=`$SUDO pvs -o pv_name| grep -v PV |grep -i $lukUUID`
    					else
    						if [ $pvmpath == "1" ]; then
    							disko=$diskmapth
    						fi
    						pvdisk=`$SUDO pvs -o pv_name| grep -v PV |grep -i $disko`
    						lukUUID="samandruli"
    					fi
    					echo $pvdisk
    					#check if pvs disk are not used
    					if [ `lsblk $pvdisk -ibr -o name,size|grep -v NAME |wc -l` -eq 1 ]; then
    						#disk only configured with pvs but not used
    						#the disk have partion pvs like /dev/sda or /dev/sda1
    						#In this case we put the total of disk because
    						#console copy this disk as raw device
    						usedsize=$size
    					else
    						#Check used size of each PV in KB
    						usedsize=`$SUDO pvs --noheadings -o pv_used --units k $pvdisk | awk '{sum += $1} END {print sum}'`
    					fi

              # The underlying for loop was added for the multipath fix & the if loop following that
              #When fixed disk have partition
              pvdisk=`$SUDO pvs -o pv_name| grep -v PV |grep -i $disko`
              pvdiskexc=$(echo ${pvdisk##*/})
              for fixeddisks in `lsblk /dev/$disko -ibr -o name,size,type|grep -v NAME|grep -wv $disko| grep -iv lvm | grep -iwv $pvdiskexc | awk '{print $1}'`;
              do
                #take each fixed disk partitioned and control if are mounted or not

                mountdisk=`lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'`
                if  lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME|grep -wv ${diskmapth}| awk '{print $3}'|grep -q '/'; then
                  #When disk are mounted
                  mountpointdisk=`lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'`
                  mpointdisk_wc=$(echo $mountpointdisk | wc -w)
                    if [ $mpointdisk_wc -eq 1 ] && [ $mpathstate -ne 0 ]; then
                      #fixeddiskspace=`df -P $mountpointdisk |grep -v Used| awk '{print $3}'`
                      kbytesfixedspace=`lsblk /dev/$fixeddisks -ibr -o size|grep -v SIZE|head -1`
                      fixeddiskspace=`expr $kbytesfixedspace / 1024`
                      sizepartial=$fixeddiskspace
                    else
                    sizepartial=0
                    fi
                else
                  #When disk is not  mounted
                  if echo $fixeddisks | grep -ivq mapper; then
                    kbytesfixedspace=`lsblk /dev/$fixeddisks -ibr -o size|grep -v SIZE|head -1`
                    fixeddiskspace=`expr $kbytesfixedspace / 1024`
                    sizepartial=$fixeddiskspace
                  else
                    sizepartial=0
                  fi
                fi
                usedsize="`expr $usedsize + $sizepartial`"
              done

              if [ ! -z $diskmapth ] && [ $diskmapth != "samandruli" ]; then
    						disko=$diskmapth
    						mpath_layout="${mpath_layout}${disko};${size};${usedsize}|"
    					else
    					  layout_console="${layout_console}${disko};${size};${usedsize}|"
    					fi

            else
    					#Here enter when pvs is installed but the disk in loop is not lvm
    					size="`cat /proc/partitions | grep -w $disko | awk '{print $3}'`"
    					usedsize=0
    					if [ `lsblk /dev/$disko -ibr -o name,size|grep -v NAME |grep -v ${diskmapth}|wc -l` -eq 1 ]; then
    							#here enter when pvs is installed but the disk in loop do not have partition defined
    						if  lsblk /dev/$disko -o name,size,mountpoint -ibr|grep -v NAME|grep -v ${diskmapth}| awk '{print $3}'|grep -q /; then
    							#When disk are mounted and do not have partition defined
    							mountpointdisk=`lsblk /dev/$disko -o name,size,mountpoint -ibr|grep -v NAME|grep -v ${diskmapth}| awk '{print $3}'`
    							fixeddiskspace=`df -P $mountpointdisk |grep -v Used| awk '{print $3}'`
    							usedsize=$fixeddiskspace
    							if [ ! -z $diskmapth ] && [ $diskmapth != "samandruli" ]; then
    								disko=$diskmapth
    								mpath_layout="${mpath_layout}${disko};${size};${usedsize}|"
    							else
    							  layout_console="${layout_console}${disko};${size};${usedsize}|"
    								fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
    							fi
    						else
    							#When disk is not  mounted and do not have partition defined
    							#we assume that the disk is not being used
    							usedsize=0
    							if [ ! -z $diskmapth ] && [ $diskmapth != "samandruli" ]; then
    								disko=$diskmapth
    								mpath_layout="${mpath_layout}${disko};${size};${usedsize}|"
    							else
    							  layout_console="${layout_console}${disko};${size};${usedsize}|"
    								#It's not a fixed disk, it's an unused disk
    							fi
    						fi
    					else
    						#When fixed disk have partition
    						for fixeddisks in `lsblk /dev/$disko -ibr -o name,size|grep -v NAME|grep -wv $disko|awk '{print $1}'`;
    						do
                ## adding additional logic to check the disks for mpathd , modifying fixeddisks to take mapper values
                  if [ $mpathstate -eq 0 ] ; then
                    ls -la /dev/$fixeddisks > /dev/null 2>&1
                    stat=$(echo $?)
                      if [ $stat -ne 0 ] ; then
                        fixeddisks="mapper/$fixeddisks"
                      fi
                  fi
    							#take each fixed disk partitioned and control if are mounted or not
    							mountdisk=`lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'`
    							if  lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME|grep -wv ${diskmapth}| awk '{print $3}'|grep -q '/'; then
    								#When disk are mounted
    								mountpointdisk=`lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'`
                    mpointdisk_wc=$(echo $mountpointdisk | wc -w)
                      if [ $mpointdisk_wc -eq 1 ] && [ $mpathstate -ne 0 ]; then
    								    fixeddiskspace=`df -P $mountpointdisk |grep -v Used| awk '{print $3}'`
    								    sizepartial=$fixeddiskspace
                      else
                      sizepartial=0
                      fi
    							else
    								#When disk is not  mounted
                    if echo $fixeddisks | grep -ivq mapper; then
    								  kbytesfixedspace=`lsblk /dev/$fixeddisks -ibr -o size|grep -v SIZE|head -1`
    								  fixeddiskspace=`expr $kbytesfixedspace / 1024`
    								  sizepartial=$fixeddiskspace
                    else
                      sizepartial=0
                    fi
    							fi
    							usedsize="`expr $usedsize + $sizepartial`"
    						done
    						if [ ! -z $diskmapth ] && [ $diskmapth != "samandruli" ]; then
    							disko=$diskmapth
    							mpath_layout="${mpath_layout}${disko};${size};${usedsize}|"
    						else
    						  layout_console="${layout_console}${disko};${size};${usedsize}|"
    							fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
    						fi
    					fi
    				fi
    			else
    				#if lvm is not installed all logic came here in order to check only fixed
    				# partitions scenario (same code that you have up to work with fixed )
    				size="`cat /proc/partitions | grep -w $disko | awk '{print $3}'`"
    				usedsize=0
    				if [ `lsblk /dev/$disko -ibr -o name,size|grep -v NAME |grep -v ${diskmapth}|wc -l` -eq 1 ]; then
    					#here enter when pvs is insta�lled but the disk in loop do not have partition defined
    					if  lsblk /dev/$disko -o name,size,mountpoint -ibr|grep -v NAME|grep -v ${diskmapth}| awk '{print $3}'|grep -q /; then
    						#When disk are mounted and do not have partition defined
    						mountpointdisk=`lsblk /dev/$disko -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'`
    						fixeddiskspace=`df -P $mountpointdisk |grep -v Used| awk '{print $3}'`
    						usedsize=$fixeddiskspace
    						if [ ! -z $diskmapth ] && [ $diskmapth != "samandruli" ]; then
    							disko=$diskmapth
    							mpath_layout="${mpath_layout}${disko};${size};${usedsize}|"
    						else
    						  layout_console="${layout_console}${disko};${size};${usedsize}|"
    							fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
    						fi
    					else
    						#When disk is not  mounted and do not have partition defined
    						#we assume that the disk is not being used
    						usedsize=0
    						if [ ! -z $diskmapth ] && [ $diskmapth != "samandruli" ]; then
    							disko=$diskmapth
    							mpath_layout="${mpath_layout}${disko};${size};${usedsize}|"
    						else
    						  layout_console="${layout_console}${disko};${size};${usedsize}|"
    							#It's not a fixed disk, its an unused disk
    						fi
    					fi
    				else
    					#When fixed disk have partition
    					for fixeddisks in `lsblk /dev/$disko -ibr -o name,size|grep -v NAME|grep -wv $disko|awk '{print $1}'`;
    					do
    						#take each fixed disk partitioned and control if are mounted or not
    						mountdisk=`lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'`
    						if  lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'|grep -q '/'; then
    							#When disk are mounted
    							mountpointdisk=`lsblk /dev/$fixeddisks -o name,size,mountpoint -ibr|grep -v NAME| awk '{print $3}'`
    							fixeddiskspace=`df -P $mountpointdisk |grep -v Used| awk '{print $3}'`
    							sizepartial=$fixeddiskspace
    						else
    							#When disk is not  mounted
    							kbytesfixedspace=`lsblk /dev/$fixeddisks -ibr -o size|grep -v SIZE|head -1`
    							fixeddiskspace=`expr $kbytesfixedspace / 1024`
    							sizepartial=$fixeddiskspace
    						fi
    						usedsize="`expr $usedsize + $sizepartial`"
    					done
    					if [ ! -z $diskmapth ] && [ $diskmapth != "samandruli" ]; then
    						disko=$diskmapth
    						mpath_layout="${mpath_layout}${disko};${size};${usedsize}|"
    					else
    					  layout_console="${layout_console}${disko};${size};${usedsize}|"
    						fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
    					fi
    				fi
    			fi
    		fi
    	done
    done
    echo $layout_console${mpath_layout} > $atatempdir/DiskDrive.txt 2>&1
    unset size
    unset usedsize

  else
  	#Used when lsblk is not installed
  	#List all disks first except powerpath, then list powerpath
  	#some changed for mmpath are not tested in server without lsblk please test
    for grepopt in -iv -i; do
      for disko in `$SUDO cat /proc/partitions | grep -v major | awk 'NF'|grep $grepopt emcpower | grep -v 'dm-' |grep -v loop| grep -iv ram|grep -iv "^sr"|grep -iv "^fd"| sort -k 2 | grep -vi mapper | grep -iv ram|awk '{print $4}'|eval ${grepvar}`; do
        pvmpath=0
  			diskmapth=`$SUDO multipath -l /dev/${disko}`
  			mpathstate=$?
  			if [ $mpathstate -eq 0 ];then
  				diskmapth=`$SUDO multipath -l /dev/${disko}| head -1 | awk '{print $1}'`
  				if [ -z $diskmapth ]; then
  					diskmapth="samandruli"
  				fi
  			else
  				diskmapth="samandruli"
  			fi
        if [ $diskmapth == "samandruli" ] || ! grep $diskmapth $atatempdir/dismapth.tmp; then
          #Check if pvs is present
          $SUDO pvs > /dev/null 2>&1
          if [ $? -eq 0 ];then
            #if lvm is present check if the disk are in lvm
            pvsym=0
            disksym="`ls -l /dev |grep -w "${disko}"| grep ^l | awk '{print $9}'`"
            if [ ! -z $disksym ]; then
              if $SUDO pvs -o pv_name| grep -v PV | grep -w $disksym ; then
                pvsym=1
              fi
            fi
            pvluks=0
            #if blkid | grep $disko | grep -i crypto_LUKS; then
            # for i in `blkid | grep $disko| grep crypto_LUKS| awk -F "UUID" '{print $2}'| awk -F\" '{print $2}'`; do
            #    diskluk=`$SUDO pvs -o pv_name| grep -v PV |grep -i $i`
            #    if [ ! -z $diskluk ]; then
            #     if $SUDO pvs -o pv_name| grep -v PV | grep -w $diskluk ; then
            #        pvluks=$((pvluks+1))
            #      fi
            #    fi
            #  done
            #fi
            pvmpath=0
  					if [ $diskmapth != "samandruli" ]; then
              echo $diskmapth >> $atatempdir/dismapth.tmp
              if $SUDO pvs -o pv_name| grep -v PV | grep -w $diskmapth ; then
                pvmpath=1
              fi
            fi
            if $SUDO pvs |grep -iq $disko || [ $pvsym == "1" ] || [ $pvluks != "0" ] || [ $pvmpath == "1" ]; then
              #if the disk use lvm proceed
              size="`cat /proc/partitions | grep -w $disko |head -1| awk '{print $3}'`"
              usedsize=0
              if [ $pvluks != "0" ]; then
                lukUUID=`blkid | grep $disko| grep crypto_LUKS| awk -F "UUID" '{print $2}'| awk -F\" '{print $2}'`
                pvdisk=`$SUDO pvs -o pv_name| grep -v PV |grep -i $lukUUID`
              else
  							if [ $pvmpath == "1" ]; then
  								disko=$diskmapth
  							fi
                pvdisk=`$SUDO pvs -o pv_name| grep -v PV |grep -i $disko`
                lukUUID="samandruli"
              fi

              #check if pvs disk are not used
              diskvg=`$SUDO pvs -o vg_name $pvdisk|grep -v VG`
              if [ -z $diskvg ]; then
                #if [[ ! $diskvg && ${diskvg-x} ]]; then
                #if [ `pvs -o vg_name $pvsdisk|grep -cv VG` -eq 0 ]; then
                #disk only configured with pvs but not u  sed
                #the disk have partion pvs like /dev/sda or /dev/sda1
                #In this case we put the total of disk because
                #console copy this disk as raw device
                usedsize=$size
              else
                #Check used size of each PV in KB
                usedsize=`$SUDO pvs --noheadings -o pv_used --units k $pvdisk | awk '{sum += $1} END {print sum}'`
              fi
              layout_console="${layout_console}${disko};${size};${usedsize}|"
            else
              #Here enter when pvs is installed but the disk in loop is not lvm
              size="`cat /proc/partitions | grep -w $disko |head -1| awk '{print $3}'`"
              usedsize=0
              if [ `blkid -o device |grep -w "/dev/$disko" |wc -l` -eq 1 ]; then
                #here enter when pvs is insta�lled but the disk in loop do not have partition defined
                mountdisk=`df -P |grep -w "/dev/$disko" | awk '{print $6}'`
                if  df -P |grep -w "/dev/$disko" | awk '{print $6}'|grep -q /; then
                  #When disk are mounted and do not have partition defined
                  mountpointdisk=`df -P |grep -w "/dev/$disko" | awk '{print $6}'`
                  fixeddiskspace=`df -P $mountpointdisk |grep -v Used| awk '{print $3}'`
                  usedsize=$fixeddiskspace
                  layout_console="${layout_console}${disko};${size};${usedsize}|"
  								fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
                else
                  #When disk is not  mounted and do not have partition defined
  								#we assume that the disk is not being used
                  usedsize=0
                  layout_console="${layout_console}${disko};${size};${usedsize}|"
  								#it's not a fixed disk, it's an unsused disk
                fi
              else
                #When fixed disk have partition
                for fixeddisks in `blkid -o device|grep -i $disko  |awk '{print $1}'`;
                do
                  #take each fixed disk partitioned and control if are mounted or not
                  mountdisk=`df -P |grep -w "$fixeddisks" | awk '{print $6}'`
                  if  [ ! -z $mountdisk ]; then
                    #When disk are mounted
                    fixeddiskspace=`df -P $mountdisk |grep -v Used| awk '{print $3}'`
                    sizepartial=$fixeddiskspace
                  else
                    #When disk is not  mounted
                    kbytesfixedspace=`$SUDO fdisk -s $fixeddisks`
                    fixeddiskspace=`expr $kbytesfixedspace / 1024`
                    sizepartial=$fixeddiskspace
                  fi
                  usedsize="`expr $usedsize + $sizepartial`"
                done
                layout_console="${layout_console}${disko};${size};${usedsize}|"
  							fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
              fi
            fi
          else
            #if lvm is not installed all logic came here in order to check only fixed
            # partitions scenario (same code that you have up to work with fixed )
            size="`cat /proc/partitions | grep -w $disko |head -1| awk '{print $3}'`"
            usedsize=0
            if [ `blkid -o device |grep -w "/dev/$disko" |wc -l` -eq 1 ]; then
              #here enter when pvs is insta�lled but the disk in loop do not have partition defined
              mountdisk=`df -P |grep -w "/dev/$disko" | awk '{print $6}'`
              if  df -P |grep -w "/dev/$disko" | awk '{print $6}'|grep -iq /; then
                #When disk are mounted and do not have partition defined
                mountpointdisk=`df -P |grep -w "/dev/$disko" | awk '{print $6}'`
                fixeddiskspace=`df -P $mountpointdisk |grep -v Used| awk '{print $3}'`
                usedsize=$fixeddiskspace
                layout_console="${layout_console}${disko};${size};${usedsize}|"
  							fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
              else
                #When disk is not  mounted and do not have partition defined
                #we assume that the disk is not being used
                usedsize=0
                layout_console="${layout_console}${disko};${size};${usedsize}|"
  							#It's not a fixed disk, it's an unused disk
              fi
            else
              #When fixed disk have partition
              for fixeddisks in `blkid -o device|grep -i $disko |awk '{print $1}'`;
              do
                #take each fixed disk partitioned and control if are mounted or not
                mountdisk=`df -P |grep -w "$fixeddisks" | awk '{print $6}'`
                if  [ ! -z $mountdisk ]; then
                  #When disk are mounted
                  fixeddiskspace=`df -P $mountdisk |grep -v Used| awk '{print $3}'`
                  sizepartial=$fixeddiskspace
                else
                  #When disk is not  mounted
                  kbytesfixedspace=`$SUDO fdisk -s $fixeddisks`
                  fixeddiskspace=`expr $kbytesfixedspace / 1024`
                  sizepartial=$fixeddiskspace
                fi
                usedsize="`expr $usedsize + $sizepartial`"
              done
              layout_console="${layout_console}${disko};${size};${usedsize}|"
  						fixedoutput="${fixedoutput}${disko};${size};${usedsize};fixed;true|"
            fi
          fi
        fi
      done
    done
    echo $layout_console${mpath_layout} > $atatempdir/DiskDrive.txt 2>&1
    unset size
    unset usedsize
    unset fixeddisks
  fi
  echo $layout_console${mpath_layout} > $atatempdir/DiskDrive.txt

  echo ${fixedoutput} > $atatempdir/DiskDrive-fixed.txt 2>&1
  sed -e "/|/ s//\n/g" $atatempdir/DiskDrive-fixed.txt |  sed '/^$/d' > DiskDrivefixed-Parsing.txt
  awk -F";" '{ print "\"DiskName\":""\x22"$1"\x22,\"TotalDiskSize\":""\x22"$2*1024"\x22,\"UsedDiskSize\":""\x22"$3*1024"\x22,\"IsFixed\":""true"",\"GroupName\":\"\",\"SelectionState\":"$5}' DiskDrivefixed-Parsing.txt >> DiskDrivefixed-parsing-fmt.txt

  #data_json_generator null DiskDrive.txt array Lines > $atatempdir/data-$$.json
  #json_generator $atatempdir/data-$$.json json_file TargetDetails_Host > $atatempdir/JSON/TargetDetails_Host.json

  ##################################################################################################################
  ##################################################################################################################
  ##################################################################################################################

  #We need DiskDrive.txt file to be there.


  #Check lvm disk process
  #######################################################
  #######################################################
  lvm_disk=0
  $SUDO pvs
  pvstatus=`echo $?`
  $SUDO vgs
  vgstatus=`echo $?`
  if echo $pvstatus | grep -wq 0 && echo $vgstatus |grep -wq 0 && [ -f $atatempdir/DiskDrive.txt ]; then
  	echo "Lvm installed"
  	#lvmstatus=1
  	echo > ./temp_disk
  	echo > ./temp_vg
  	for i in `$SUDO pvs -o pv_name,vg_name --noheadings --separator ";" |sed 's/  //g'`; do
  		tempdisk=`echo $i|cut -d";" -f1`
  		vgdisk=`echo $i|cut -d";" -f2`
      if echo ${tempdisk} | grep -i luks; then
        realdkuid=`echo ${tempdisk} | awk -F "luks-" '{print $2}'`
        part=`blkid | grep $realdkuid | grep crypto_LUKS | awk -F ":" '{print $1}'`
      else
    		part=${tempdisk}
      fi
  		partnum=${part##*[[:alpha:]]}
  		if [[ `echo $partnum` -gt 0 ]]; then
  			disk=`echo ${part%$partnum*}`
  		else
  			disk=$part
  		fi
  		echo $disk
      if [ ! -e $disk ]; then
        disk=`echo $disk | rev | cut -c 1 --complement | rev`
      fi
        if echo $disk | grep -iq mapper; then
          diskshort=`echo $disk |cut -d "/" -f 4`
        else
  		    diskshort=`echo $disk |cut -d "/" -f 3`
        fi
  		#Get real size
  		realsize=`cat $atatempdir/DiskDrive.txt |awk -F $diskshort '{print $2}'|cut -d ";" -f2`
  		#Get used size
  		if cat $atatempdir/DiskDrive.txt |awk -F $diskshort '{print $2}'|cut -d ";" -f3 |grep -qi "|"; then
  			usedsize=`cat $atatempdir/DiskDrive.txt |awk -F $diskshort '{print $2}'|cut -d ";" -f3|cut -d"|" -f1 `
  			echo $usedsize
  		else
  			usedsize=`cat $atatempdir/DiskDrive.txt |awk -F $diskshort '{print $2}'|cut -d ";" -f3`
  		fi
  		disk_regex="sda|sda[1-9]|vda|vda[1-9]|xvda|xvda[1-9]|hda|hda[1-9]|emcpowera|emcpowera[1-9]"
  		if echo $diskshort| egrep -qw "${disk_regex}";  then
  			echo "$disk;$realsize;$usedsize;$vgdisk;false"
  			echo "$disk;$realsize;$usedsize;$vgdisk;false" >> ./temp_disk
  			lvm_disk=1
  		else
  			echo "$disk;$realsize;$usedsize;$vgdisk;true"
  			echo "$disk;$realsize;$usedsize;$vgdisk;true" >> ./temp_disk
  		fi
  		sed -i '/^$/d' ./temp_disk
  	done
    for i in `$SUDO vgs -o vg_name --noheadings --separator ";" --aligned|sed 's/  //g'`
    do
    	vgdisk=$i
    	echo "$vgdisk" >> ./temp_vg
    	sed -i '/^$/d' ./temp_vg
    done
    for i in `cat ./temp_vg`
    do
    	COUNT=0
    	declare -A array
    	#echo " Size of array" ${#array[@]}
    	for j in `cat ./temp_disk`
    	do
          if echo $j | grep -iq mapper; then
            disk=`echo $j|cut -d";" -f1|cut -d"/" -f4 `
          else
    		    disk=`echo $j|cut -d";" -f1|cut -d"/" -f3 `
          fi
    		realdisk=`echo $j |cut -d ";" -f2`
    		useddisk=`echo $j |cut -d ";" -f3`
    		vg=`echo $j|cut -d";" -f4`
    		diskstate=`echo $j |cut -d ";" -f5`
    		if [ "$vg" == "$i" ]; then
    			let COUNT=COUNT+1
    			array[$COUNT]="$disk;$realdisk;$useddisk;$diskstate"
    		fi
    	done
  		for n in `seq 1 $COUNT`
  		do
    		echo ${array[$n]}
    		echo $n
    		if [ $COUNT -gt 1 ]; then
    			array[$n]=$(echo ${array[$n]}|sed -e 's/true/false/g')
    			#IF VG have more than one disk
    			 echo "$i;${array[$n]};|" >> ./table_disk_temp
    		else
    			#If VG have one disk
    			echo "$i;${array[$n]}|" >> ./table_disk_temp
    		fi
  	 done
    done
  fi
  cat ./table_disk_temp |xargs echo > $atatempdir/DiskDrive-lvm.txt
  sed -i 's/ //g' $atatempdir/DiskDrive-lvm.txt
  #cp ./temp_disk{,.lvm}
  rm -f ./table_disk_temp
  rm -f ./temp_vg
  rm -f ./temp_disk
  sed -e "/|/ s//\n/g" DiskDrive-lvm.txt | sed '/^$/d' > DiskDrivelvm-Parsing.txt
  awk -F";" '{ print "\"DiskName\":""\x22"$2"\x22,\"TotalDiskSize\":""\x22"$3*1024"\x22,\"UsedDiskSize\":""\x22"$4*1024"\x22,\"IsFixed\":""false"",\"GroupName\":\x22"$1"\x22,\"SelectionState\":"$5}'  DiskDrivelvm-Parsing.txt >> DiskDrivefixed-parsing-fmt.txt
  #send_data $DISKDETAILS_URL "$(job_json_generator DiskDrive-fixed.txt array FixedLines DiskDrive-lvm.txt array VGLines)"
  #data_json_generator null DiskDrive-fixed.txt array FixedLines DiskDrive-lvm.txt array VGLines > $atatempdir/data-$$.json
  #data_json_generator_iteration null DiskDrivefixed-parsing-fmt.txt objectsArrayParsing Data >$atatempdir/data-$$.json
  #json_generator $atatempdir/data-$$.json json_file LinuxDiskDetails > $atatempdir/JSON/LinuxDiskDetails.json

  #Check raw devices
  #######################################################
  #######################################################

  #Create the temp.fixed file for checking raw devices
  cat $atatempdir/DiskDrive-fixed.txt | sed s/\|/\\n/g | sed '/^$/d' > ./temp_disk.fixed
  cat $atatempdir/DiskDrive.txt | sed s/\|/\\n/g | sed '/^$/d' > ./temp_disk
  cat $atatempdir/DiskDrive-lvm.txt | sed s/\|/\\n/g | sed '/^$/d' > ./temp_disk.lvm

  cat ./temp_disk |awk -F";" '{print $1}'|cut -d"/" -f3  > ./temp_disk.short
  cat ./temp_disk.lvm |awk -F";" '{print $2}'|cut -d"/" -f3  > ./temp_disk.lvm.short
  cat ./temp_disk.fixed |awk -F";" '{print $1}'|cut -d"/" -f3 > ./temp_disk.fixed.short
  cat ./temp_disk.fixed.short ./temp_disk.lvm.short ./temp_disk.short |sort |uniq -u > ./temp_disk.raw.short
  for i in `cat ./temp_disk.raw.short`
  do
    realsize=`cat $atatempdir/DiskDrive.txt |awk -F $i '{print $2}'|cut -d ";" -f2`
    if cat $atatempdir/DiskDrive.txt |awk -F $i '{print $2}'|cut -d ";" -f3 |grep -qi "|"; then
      usedsize=`cat $atatempdir/DiskDrive.txt |awk -F $i '{print $2}'|cut -d ";" -f3|cut -d"|" -f1 `
      echo $usedsize
    else
      usedsize=`cat $atatempdir/DiskDrive.txt |awk -F $i '{print $2}'|cut -d ";" -f3`
    fi
    echo "$i;$realsize;$usedsize;raw;true|" >> ./temp_disk.last
  done
  cat ./temp_disk.last |xargs echo > $atatempdir/DiskDrive-raw.txt
  sed -i 's/ //g' $atatempdir/DiskDrive-raw.txt
  rm -f ./temp_disk
  rm -f ./temp_disk.last
  rm -f ./temp_disk.short
  rm -rf ./temp_disk.fixed
  rm -rf ./temp_disk.raw
  rm -rf ./temp_disk.lvm
  rm -rf ./temp_disk.fixed.short
  rm -rf ./temp_disk.raw.short
  rm -rf ./temp_disk.lvm.short
  sed -e "/|/ s//\n/g" DiskDrive-raw.txt | sed '/^$/d' > DiskDrive-raw-Parsing.txt
  awk -F";" '{ print "\"DiskName\":""\x22"$1"\x22,\"TotalDiskSize\":""\x22"$2*1024"\x22,\"UsedDiskSize\":""\x22"$3*1024"\x22,\"IsFixed\":""true"",\"GroupName\":\"\",\"SelectionState\":""false"}' DiskDrive-raw-Parsing.txt >> DiskDrivefixed-parsing-fmt.txt

  ## Additional code to append the OSdisk parameter, considering only the disk where /boot resides.
  if [ ! -d /sys/firmware/efi ]; then
    bootdiskpart=$(df -TP /boot | grep -v "Used" | awk '{print $1}')
    bootdisktype=$($SUDO lsblk -o TYPE $bootdiskpart | grep -v TYPE | head -n 1)
    bootdisk=$(echo ${bootdiskpart##*/})
      if [[ $bootdisktype != lvm ]]; then
        bootdisk_wn=$(echo ${bootdisk//[[:digit:]]/})
         if [[ $bootdisk_wn =~ "nvme" ]] ; then
           bootdisk_wn=$(echo ${bootdisk%%p*})
         fi
        sed -i '/'"$bootdisk_wn"'/ s/$/,\"OsDisk\":true/' DiskDrivefixed-parsing-fmt.txt
        sed -i '/'"$bootdisk_wn"'/! s/$/,\"OsDisk\":false/' DiskDrivefixed-parsing-fmt.txt
      else
        bootdisk=$(echo ${bootdiskpart##*/})
        bootdiskvg=$($SUDO lvs -o vg_name $bootdiskpart | grep -v VG)
       ## This is to take only the first added disk to the system, negating all other disks later added to the vg
        bootdiskvgpart=$($SUDO pvs | grep -i "$bootdiskvg" | awk '{print $1}'| head -1)
        bootdiskpvdisk=$(echo ${bootdiskvgpart##*/})
        bootdiskpvdisk_wn=$(echo ${bootdiskpvdisk//[[:digit:]]/})
          if [[ $bootdiskpvdisk_wn =~ "nvme" ]] ; then
           bootdiskpvdisk_wn=$(echo ${bootdisk%%p*})
          fi
        sed -i '/'"$bootdiskpvdisk_wn"'/ s/$/,\"OsDisk\":true/' DiskDrivefixed-parsing-fmt.txt
        sed -i '/'"$bootdiskpvdisk_wn"'/! s/$/,\"OsDisk\":false/' DiskDrivefixed-parsing-fmt.txt
      fi
  else
    bootdiskpart=$(df -TP /boot/efi | grep -v "Used" | awk '{print $1}')
    bootdisk=$(echo ${bootdiskpart##*/})
    bootdisk_wn=$(echo ${bootdisk//[[:digit:]]/})
      if [[ $bootdisk_wn =~ "nvme" ]] ; then
        bootdisk_wn=$(echo ${bootdisk%%p*})
      fi
    sed -i '/'"$bootdisk_wn"'/ s/$/,\"OsDisk\":true/' DiskDrivefixed-parsing-fmt.txt
    sed -i '/'"$bootdisk_wn"'/! s/$/,\"OsDisk\":false/' DiskDrivefixed-parsing-fmt.txt
  fi

  data_json_generator_iteration null DiskDrivefixed-parsing-fmt.txt objectsArrayParsing Data >$atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file LinuxDiskDetails > $atatempdir/JSON/LinuxDiskDetails.json

  #DISK PARTITIONS information
  if [ -f /proc/partitions ]; then
  	cat /proc/partitions | grep -iv cifs >> DiskPart.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EPRO: Error retrieving partitions information: File /proc/partitions not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch DiskPart.txt 2>&1
  fi

  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> DiskPart.txt 2>&1
  which df > /dev/null 2>&1
  if [ $? = 0 ]; then
  	df -TP -B1 |grep -iv cifs| grep -Ev ':|\/\/' | sed -e 's/ \+/\ \|\ /g' >> DiskPart.txt 2>&1
    #df -TP -B1 |grep -iv cifs| grep -Ev ':|\/\/|tmpfs' | sed -e 's/ \+/\ \|\ /g' >> DiskInformation.txt 2>&1
    df -TP -B1 |grep -iv cifs| grep -Ev ':|\/\/|tmpfs|Filesystem' | sed -e 's/ \+/\ \,\ /g' | awk -v a=$ext -F " , " '{print "\"Name\":""\x22"$1"\x22"",\"Description\":\"Mounted on " $7" \x22,\"FreeSpace\":"$5",\"FileSystem\":""\x22"$2"\x22,\"Size\":"$3",\"LargestDirectorySize\":0"}' >> DiskInformation.txt
    grep -iq /boot DiskInformation.txt
    if [[ $? -eq 0 ]]; then
       sed -i '/\/boot/ s/$/,\"OsDisk\":true/' DiskInformation.txt
       sed -i '/\/boot/! s/$/,\"OsDisk\":false/' DiskInformation.txt
    else
       sed -i '/\/ / s/$/,\"OsDisk\":true/' DiskInformation.txt
       sed -i '/\/ /! s/$/,\"OsDisk\":false/' DiskInformation.txt
    fi
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EDF: Error retrieving partitions information from 'df'..." | tee -a $log_file
  	echo "******************" | tee -a $log_file
    touch DiskInformation.txt
  fi

  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> DiskPart.txt 2>&1
  which mount > /dev/null 2>&1
  if [ $? = 0 ]; then
  	mount |grep -iv cifs| grep -Ev ':|\/\/' >> DiskPart.txt 2>&1
    #mount |grep -iv cifs| grep -Ev ':|\/\/' | grep ^\/ >> DiskInformation.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EMOU: Error retrieving information with mount command..." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  fi

  #Get disk type Information
  touch DiskType.txt
  for disko in `$SUDO cat /proc/partitions | grep -v major | awk 'NF'|grep -iv emcpower | grep -v 'dm-' |grep -v loop| grep -iv ram| sort -k 2 | grep -vi mapper | grep -iv ram|awk '{print $4}'|eval ${grepvar}`; do
  	if [ -f /sys/block/$disko/device/model ]; then
  		model=$(cat /sys/block/$disko/device/model)
  		vendor=$(cat /sys/block/$disko/device/vendor)
  		rev=$(cat /sys/block/$disko/device/rev)
  		echo "$disko $vendor $model $rev">> DiskType.txt
  	elif [ -f /sys/block/$disko/device/devtype ] && [ $(cat /sys/block/$disko/device/devtype) == "vbd" ]; then
  		model="Virtual Block Disk"
  		vendor="Xen"
  		echo "$disko $vendor $model">> DiskType.txt
  	elif grep -i cciss /proc/partitions; then
  		vendor="HP"
  		model="DG0300FARVV"
  		echo "$disko $vendor $model">> DiskType.txt
    elif grep -i vbd /sys/devices/xen/vbd-*/devtype; then
      model="Virtual Block Disk"
      vendor="Xen"
      echo "$disko $vendor $model">> DiskType.txt
  	fi
  done


  #this function will run data_json_generator itself
  #send_data $DISKINFO_URL "$(diskinfo_json_data)"
	error_check "EDF"
  diskinfo_json_data "$error" > ${atatempdir}/data-$$.json
  json_generator $atatempdir/data-$$.json json_file LogicalDiskDetails > $atatempdir/JSON/LogicalDiskDetails.json

  #Volume Groups information
  vgdisp=$(which vgdisplay)
  if [ -z $vgdisp ]; then
  	$SUDO $vgdisp >> VolumeGroups.txt 2>&1
  fi
  touch VolumeGroups.txt 2>&1

  #IDE Controller
  which lspci > /dev/null 2>&1
  if [ $? = 0 ]; then
  	for line in $(lspci | awk '/Fibre/ {print $1}')
  	do
  		for line in $(lspci -n | grep $line | awk '{print $3}')
  		do
  			lspci -vv -d $line >> IDEController.txt 2>&1
  		done
  	done
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) ELSPCI Error retrieving information with lspci command..." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch IDEController.txt 2>&1
  fi

  #Hostname information
  which hostname > /dev/null 2>&1
  if [ $? = 0 ]; then
    hostname -f > /dev/null 2>&1
    if  [ $? = 0 ]; then
      hostname -f >> HostName.txt 2>&1
  	else
  		hostname 	>> HostName.txt 2>&1
  	fi
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EHSTNME Error retrieving information with hostname command..." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch HostName.txt 2>&1
  fi

  #Users information
  if [ -f /etc/passwd ];then
  	DOMAIN=$(hostname --domain)
  	for USRS in $(awk -F: '$5 && $7 ~ "sh$" {print $1}' /etc/passwd)
  	do
  	  GRP=$(groups $USRS | awk '{print $3}')
  	  STAT=$($SUDO passwd -S $USRS | awk '{print $2}')
  	  case $STAT in
  	    L) STAT="Locked" ;;
  	    NP) STAT="No Password" ;;
  	    P) STAT="Active" ;;
  			PS) STAT="Active" ;;
  			LK) STAT="Locked" ;;
  	  esac
  	  echo $USRS,$DOMAIN,$GRP,$STAT >> UsersList.txt
      echo "\"Name\":\"$USRS\",\"Caption\":\"$DOMAIN\",\"Description\":\"\",\"Type\":\"ACCOUNT\",\"Status\":\"$STAT\"">> UsersList-new-fmt.txt #this should be modified to key value pair text.
  	done
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EPASS: Error retrieving users information from /etc/passwd file..." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	echo "\"Name\":\"\",\"Caption\":\"\",\"Description\":\"\",\"Type\":\"\",\"Status\":\"\"" >> UsersList.txt
  fi
  error_check "EPASS"
  #send_data $ACCOUNTINFO_URL "$(job_json_generator UsersList.txt array Lines)"
  #data_json_generator $error UsersList.txt array Lines DiskDrive-lvm.txt array VGLines > $atatempdir/data-$$.json
  #json_generator $atatempdir/data-$$.json json_file AccountInformation_AccountGroup > $atatempdir/JSON/AccountInformation_AccountGroup.json
  data_json_generator_iteration "$error" UsersList-new-fmt.txt objectsArrayParsing Data > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file UserAccountInformation > $atatempdir/JSON/UserAccountInformation.json
  #Groups information
  if [ -f /etc/group ]; then
  	cat /etc/group | cut -d: -f1 >> GroupList.txt 2>&1
     cat /etc/group | awk -F":" '{print "\"Name\":""\x22"$1"\x22,\"Caption\":""\x22"$1"\x22,\"Status\":\"\",\"Description\":\"\",\"Type\":\"GROUP\""}' >> GroupList-fmt.txt
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EGRP: Error retrieving groups information: File /etc/group not found..." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	echo "\"Name\":\"\",\"Caption\":\"\",\"Status\":\"\",\"Description\":\"\",\"Type\":\"\"" >> GroupList.txt 2>&1
  fi

	#error_check "EGRP"
  #send_data $GROUPINFO_URL "$(job_json_generator GroupList.txt array Lines)"
#  data_json_generator $error GroupList.txt array Lines > $atatempdir/data-$$.json
#  json_generator $atatempdir/data-$$.json json_file GroupInformation_AccountGroup > $atatempdir/JSON/GroupInformation_AccountGroup.json
  data_json_generator_iteration null GroupList-fmt.txt objectsArrayParsing Data > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file UserGroupInformation > $atatempdir/JSON/UserGroupInformation.json


  #fdisk
  which fdisk > /dev/null 2>&1
  if [ $? = 0 ] && [[ $ver != "7.4" ]]; then
  	$SUDO fdisk -l >> Fdisk.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EFDISK Error retrieving fdisk information" | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch Fdisk.txt 2>&1
  fi

  #PVs information
  pvdisp=$(which pvdisplay)
  if [ ! -z $pvdisp ]; then
  	$SUDO $pvdisp >> LogicalDiskToPartition.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) This system has not LVM installed..." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch LogicalDiskToPartition.txt 2>&1
  fi

  #LVs information
  which parted > /dev/null 2>&1
  if [ $? = 0 ]; then
  	$SUDO parted -l >> LogicalDisk.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EPART: Error retrieving logical volumes information: Command parted not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch LogicalDisk.txt 2>&1
  fi

  # Mapped Drives information
  which mount > /dev/null 2>&1
  if [ $? = 0 ]; then
    mount | grep 'nfs[34]* ' >> MappedDisk.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EMOU: Error retrieving information with mount command." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  fi
  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> MappedDisk.txt 2>&1
  which df > /dev/null 2>&1
  if [ $? = 0 ]; then
  	for DISK in $(mount | grep 'nfs[34]* '| awk '{print $3}')
  	do
  		df -ThP $DISK | sed -e 's/ \+/\ \|\ /g' >> MappedDisk.txt 2>&1
      df -ThP -B1 $DISK  | grep -v Type  | awk '{ print "\"FileSystem\":""\x22"$2"\x22,\"FreeSpace\":""\x22"$5"\x22,\"Name\":""\x22"$1"\x22,\"ProviderName\":""\x22"$7"\x22,\"SessionId\":\"\",\"Size\":""\x22"$3"\x22"}' >> MappedDisk-fmt.txt
  	done
    for DISK in $(mount | awk '/ cifs / {print $3}')
  	do
  		df -ThP $DISK | sed -e 's/ \+/\ \|\ /g' >> MappedDisk.txt 2>&1
      df -ThP -B1 $DISK  | grep -v Type  | awk '{ print "\"FileSystem\":""\x22"$2"\x22,\"FreeSpace\":""\x22"$5"\x22,\"Name\":""\x22"$1"\x22,\"ProviderName\":""\x22"$7"\x22,\"SessionId\":\"\",\"Size\":""\x22"$3"\x22"}' >> MappedDisk-fmt.txt
  	done

  else
  	echo "Unable to get the size of mapped drive" >> MappedDisk.txt 2>&1
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EDF Error retrieving information with df command." | tee -a $log_file
  	echo "******************" | tee -a $log_file
    touch MappedDisk-fmt.txt
  fi

  which mount > /dev/null 2>&1
  if [ $? = 0 ]; then
    mount | grep ' cifs ' >> MappedDisk.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EMOU Error retrieving  information with mount command." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  fi
  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> MappedDisk.txt 2>&1
  which df > /dev/null 2>&1
  if [ $? = 0 ]; then
  	for DISK in $(mount | awk '/ cifs / {print $3}')
  	do
  		df -ThP $DISK | sed -e 's/ \+/\ \|\ /g' >> MappedDisk.txt 2>&1
    #  df -ThP /mnt/nfs_clientshare  | grep -v Size  | awk '{ print "\"FileSystem\":""\x22"$2"\x22,\"FreeSpace\":""\x22"$5"\x22,\"Name\":""\x22"$1"\x22,\"ProviderName\":""\x22"$7"\x22,\"SessionId\":\"\",\"Size\":""\x22"$3"\x22"}' >> MappedDisk-fmt.txt
  	done
  else
  	echo "Unable to get the size of mapped drive" >> MappedDisk.txt 2>&1
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EDF Error retrieving information with df command." | tee -a $log_file
  	echo "******************" | tee -a $log_file
    touch MappedDisk-fmt.txt
  fi

  touch MappedDisk-fmt.txt
  error_check "EDF"
  # send data to console
  # send_data $DISKMAPPING_URL "$(job_json_generator MappedDisk.txt array Lines)"
#  data_json_generator $error MappedDisk.txt array Lines > $atatempdir/data-$$.json
#  json_generator $atatempdir/data-$$.json json_file MappedDisk_MappedDiskDetail > $atatempdir/JSON/MappedDisk_MappedDiskDetail.json
  data_json_generator_iteration "$error" MappedDisk-fmt.txt objectsArrayParsing Data  > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file MappedDiskDetail > $atatempdir/JSON/MappedDiskDetail.json

  # Memory
  which free > /dev/null 2>&1
  if [ $? = 0 ]; then
  	free -m >> MemoryInfo.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EFREE: Error retrieving memory free information: Command free not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch MemoryInfo.txt 2>&1
  fi
  awk '/Mem/ {print "\"Memory\":\"\",\"Size\":""\x22"$2"MB\x22,\"MemoryBank\":\"\""}' MemoryInfo.txt > MemoryInfo-fmt.txt
  error_check "EFREE"
  data_json_generator_iteration "$error" MemoryInfo-fmt.txt  objectsArrayParsing Data > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file MemoryDetails > $atatempdir/JSON/MemoryDetails.json
  #ps COMMAND
  which ps > /dev/null 2>&1
  if [ $? = 0 ]; then
    ps -aux >> Process_running.txt 2>&1
  else
    echo "******************" | tee -a $log_file
    echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EPS: Error retrieving running processes information: Command ps not found." | tee -a $log_file
    echo "******************" | tee -a $log_file
    touch Process_running.txt 2>&1
  fi
  # Services
  which systemctl > /dev/null 2>&1
  if [ $? -eq 1 ]; then
  	chkconfig --list | grep "$(runlevel | cut -d ' ' -f2)" | awk '/:on/ {print "\"ServiceName\":""\x22"$1"\x22" ",\"ServiceStatus\":\"running\",\"ActualName\":""\x22"$1"\x22"" "}' >> msservices.txt 2>&1
  else
  	systemctl | awk '/running/ {print "\"ServiceName\":""\x22"$1"\x22" ",\"ServiceStatus\":\"running\",\"ActualName\":""\x22"$1"\x22"" "}' >> msservices.txt 2>&1
  fi
  #echo "" >> msservices.txt 2>&1

 #error_check
  # send data to console
  # send_data $MSSERVICES_URL "$(job_json_generator msservices.txt array Lines)"
  data_json_generator_iteration null msservices.txt objectsArrayParsing Data> $atatempdir/data-$$.json
  json_generator $atatempdir/job-$$.json json_file ServiceDetails > $atatempdir/JSON/ServiceDetails.json

  # CPU Information
  sockets=$(cat /sys/devices/system/cpu/cpu[0-9]*/topology/physical_package_id | sort -u | wc -l)

  sibling=$(cat /sys/devices/system/cpu/cpu[0-9]*/topology/core_id | wc -l)
  if [ -z $sibling ]; then
  	sibling=1
  fi
  cpucores=$(cat /sys/devices/system/cpu/cpu[0-9]*/topology/core_id | sort -u | wc -l)
  if [ -z $cpucores ]; then
  	cpucores=1
  fi
  threads=$((sibling/(cpucores*sockets)))
  cpuspeed=$(cat /proc/cpuinfo | awk '/cpu MHz/ {print int($4)}'|sort -u | tail -1)
  vCPUs=$(($threads * $cpucores *  $sockets))

  if [ $distro = "el4" ]; then
  	sockets=1
  	sibling=1
  	cpucores=1
  	threads=1
  fi

  model_name=$(awk '/model name/ {for (i=4; i<NF; i++) printf $i " "; if (NF >= 4) print $NF; }' /proc/cpuinfo | sort -u )
  totalcore=$(($sockets * $cpucores))

#  echo -e "Architecture: $(uname -m)" >> Processor.txt
#  echo -e "CPU(s): \t\t $sockets" >> Processor.txt
#  echo -e "Thread(s) per core: \t $threads" >> Processor.txt
#  echo -e "Cores(s) per socket: \t $cpucores" >> Processor.txt
#  echo -e "CPU MHz: \t\t $cpuspeed MHz" >> Processor.txt
#  echo -e "Vendor ID: \t\t $(cat /proc/cpuinfo | awk '/vendor_id/ {print $3}' | sort -u )" >> Processor.txt
#  echo -e "Model Name: \t\t $model_name" >> Processor.txt
#  echo -e "Total Core Count: \t\t $totalcore" >> Processor.txt
#  echo -e "Virtual Processor Count: \t $vCPUs" >> Processor.txt
  echo -n "\"Architecture\":\"$(uname -m)\"," >> Processor.txt
  echo -n "\"CpuCount\":\"$sockets\"," >> Processor.txt
  echo -n "\"ThreadCount\":\"$threads\"," >> Processor.txt
  #echo -e "Cores(s) per socket: \t $cpucores" >> Processor.txt
  echo -n "\"CpuMhz\":\"$cpuspeed\"," >> Processor.txt
  echo -n "\"VendorId\":\"$(cat /proc/cpuinfo | awk '/vendor_id/ {print $3}' | sort -u )\"," >> Processor.txt
  echo -n "\"ProcessorType\":\"$model_name\"," >> Processor.txt
  echo -n "\"CoreCount\":\"$totalcore\"," >> Processor.txt
  echo -n "\"VirtualProcessorCount\":\"$vCPUs\"" >> Processor.txt

  # send data to console
  #send_data $PROCESSORS_URL "$(job_json_generator Processor.txt array Lines)"
#  data_json_generator null Processor.txt array Lines > $atatempdir/data-$$.json
#  json_generator $atatempdir/data-$$.json json_file Details_Processor > $atatempdir/JSON/Details_Processor.json
  data_json_generator_iteration null Processor.txt objectsArray Data > $atatempdir/data-$$.json
  sed -i 's/\[/\{/g' $atatempdir/data-$$.json ; sed -i 's/\]/\}/g' $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file ProcessorDetails > $atatempdir/JSON/ProcessorDetails.json

  # Product Information
  if [ -x /usr/bin/dpkg ]; then
  	for package in $(dpkg -l | awk '/^ii/ {print $2}')
  		do dpkg -s $package | sed 's/Package:/Name:/g' >> ProductList.txt 2>&1
  	done
    echo -e $(cat ProductList.txt | awk -F'[" ":]' '/^Name|^Version|^Maintainer/ { print $0"," }'| sed '/Version/ s/,$/\\n/g' | awk NF=NF RS='\n\n' | sed 's/: /:/g ;s/ :/:/g'| sed '$ s/..$//') >> ProductList-fmt.txt
    cat ProductList-fmt.txt | awk -F"[:,]" '{print "\"ProductName\":""\x22"$2"\x22,\"Publisher\":""\x22"$4"\x22,\"InstallDate\":\"\",\"ProductVersion\":""\x22"$6":"$7"\x22"}' >> ProductList-fmt-parsing.txt
  fi
  if [ -x /usr/bin/rpm ] || [ -x /bin/rpm ]; then
  	rpm -qa --info >> ProductList.txt 2>&1
    #echo -e $(cat ProductList.txt | awk -F'[" ":]' '/^Name|^Version|^Install|^Vendor/ { print $0"," }'| sed '/Vendor/ s/,$/\\n/g' | awk NF=NF RS='\n\n' | sed 's/: /:/g ;s/ :/:/g'|sed '$ s/..$//' ) >>ProductList-fmt.txt
    #cat ProductList-fmt.txt |awk -F"[:,]" '{print "\"ProductName\":""\x22"$2"\x22,\"Publisher\":""\x22"$10$11"\x22,\"InstallDate\":""\x22"$6"\:"$7"\:"$8"\x22,\"ProductVersion\":""\x22"$4"\x22"}' >> ProductList-fmt-parsing.txt
    rpm -qa --queryformat "\"ProductName\":\"%{NAME}\",\"InstallDate\":\"%{INSTALLTIME:date}\",\"ProductVersion\":\"%{VERSION}\",\"Publisher\":\"%{VENDOR}\"\n" >> ProductList-fmt-parsing.txt
  fi
#Productlist new JSON generator should be created
  # send data to console
  # send_data $PRODUCTLIST_URL "$(job_json_generator ProductList.txt array Lines)"
  #data_json_generator null ProductList.txt array Lines > $atatempdir/data-$$.json
  #json_generator $atatempdir/data-$$.json json_file ProductList_Product > $atatempdir/JSON/ProductList_Product.json
  data_json_generator_iteration null ProductList-fmt-parsing.txt objectsArrayParsing Data > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file InstalledProducts > $atatempdir/JSON/InstalledProducts.json
  # SCSI Information
  which lspci > /dev/null 2>&1
  if [ $? = 0 ]; then
  	lspci | grep Fibre >> SCSIController.txt 2>&1
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) ELSPCI: Error retrieving SCSI information: Command lspci not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch SCSIController.txt 2>&1
  fi

  # Scheduled tasks
  which crontab > /dev/null 2>&1
  if [ $? = 0 ]; then
  	$SUDO	crontab -l >> CronJobs.txt 2>&1
    #$SUDO  crontab -l | awk  '{print "\"Command\":""\x22"$6"\x22,\"Description\":""\x22"$1,$2,$3,$4,$5"\x22"}'>> Crontabparser.txt
    crontab -l |grep -v "^#"| sed '/^$/d'|sed 's/"/\\\"/g'|  awk '{print "\"Description\":\""$1,$2,$3,$4,$5"\",\"Command\":\"";for (i=6; i<NF; i++) printf $i " "; if (NF >= 6) print $NF"\""; }'| sed -z 's/:\"\n/:" /g' >>Crontabparser.txt
    #$SUDO crontab -l | grep -v "^#" |  awk '{for (i=6; i<NF; i++) printf $i " "; if (NF >= 6) print "\"Command\":\""$NF"\""; }' >>contabpa.txt
  	#$SUDO	cat /etc/cron.d/* >> CronJobs.txt 2>&1
  	#$SUDO	cat /etc/cron.daily/* >> CronJobs.txt 2>&1
  	#$SUDO	cat /etc/cron.deny/* >> CronJobs.txt 2>&1
  	#$SUDO	cat /etc/cron.hourly/* >> CronJobs.txt 2>&1
  	#$SUDO	cat /etc/cron.monthly/* >> CronJobs.txt 2>&1
  	#$SUDO	cat /etc/crontab >> CronJobs.txt 2>&1
  	#$SUDO	cat /etc/cron.weekly/* >> CronJobs.txt 2>&1
    sed -i  's/\*/\\*/g' Crontabparser.txt
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) ECRON: Error retrieving scheduled tasks information: Command crontab not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	echo ""\"Command\":\"\",\"Description\":"\"\"" >> CronJobs.txt 2>&1
    touch Crontabparser.txt
  fi

  #error_check "ECRON"
  # send_data $CRONJOBS_URL "$(job_json_generator CronJobs.txt array Lines)"
#  data_json_generator $error CronJobs.txt array Lines > $atatempdir/data-$$.json
#  json_generator $atatempdir/data-$$.json json_file Host_CronJobs > $atatempdir/JSON/Host_CronJobs.json
  data_json_generator_iteration null Crontabparser.txt objectsArrayParsing Data > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file CronJobs>$atatempdir/JSON/CronJobs.json
   sed  -i 's/\\\\\*/*/g;s/\\\\\"/\\"/g' $atatempdir/JSON/CronJobs.json
  # Share details
  which smbclient > /dev/null 2>&1
  if [ $? = 0 ]; then
  	while read line; do
      [[ "$line" =~ ^\[ ]] && name="$line"
      [[ "$line" =~ ^[[:space:]]*path ]] && echo -e "$name\t$line"
    done </etc/samba/smb.conf | grep -v "+">> ShareDetails.txt 2>&1
    cat  ShareDetails.txt | tr -d [] | awk '{print "\"Name\":""\x22"$1"\x22,\"Path\":""\x22"$4"\x22,\"Caption\":""\x22"$1"\x22,\"Description\":""\x22""\x22,\"AccessMask\":""\x22""\x22,\"AllowMaximum\":\"True\",\"MaximumAllowed\":\"\",\"InstallDate\":\"\",\"Status\":\"OK\""}' >>  ShareDetails-fmt.txt
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) ESMB: Error retrieving shared details: Command smbclient not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch ShareDetails.txt 2>&1
    #echo  "\"Name\":\"\",\"Path\":\"\",\"Caption\":\"\",\"Description\":\"\",\"AccessMask\":\"\",\"AllowMaximum\":\"\",\"MaximumAllowed\":\"\",\"InstallDate\":\"\",\"Status\":\"\"" >> ShareDetails-fmt.txt
    echo "">ShareDetails-fmt.txt
  fi
  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> ShareDetails.txt 2>&1
  if [ -f /etc/exports ]; then
  	cat /etc/exports >> ShareDetails.txt 2>&1
    cat /etc/exports | awk -F'[" "()]' '/^\// {print "\"Name\":""\x22"$1"\x22,\"Path\":""\x22"$1"\x22,\"Caption\":""\x22"$3"\x22,\"Description\":""\x22"$3"\x22,\"AccessMask\":""\x22"$4"\x22,\"AllowMaximum\":\"True\",\"MaximumAllowed\":\"\",\"InstallDate\":\"\",\"Status\":\"OK\""}' >> ShareDetails-fmt.txt
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) ENFS: Error retrieving shared details: File /etc/exports not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch ShareDetails.txt 2>&1
    touch ShareDetails-fmt.txt
   #  echo "\"Name\":\"\",\"Path\":\"\",\"Caption\":\"\",\"Description\":\"\",\"AccessMask\":\"\",\"AllowMaximum\":\"\",\"MaximumAllowed\":\"\",\"InstallDate\":\"\",\"Status\":\"\"" >> ShareDetails-fmt.txt
  fi

  #error_check "ESMB ENFS"
  # send data to console
  # send_data $SHAREDETAILS_URL "$(job_json_generator ShareDetails.txt array Lines)"
  data_json_generator_iteration null ShareDetails-fmt.txt objectsArrayParsing Data > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file ShareDetails > $atatempdir/JSON/ShareDetails.json


  # System information
  LSB_RELEASE=$(which lsb_release)
  RPM_QUERY=$(rpm -qa --queryformat '%{VERSION}.%{RELEASE}\n' '(redhat|sl|slf|centos|oraclelinux)-release' | sed 's/[a-z A-Z]//g ; s/\.\././g' | cut -d. -f-2)
  uname -n | awk '{ print "Hostname: " $1}' >> SystemInfo.txt 2>&1
  suf=$(cat /etc/resolv.conf | awk '/search/ {print $2}')
  if [[ -z $suf ]]; then
  	echo "Suffix: $(hostname -d)" >> SystemInfo.txt 2>&1
    echo "\"PrimaryDnsSuffix\":\"$(hostname -d)\"" >>SystemInfo-fmt.txt
  else
  	echo "Suffix: $(cat /etc/resolv.conf | awk '/search/ {print $2}')" >> SystemInfo.txt 2>&1
    echo "\"PrimaryDnsSuffix\":\"$(cat /etc/resolv.conf | awk '/^search/ {print $2}')\"" >>SystemInfo-fmt.txt
  fi
  echo "Domain Name: $(hostname -d)" >> SystemInfo.txt 2>&1
  echo "\"DomainName\":\"$(hostname -d)\"" >> SystemInfo-fmt.txt
  uname -a | awk '{ print "Kernel Version: " $3}' >> SystemInfo.txt 2>&1
  if [ -f /etc/redhat-release ]; then
  	OpSys="REDHAT"
  	cat /etc/*{release,version} | grep -i centos > /dev/null 2>&1
  	if [ $? = 0 ]; then
  		echo "OS: CentOS" >> SystemInfo.txt 2>&1
      echo "\"OsName\":\"CentOS\"">> SystemInfo-fmt.txt
  		OS_rhel="CentOS"
    elif [ -f /etc/oracle-release ]; then
      echo "OS: Oracle Linux" >> SystemInfo.txt 2>&1
			echo "\"OsName\":\"Oracle Linux\"">> SystemInfo-fmt.txt
      OS_rhel="Oracle Linux"
  	else
  		echo "OS: Red Hat Enterprise Linux Server" >> SystemInfo.txt 2>&1
        echo "\"OsName\":\"Red Hat Enterprise Linux Server\"">> SystemInfo-fmt.txt
  		OS_rhel="Red Hat"
  	fi
  	if [ ! -z $LSB_RELEASE ] && ! echo $LSB_RELEASE | grep -i no; then
  		OSV=$($LSB_RELEASE -r | awk '{print $2}')
  	else
  		OSV=$RPM_QUERY
  	fi
  	if [ -z $OSV ]; then
  		OSV=$(cat /etc/redhat-release | grep -Eio '([0-9]+.+[0-9])')
  	fi
  	echo "OS Version: $OSV" >> SystemInfo.txt 2>&1
    echo "\"OsVersion\":\"$OSV\"" >>  SystemInfo-fmt.txt
  	echo "Distributor ID: $OS_rhel" >> SystemInfo.txt
    echo "\"OsManufacturer\":\"$OS_rhel\"" >> SystemInfo-fmt.txt

  fi
  $SUDO dumpe2fs $(mount | awk '/ \/ / {print $1}') | grep created | sed -e 's/Filesystem created/OS Installation date/g' >> SystemInfo.txt
  if [ -f /etc/debian_version ]; then
  	cat /etc/*{release,version} | grep -i ubuntu > /dev/null 2>&1
  	if [ $? = 0 ]; then
  	 OS_Distro=ubuntu
  	else
  	 OS_Distro=debian
  	fi
  	case $OS_Distro in
  		ubuntu)
    		OpSys="UBUNTU"
    		echo "OS: $(cat /etc/*{release,version} 2>/dev/null | grep -Ei 'distrib_description' | cut -d\" -f2)" >>  SystemInfo.txt 2>&1
    		echo "Distributor ID: Canonical" >> SystemInfo.txt
    		echo "OS Version: $(lsb_release -r 2>/dev/null | awk '{print $2}')" >> SystemInfo.txt 2>&1
        echo "\"OsName\":\"$(cat /etc/*{release,version} 2>/dev/null | grep -Ei 'distrib_description' | cut -d\" -f2)\"" >>  SystemInfo-fmt.txt 2>&1
    		echo "\"OsManufacturer\":\"Canonical\"" >> SystemInfo.txt
    		echo "\"OsVersion\":\"$(lsb_release -r 2>/dev/null | awk '{print $2}')\"" >> SystemInfo-fmt.txt 2>&1
  		;;
  		debian)
    		OpSys="DEBIAN"
    		if cat /etc/debian_version|grep ^6 > /dev/null 2>&1; then
    			echo "OS: Debian Squeeze" >>  SystemInfo.txt 2>&1
          echo "\"OsName\":\"Debian Squeez\"">> SystemInfo-fmt.txt
    		else
    			echo "OS: $(cat /etc/*{release,version} 2>/dev/null | grep -Ei 'pretty_name' | cut -d\" -f2)" >>  SystemInfo.txt 2>&1
          echo "\"OsName\":\"$(cat /etc/*{release,version} 2>/dev/null | grep -Ei 'pretty_name' | cut -d\" -f2)\"" >>  SystemInfo-fmt.txt 2>&1

    		fi
    		echo "Distributor ID: Debian" >> SystemInfo.txt
        echo "\"OsManufacturer\":\"Debian\"" >> SystemInfo-fmt.txt

    		echo "OS Version: $(cat /etc/debian_version)" >> SystemInfo.txt 2>&1
        echo "\"OsVersion\":\"$(cat /etc/debian_version)\"" >> SystemInfo-fmt.txt 2>&1

  		;;
  	esac
  fi
  if [ -f /etc/SuSE-release ]; then
  	OpSys="SUSE"
  	echo "OS: SuSE Linux Enterprise Server" >> SystemInfo.txt 2>&1
  	echo "OS Version: $(cat /etc/SuSE-release | awk '/VERSION/ {print $3}')" >> SystemInfo.txt 2>&1
  	echo "Distributor ID: SUSE (Micro Focus)" >> SystemInfo.txt
    echo "\"OsName\":\"SuSE Linux Enterprise Server\"" >> SystemInfo-fmt.txt 2>&1
  	echo "\"OsVersion\":\"$(cat /etc/SuSE-release | awk '/VERSION/ {print $3}')\"" >> SystemInfo-fmt.txt 2>&1
  	echo "\"OsManufacturer\":\"SUSE (Micro Focus)\"" >> SystemInfo-fmt.txt
  fi

  if $(cat /etc/os-release | grep "SUSE" | grep -q "15"); then
    OpSys="SUSE"
    echo "OS: SuSE Linux Enterprise Server" >> SystemInfo.txt 2>&1
    echo "OS Version: $(cat /etc/os-release | grep -Ei 'VERSION_ID' | cut -d\" -f2)" >> SystemInfo.txt 2>&1
    echo "Distributor ID: SUSE (Micro Focus)" >> SystemInfo.txt
    echo "\"OsName\":\"SuSE Linux Enterprise Server\"" >> SystemInfo-fmt.txt 2>&1
    echo "\"OsVersion\":\"$(cat /etc/os-release | grep -Ei 'VERSION_ID' | cut -d\" -f2)\"" >> SystemInfo-fmt.txt 2>&1
    echo "\"OsManufacturer\":\"SUSE (Micro Focus)\"" >> SystemInfo-fmt.txt
  fi

  AMAZON=$(cat /etc/system-release | awk '{print $1}')
  if [ $AMAZON = "Amazon" ]; then
  	OpSys="REDHAT"
  	echo "OS: Amazon Linux" >> SystemInfo.txt 2>&1
  	echo "OS Version: $(cat /etc/system-release | awk '{print $5}')" >> SystemInfo.txt 2>&1
  	echo "Distributor ID: Amazon" >> SystemInfo.txt
    echo "\"OsName\":\"Amazon Linux\"" >> SystemInfo-fmt.txt 2>&1
    echo "\"OsVersion\":\"$(cat /etc/system-release | awk '{print $5}')\"" >> SystemInfo-fmt.txt 2>&1
    echo "\"OsManufacturer\":\"Amazon\"" >> SystemInfo-fmt.txt
  fi

  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> SystemInfo.txt 2>&1
  which dmidecode > /dev/null 2>&1
  if [ $? = 0 ]; then
  	BIOVEN=$($SUDO dmidecode -s bios-vendor)
  	if [ -z "$BIOVEN" ]; then
  		BIOVEN="Bios Information is not available in this system"
  	fi
  	BIOREL=$($SUDO dmidecode -s bios-release-date)
  	if [ -z "$BIOREL" ]; then
  		BIOREL="Bios Information is not available in this system"
  	fi
  	BIOVER=$($SUDO dmidecode -s bios-version)
  	if [ -z "$BIOVER" ]; then
  		BIOVER="Bios Information is not available in this system"
  	fi
    SYSTEMMODEL=$($SUDO dmidecode -s system-product-name)
    if [ -z "$SYSTEMMODEL" ]; then
      SYSTEMMODEL="SystemModel Information is not available in this system"
    fi
    SYSTEMUUID=$($SUDO dmidecode -s system-uuid)
    if [ -z "$SYSTEMUUID" ]; then
      SYSTEMUUID="SYSTEMUUID Information is not available in this system"
    fi

  	echo "Bios Vendor: $BIOVEN" >> SystemInfo.txt 2>&1
  	echo "Bios Release Date: $BIOREL " >> SystemInfo.txt 2>&1
  	echo "Bios Version: $BIOVER " >> SystemInfo.txt 2>&1
    echo "\"SystemManufacturer\": \"$BIOVEN\"" >> SystemInfo-fmt.txt 2>&1
  	echo "\"BiosVersion\":\"$BIOVER\"" >> SystemInfo-fmt.txt 2>&1
    echo "\"SystemModel\":\"$SYSTEMMODEL\"" >> SystemInfo-fmt.txt
    echo "\"ProductId\":\"$SYSTEMUUID\"" >> SystemInfo-fmt.txtelse

    which hwinfo
  	if [ $? = 0 ]; then
  		echo "Bios Vendor: $($SUDO hwinfo --bios | grep "BIOS Info:" -A 3| grep -i vendor| awk -F "\"" '{print $2}')" >> SystemInfo.txt 2>&1
  		echo "Bios Release Date: $($SUDO hwinfo --bios | grep "BIOS Info:" -A 3| grep -i date| awk -F "\"" '{print $2}')" >> SystemInfo.txt 2>&1
  		echo "Bios Version: $($SUDO hwinfo --bios | grep "BIOS Info:" -A 3| grep -i version| awk -F "\"" '{print $2}')" >> SystemInfo.txt 2>&1
      echo "\"SystemManufacturer\":\"$($SUDO hwinfo --bios | grep "BIOS Info:" -A 3| grep -i vendor| awk -F "\"" '{print $2}')\"" >> SystemInfo-fmt.txt 2>&1
      echo "\"BiosVersion\":\"$($SUDO hwinfo --bios | grep "BIOS Info:" -A 3| grep -i version| awk -F "\"" '{print $2}')\"" >> SystemInfo-fmt.txt 2>&1
      $SUDO hwinfo | awk -F":" '/Product:\ / {print $0}'|uniq |awk -F":" '/Product:\ / {print "\"SystemModel\":""\x22"$2"\x22}' >> SystemInfo-fmt.txt
      $SUDO hwinfo | awk  -F":" '/UUID:/ {print $0}'| uniq | awk  -F":" '/UUID:/ {print "\"ProductId\":""\x22"$2"\x22"}' >> SystemInfo-fmt.txt
    fi
  fi
  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> SystemInfo.txt 2>&1
  echo "System Locale:" >> SystemInfo.txt 2>&1
  echo "\"SystemLocale\":\"$(locale | awk -F"=" '/LANG/ {print $2}')\"" >> SystemInfo-fmt.txt
  echo "\"InputLocale\":\"$(locale | awk -F'[=.]' '/LANG/ {print $2}')\"" >> SystemInfo-fmt.txt
  locale >> SystemInfo.txt 2>&1
  date +%Z  | awk '{ print "TimeZone:" $1}' >> SystemInfo.txt 2>&1
  date +%Z  | awk '{ print "\"TimeZone\":""\x22"$1"\x22"}' >> SystemInfo-fmt.txt

  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> SystemInfo.txt 2>&1
  echo "Memory: " >> SystemInfo.txt 2>&1
  free -mt >> SystemInfo.txt 2>&1
  echo "- - - - - - - - - - - - - - - - - - - - - - -" >> SystemInfo.txt 2>&1
  free -mt | awk '/Mem/ {print "\"TotalPhysicalMemory\":""\x22"$2"MB""\x22"}' >> SystemInfo-fmt.txt
  free -mt | awk '/Mem/ {print "\"AvailablePhysicalMemory\":""\x22"$7"MB""\x22"}' >> SystemInfo-fmt.txt
  free -mt | awk '/Swap/ {print "\"VirtualMemoryMaxSize\":""\x22"$2"MB""\x22"}' >> SystemInfo-fmt.txt
  free -mt | awk '/Swap/ {print "\"VirtualMemoryAvailable\":""\x22"$4"MB""\x22"}' >> SystemInfo-fmt.txt
  free -mt | awk '/Swap/ {print "\"VirtualMemoryInUse\":""\x22"$3"MB""\x22"}' >> SystemInfo-fmt.txt
  isEnabled=$($SUDO iptables --list |grep -Eiv "chain|target")
  echo "\"FirewallEnabled\": $( [[ -z $isEnabled ]] && echo false || echo true)" >> SystemInfo-fmt.txt
  echo "\"SystemBootTime\":\"$(date -d "`cut -f1 -d. /proc/uptime` seconds ago")\"">> SystemInfo-fmt.txt
  isBoot=$(df -TP | grep -i /boot | awk '{print $7}')
  echo "\"BootDevice\":$( [[ -z $isBoot ]] && echo \"/\" || echo \"$isBoot\")" >> SystemInfo-fmt.txt
  echo "\"SystemDirectory\":\"\"" >> SystemInfo-fmt.txt
  echo "\"WindowsDirectory\":\"\"" >> SystemInfo-fmt.txt
  echo "\"OriginalInstallDate\":\"\"" >> SystemInfo-fmt.txt
  echo "\"RegisteredOrganization\":\"\"" >> SystemInfo-fmt.txt
  echo "\"RegisteredOwner\":\"\"" >> SystemInfo-fmt.txt
  echo "\"OsBuildType\":\"\"" >> SystemInfo-fmt.txt
  echo "\"OsConfiguration\":\"\"" >> SystemInfo-fmt.txt
  echo "\"PageFileLocations\":\"\"" >> SystemInfo-fmt.txt
  echo "\"ProxyServer\":\"\"" >> SystemInfo-fmt.txt
  echo "\"AixFirmwareLevel\":\"\"" >> SystemInfo-fmt.txt
  echo "\"AixConsoleLogin\":\"\"" >> SystemInfo-fmt.txt
  echo "\"AixAutoRestart\":\"\"" >> SystemInfo-fmt.txt
  echo "\"AixFullCore\":\"\"" >> SystemInfo-fmt.txt
  echo "\"AixFirmwareVersion\":\"\"" >> SystemInfo-fmt.txt
  echo "\"AixLparConfig\":\"\"" >> SystemInfo-fmt.txt

  echo "Network: " >> SystemInfo.txt 2>&1
  ifconfig -a | sed -e 's/Bcast/broadcast/g' | sed -e 's/Mask/netmask/g' >> SystemInfo.txt 2>&1
  for line in $(lspci | awk '/Ethernet/ {print $1}')
  do
  	for line in $(lspci -n | grep $line | awk '{print $3}')
  	do
  		lspci -vv -d $line >> SystemInfo.txt 2>&1
  	done
  done

	#checking error
  error_check "EDMI"
  #send_data $SYSTEMINFO_URL "$(job_json_generator SystemInfo.txt array SystemInfoFile ComputerSystemProduct.txt array ComputerSystemProductFile)"
  #data_json_generator $error SystemInfo.txt array SystemInfoFile ComputerSystemProduct.txt array ComputerSystemProductFile > $atatempdir/data-$$.json
  #json_generator $atatempdir/data-$$.json json_file ServerSystemInfo_SystemInfo > $atatempdir/JSON/ServerSystemInfo_SystemInfo.json
  data_json_generator_iteration "$error" SystemInfo-fmt.txt objectsArray Data > $atatempdir/data-$$.json
  sed -i 's/\[/\{/g' $atatempdir/data-$$.json ; sed -i 's/\]/\}/g' $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file ServerSystemInfo > $atatempdir/JSON/ServerSystemInfo.json

  # lastboot
  which date > /dev/null 2>&1
  if [ $? = 0 ]; then
    if [ -f /proc/uptime ]; then
      date -d "`cut -f1 -d. /proc/uptime` seconds ago" >> Lastboot.txt 2>&1
    else
      echo "******************" | tee -a $log_file
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EUTIM: Error retrieving lastboot information: File /proc/uptime not found." | tee -a $log_file
      echo "******************" | tee -a $log_file
      touch Lastboot.txt 2>&1
    fi

  else
    echo "******************" | tee -a $log_file
    echo "($(date -u +"%m/%d/%Y %H:%M:%S")) ELBOOT: Error retrieving lastboot information: Command date not found." | tee -a $log_file
    echo "******************" | tee -a $log_file
    touch Lastboot.txt 2>&1
  fi
  #error_check "ELBOOT EUTIM"
  # send_data $BOOTTIME_URL "$(job_json_generator Lastboot.txt file Content)"
  #data_json_generator $error Lastboot.txt file Content > $atatempdir/data-$$.json
  #json_generator $atatempdir/data-$$.json json_file ServerSystemInfo_BootTime > $atatempdir/JSON/ServerSystemInfo_BootTime.json


  which docker > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    mkdir -p $atatempdir/DOCKER/NETSTAT
    docker ps >> $atatempdir/DOCKER/Docker-system.txt
  	for image in $(docker ps | grep -v COMMAND| awk '{print $1}'); do
  	  docker inspect -f "{{ .HostConfig.Links }}" ${image} >> $atatempdir/DOCKER/Docker-system.txt
  		LSB_RELEASE=$(docker exec ${image} which lsb_release)
  		RPM_QUERY=$(docker exec ${image} rpm -qa --queryformat '%{VERSION}.%{RELEASE}\n' '(redhat|sl|slf|centos|oraclelinux)-release' | sed 's/[a-z A-Z]//g ; s/\.\././g' | cut -d. -f-2)
  		docker exec ${image} uname -n | awk '{ print "Hostname: " $1}' >> $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		suf=$(docker exec ${image} cat /etc/resolv.conf | awk '/search/ {print $2}')
  		if [[ -z $suf ]]; then
  		 echo "Suffix: $(docker exec ${image} hostname -d)" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		else
  		 echo "Suffix: $(docker exec ${image} cat /etc/resolv.conf | awk '/search/ {print $2}')" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		fi
  		echo "Domain Name: $(docker exec ${image} hostname -d)" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		docker exec ${image} uname -a | awk '{ print "Kernel Version: " $3}' >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		docker exec ${image} cat /etc/redhat-release >/dev/null 2>&1
  		if [ $? = 0 ]; then
        docker exec ${image} cat /etc/*{release,version} | grep -i centos > /dev/null 2>&1
  			if [ $? = 0 ]; then
  				echo "OS: CentOS" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  				OS_rhel="CentOS"
  			else
  				echo "OS: Red Hat Enterprise Linux Server" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  				OS_rhel="Red Hat"
  			fi
  		 if [ ! -z $LSB_RELEASE ] && ! echo $LSB_RELEASE | grep -i no; then
  			 OSV=$(docker exec ${image} $LSB_RELEASE -r | awk '{print $2}')
  		 else
  			 OSV=$RPM_QUERY
  		 fi
  		 if [ -z $OSV ]; then
  			 OSV=$(docker exec ${image} cat /etc/redhat-release | grep -Eio '([0-9]+.+[0-9])')
  		 fi
  		 echo "OS Version: $OSV" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		 echo "Distributor ID: $OS_rhel" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt
  		fi
  		docker exec --privileged=true ${image} dumpe2fs $(docker exec --privileged=true ${image} mount | awk '/ \/ / {print $1}') | grep created | sed -e 's/Filesystem created/OS Installation date/g' >>  $atatempdir/DOCKER/SystemInfo-${image}.txt
  		docker exec ${image} cat /etc/debian_version > /dev/null 2>&1
  		if [ $? = 0 ]; then
        docker exec ${image} cat /etc/*{release,version} | grep -i ubuntu > /dev/null 2>&1
  			if [ $? = 0 ]; then
          OS_Distro=ubuntu
  			else
          OS_Distro=debian
  			fi
  			case $OS_Distro in
  			 ubuntu)
    			 echo "OS: $(docker exec ${image} cat /etc/*{release,version} 2>/dev/null | grep -Ei 'distrib_description' | cut -d\" -f2)" >>   $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
    			 echo "Distributor ID: Canonical" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt
    			 echo "OS Version: $(docker exec ${image} lsb_release -r 2>/dev/null | awk '{print $2}')" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  			 ;;
  			 debian)
    			 echo "OS: $(docker exec ${image} cat /etc/*{release,version} 2>/dev/null | grep -Ei 'pretty_name' | cut -d\" -f2)" >>   $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
    			 echo "Distributor ID: Debian" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt
    			 echo "OS Version: $(docker exec ${image} cat /etc/debian_version)" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  			 ;;
  		 esac
  		fi
  		docker exec ${image} cat /etc/SuSE-release > /dev/null 2>&1
  		if [ $? = 0 ]; then
  		 echo "OS: SuSE Linux Enterprise Server" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		 echo "OS Version: $(docker exec ${image} cat /etc/SuSE-release | awk '/VERSION/ {print $3}')" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		 echo "Distributor ID: SUSE (Micro Focus)" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt
  		fi
  		AMAZON=$(cat /etc/system-release | awk '{print $1}')
  		if [ $AMAZON = "Amazon" ]; then
  			echo "OS: Amazon Linux" >> $atatempdir/DOCKER/SystemInfo-${image}.txt
  			echo "OS Version: $(cat /etc/system-release | awk '{print $5}')" >> $atatempdir/DOCKER/SystemInfo-${image}.txt
  			echo "Distributor ID: Amazon" >> $atatempdir/DOCKER/SystemInfo-${image}.txt
  		fi
  		echo "- - - - - - - - - - - - - - - - - - - - - - -" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		docker exec --privileged=true ${image} which dmidecode
  		if [ $? = 0 ]; then
        echo "Bios Vendor: $(docker exec --privileged=true ${image} dmidecode -s bios-vendor)" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
        echo "Bios Release Date: $(docker exec --privileged=true ${image} dmidecode -s bios-release-date)" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
        echo "Bios Version: $(docker exec --privileged=true ${image} dmidecode -s bios-version)" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		else
  		 docker exec --privileged=true ${image} which hwinfo
  		 if [ $? = 0 ]; then
  			 echo "Bios Vendor: $(docker exec --privileged=true ${image} hwinfo --bios | grep "BIOS Info:" -A 3| grep -i vendor| awk -F "\"" '{print $2}')" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  			 echo "Bios Release Date: $(docker exec --privileged=true ${image} hwinfo --bios | grep "BIOS Info:" -A 3| grep -i date| awk -F "\"" '{print $2}')" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  			 echo "Bios Version: $(docker exec --privileged=true ${image} hwinfo --bios | grep "BIOS Info:" -A 3| grep -i version| awk -F "\"" '{print $2}')" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		 fi
  		fi
  		echo "- - - - - - - - - - - - - - - - - - - - - - -" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		echo "System Locale:" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		docker exec ${image} locale >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		docker exec ${image} date +%Z  | awk '{ print "TimeZone:" $1}' >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		echo "- - - - - - - - - - - - - - - - - - - - - - -" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		echo "Memory: " >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		docker exec ${image} free -mt >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		echo "- - - - - - - - - - - - - - - - - - - - - - -" >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		echo "Network: " >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		docker exec ${image} ip a >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
  		for line1 in $(docker exec ${image}  lspci | awk '/Ethernet/ {print $1}')
  		do
        for line in $(docker exec ${image}  lspci -n | grep $line1 | awk '{print $3}')
        do
          docker exec ${image} lspci -vv -d $line >>  $atatempdir/DOCKER/SystemInfo-${image}.txt 2>&1
        done
  		done

  		#Getting IP information for docker containers
  		for ipcdock in $(docker exec ${image} ip a | grep inet | grep -v 127.0.0.1 | grep -v inet6| awk '{print $2}'|awk -F "/" '{print $1}'); do
  			if [ -z $ipcdock ]; then
  				echo "N/A-${image}" >> $atatempdir/DOCKER/IpConfig-${image}.txt
  			else
  				echo "${ipcdock}-${image}" >> $atatempdir/DOCKER/IpConfig-${image}.txt
  			fi
  		done

  		#Getting network information for docker containers
  		for eth in $(docker exec ${image} ip a| grep "^[0-9]" | awk -F ":" '{print $2}'| cut -d" " -f2|grep -v lo| cut -d"@" -f1); do
  			ipeth=$(docker exec ${image} ip a s ${eth} |grep -w inet| cut -d"/" -f1|cut -d" " -f6)
  			#Converting the netmask
  			nmaskn=$(docker exec ${image} ip a s ${eth} |grep -w inet| cut -d"/" -f2|cut -d" " -f1)
  			set -- $(( 5 - ($nmaskn / 8) )) 255 255 255 255 $(( (255 << (8 - ($nmaskn % 8))) & 255 )) 0 0 0
   			[ $1 -gt 1 ] && shift $1 || shift
   			nmask=$(echo ${1-0}.${2-0}.${3-0}.${4-0})

  			macadd=$(docker exec ${image} ip a s ${eth} |grep link/| cut -d" " -f6)
  		  echo "$eth;$ipeth;$nmask;$macadd" >> $atatempdir/DOCKER/IFConfig-${image}.txt
  		done
    done
    docker_array_data="["
    for i in $(docker ps --format "{{.ID}}"); do
      [[ $docker_array_data != "[" ]] && docker_array_data="${docker_array_data},"
      docker_array_data="${docker_array_data}$(docker_json_data $i)"
      # [[ ! -z $DOCKER_DATA ]] && send_data $DOCKER_URL $DOCKER_DATA
    done
    docker_array_data="${docker_array_data}]"
    echo $docker_array_data > $atatempdir/docker-data-$$.json
    docker ps -a --format "\"ContainerId\":\"{{.ID}}\",\"ImageName\":\"{{.Image}}\",\"DockerCommand\":{{.Command}},\"ContainerCreated\":\"{{.CreatedAt}}\",\"Status\":\"{{.Status}}\",\"Ports\":\"{{.Ports}}\",\"ContainerNames\":\"{{.Names}}\",\"isDelete\":false" >> docker-info-fmt.txt

    #data_json_generator null $atatempdir/docker-data-$$.json json_file Containers > $atatempdir/data-$$.json
    #json_generator $atatempdir/data-$$.json json_file Docker_ContainerInfo > $atatempdir/JSON/Docker_ContainerInfo.json
    data_json_generator_iteration null docker-info-fmt.txt objectsArrayParsing Data > $atatempdir/data-$$.json
    json_generator $atatempdir/data-$$.json json_file DockerDetails > $atatempdir/JSON/DockerDetails.json
  fi

  #IP Config information
  IFCONFIG_FILE=$atatempdir/IFConfig.txt
  INTERFACES_FILE=$atatempdir/temp_interfaces.txt
  IsFallback=false
  which ifconfig 2> /dev/null 2>&1
  if [ $? -eq 0 ]; then
    ifconfig -a | sed -e 's/Bcast/broadcast/g' | sed -e 's/Mask/netmask/g' | sed -e 's/ether/HWaddr/g' >> $IFCONFIG_FILE 2>&1
  elif [ ! -z $(which ip 2>/dev/null) ]; then
    IsFallback=true
    ip addr | sed -e '/inet/ { s/brd/broadcast/g }' | sed -e 's,link/ether,HWaddr,g' >> $IFCONFIG_FILE 2>&1
    ip -o addr show | awk '{ print $2 }' | uniq | grep -vw ^lo > $INTERFACES_FILE
  else
    echo "******************" | tee -a $log_file
    echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EIFCO: Error retrieving network information: Commands ip/ifconfig not found." | tee -a $log_file

    echo "******************" | tee -a $log_file
    echo "\"Nic\":\"\",\"ConnectionName\":\"\",\"DhcpEnabled\":false,\"DhcpServer\":\"\",\"Ipv4Address\":\"\",\"Ipv6Address\":\"\",\"SubnetMask\":\"\",\"MacAddress\":\"\",\"DnsServers\":\"\",\"DefaultGateway\":\"\",\"DnsDomain\":\"\"">> IFconfig-fmt.txt

  fi

  if [ ! -f  $INTERFACES_FILE ] && [ ! -z $(which netstat 2>/dev/null) ]; then
    netstat -i |grep -v MTU |grep -vi kernel| grep  -iv 'iface\|lo' | awk '{print $1}' > $INTERFACES_FILE
  fi

	echo "-----------------------------" >> $IFCONFIG_FILE
	counter=1
	case $OpSys in
		DEBIAN|UBUNTU)
			for IFACE in $(cat $INTERFACES_FILE)
			do
        if [[ $IsFallback == true ]];then
          IPfmt=$(ip addr show $IFACE | grep  'inet' | grep -v inet6 | awk '{print $2}')
          IP6fmt=$(ip addr show $IFACE | grep  'inet6' | awk '{print $2}')
          IPADD=$(echo $IPfmt | awk -F"/" '{print $1}' )
          IP6ADD=$(echo $IP6fmt | awk -F"/" '{print $1}')
          SUBMASK=$(echo $IPfmt | awk -F"/" '{print $2}' )
          #SUB6MASK=$(echo $IP6fmt | awk -F"/" '{print $2}' )
          HWADDR=$(ip addr show $IFACE | grep "link/ether" | awk '{print $2}')
        else
          #IPfmt=$(ifconfig $IFACE | grep inet | grep -v inet6 | awk -F"['':]" '{print $2}'| awk '{print $1}')
          #IP6fmt=$(ifconfig eth0 | grep inet6 | awk -F"['':]" '{print $3}'| awk '{print $1}')
          IPADD=$(ifconfig $IFACE| grep inet| grep -v inet6 |  awk  -F "['':]" '{print $2}' | awk '{print $1}' )
          IP6ADD=$(ifconfig $IFACE | grep inet6 |  awk   '{print $3}' | awk -F"/" '{print $1}')
          SUBMASK=$(ifconfig $IFACE |  grep inet|grep -v inet6  |  awk  -F "['':]" '{print $4}')
          #SUB6MASK=$(echo $IP6fmt | awk -F"/" '{print $2}' )
          HWADDR=$(ifconfig $IFACE | grep -i Hwaddr| awk '{print $5}')
          if [[ -z $IPADD ]] || [[ -z $IP6ADD ]] || [[ -z $SUBMASK ]] || [[ -z $HWADDR ]];then
            IPADD=$(ifconfig $IFACE| grep inet| grep -v inet6 | awk '{print $2}' )
            IP6ADD=$( ifconfig $IFACE| grep inet6 |  awk   '{print $2}')
            SUBMASK=$(ifconfig $IFACE |  grep inet|grep -v inet6  |  awk   '{print $4}')
            HWADDR=$( ifconfig $IFACE |grep -i ether| awk '{print $2}')
          fi
        fi
				DNS=$(cat /etc/network/interfaces | awk 'BEGIN{RS=ORS="\n\n";FS=OFS="\n"}/iface '"$IFACE"'/' | awk '/dns-nameservers/ {print $2}'  ORS=","| sed 's/"//g'| sed 's/.$//g')
				if [ -z "$DNS" ]; then
					DNS=$(cat /etc/resolv.conf | awk '/nameserver/ {print $2}' ORS=","| sed 's/.$//g')
          DNSdomain=$(cat /etc/resolv.conf | awk '/^search/ {print $2}' ORS=","| sed 's/.$//g')
          which route > /dev/null 2>&1
          if [[ $? -eq 0 ]];then
            DefaultGw=$( route | grep -i $IFACE | grep -i default)
          else
            DefaultGw=$( ip route | grep -i $IFACE | grep -i default | awk '{print $3}')
          fi

          if [ -z "$DNSdomain" ]; then
				  	 echo -e "\nDNSdomain for NIC $IFACE: No specific DNSDomain" >> $IFCONFIG_FILE
          else
            echo -e "\nDNSdomain for NIC $IFACE: $DNSdomain" >> $IFCONFIG_FILE
          fi
					if [ -z $DNS ]; then
					 echo -e "\nDNS for NIC $IFACE: No specific DNS" >> $IFCONFIG_FILE
					else
					 echo -e "\nDNS for NIC $IFACE: $DNS" >> $IFCONFIG_FILE
					fi
				else
					echo -e "\nDNS for NIC $IFACE: $DNS" >> $IFCONFIG_FILE
				fi
				ethtype=$(lspci | grep -i ethernet| sed -n "${counter}p"|awk -F"ler:" '{print $2}')
				if [ -z $ethtype ]; then  > /dev/null 2>&1
					echo "NIC Model: Not found in the system"  >> $IFCONFIG_FILE
				else
					echo "NIC Model:"$ethtype >> $IFCONFIG_FILE
				fi
        echo "\"Nic\":\"$IFACE\",\"ConnectionName\":\"\",\"DhcpEnabled\":false,\"DhcpServer\":\"\",\"Ipv4Address\":\"$IPADD\",\"Ipv6Address\":\"$IP6ADD\",\"SubnetMask\":\"$SUBMASK\",\"MacAddress\":\"$HWADDR\",\"DnsServers\":\"$DNS\",\"DefaultGateway\":\"$DefaultGw\",\"DnsDomain\":\"$DNSdomain\"">> IFconfig-fmt.txt
				counter=$((counter+1))
			done
		;;
		REDHAT)
			for IFACE in $(cat $INTERFACES_FILE)
			do
        if [[ $IsFallback == true ]];then
          IPfmt=$(ip addr show $IFACE | grep  'inet' | grep -v inet6 | awk '{print $2}')
          IP6fmt=$(ip addr show $IFACE | grep  'inet6' | awk '{print $2}')
          IPADD=$(echo $IPfmt | awk -F"/" '{print $1}' )
          IP6ADD=$(echo $IP6fmt | awk -F"/" '{print $1}')
          SUBMASK=$(echo $IPfmt | awk -F"/" '{print $2}' )
          #SUB6MASK=$(echo $IP6fmt | awk -F"/" '{print $2}' )
          HWADDR=$(ip addr show $IFACE | grep "link/ether" | awk '{print $2}')
        else
          #IPfmt=$(ifconfig $IFACE | grep inet | grep -v inet6 | awk -F"['':]" '{print $2}'| awk '{print $1}')
          #IP6fmt=$(ifconfig eth0 | grep inet6 | awk -F"['':]" '{print $3}'| awk '{print $1}')
          IPADD=$(ifconfig $IFACE| grep inet| grep -v inet6 |  awk  -F "['':]" '{print $2}' | awk '{print $1}' )
          IP6ADD=$(ifconfig $IFACE | grep inet6 |  awk   '{print $3}' | awk -F"/" '{print $1}')
          SUBMASK=$(ifconfig $IFACE |  grep inet|grep -v inet6  |  awk  -F "['':]" '{print $4}')
          #SUB6MASK=$(echo $IP6fmt | awk -F"/" '{print $2}' )
          HWADDR=$(ifconfig eth0 | grep -i Hwaddr| awk '{print $5}')
          if [[ -z $IPADD ]] || [[ -z $IP6ADD ]] || [[ -z $SUBMASK ]] || [[ -z $HWADDR ]];then
            IPADD=$(ifconfig $IFACE| grep inet| grep -v inet6 | awk '{print $2}' )
            IP6ADD=$( ifconfig $IFACE| grep inet6 |  awk   '{print $2}')
            SUBMASK=$(ifconfig $IFACE |  grep inet|grep -v inet6  |  awk   '{print $4}')
            HWADDR=$( ifconfig $IFACE |grep -i ether| awk '{print $2}')
          fi
        fi
				DNS=$(cat /etc/sysconfig/network-scripts/ifcfg-$IFACE | grep ^DNS | cut -d= -f2| awk '{print $0}'  ORS=","| sed 's/"//g'| sed 's/.$//g')
				if [ -z "$DNS" ]; then
					DNS=$(cat /etc/resolv.conf | awk '/nameserver/ {print $2}' ORS=","| sed 's/.$//g')
          DNSdomain=$(cat /etc/resolv.conf | awk '/^search/ {print $2}' ORS=","| sed 's/.$//g')
          if [ -z "$DNSdomain" ]; then
				  	 echo -e "\nDNSdomain for NIC $IFACE: No specific DNSDomain" >> $IFCONFIG_FILE
          else
            echo -e "\nDNSdomain for NIC $IFACE: $DNSdomain" >> $IFCONFIG_FILE
          fi
          which route > /dev/null 2>&1
          if [[ $? -eq 0 ]];then
            DefaultGw=$( route | grep -i $IFACE | grep -i default)
          else
            DefaultGw=$( ip route | grep -i $IFACE | grep -i default | awk '{print $3}')
          fi
					if [ -z "$DNS" ]; then
					 echo -e "\nDNS for NIC $IFACE: No specific DNS" >> $IFCONFIG_FILE
					else
					 echo -e "\nDNS for NIC $IFACE: $DNS" >> $IFCONFIG_FILE
					fi
				else
					echo -e "\nDNS for NIC $IFACE: $DNS" >> $IFCONFIG_FILE
				fi
				ethtype=$(lspci | grep -i ethernet| sed -n "${counter}p"|awk -F"ler:" '{print $2}')
				if [ -z $ethtype ]; then  > /dev/null 2>&1
					echo "NIC Model: Not found in the system"  >> $IFCONFIG_FILE
				else
					echo "NIC Model:"$ethtype >> $IFCONFIG_FILE
				fi
        echo "\"Nic\":\"$IFACE\",\"ConnectionName\":\"\",\"DhcpEnabled\":false,\"DhcpServer\":\"\",\"Ipv4Address\":\"$IPADD\",\"Ipv6Address\":\"$IP6ADD\",\"SubnetMask\":\"$SUBMASK\",\"MacAddress\":\"$HWADDR\",\"DnsServers\":\"$DNS\",\"DefaultGateway\":\"$DefaultGw\",\"DnsDomain\":\"$DNSdomain\"">> IFconfig-fmt.txt
				counter=$((counter+1))
			done
		;;
		SUSE)
			for IFACE in $(cat $INTERFACES_FILE)
			do
        if [[ $IsFallback == true ]];then
          IPfmt=$(ip addr show $IFACE | grep  'inet' | grep -v inet6 | awk '{print $2}')
          IP6fmt=$(ip addr show $IFACE | grep  'inet6' | awk '{print $2}')
          IPADD=$(echo $IPfmt | awk -F"/" '{print $1}' )
          IP6ADD=$(echo $IP6fmt | awk -F"/" '{print $1}')
          SUBMASK=$(echo $IPfmt | awk -F"/" '{print $2}' )
          #SUB6MASK=$(echo $IP6fmt | awk -F"/" '{print $2}' )
          HWADDR=$(ip addr show $IFACE | grep "link/ether" | awk '{print $2}')
        else
          #IPfmt=$(ifconfig $IFACE | grep inet | grep -v inet6 | awk -F"['':]" '{print $2}'| awk '{print $1}')
          #IP6fmt=$(ifconfig eth0 | grep inet6 | awk -F"['':]" '{print $3}'| awk '{print $1}')
          IPADD=$(ifconfig $IFACE| grep inet| grep -v inet6 |  awk  -F "['':]" '{print $2}' | awk '{print $1}' )
          IP6ADD=$(ifconfig $IFACE | grep inet6 |  awk   '{print $3}' | awk -F"/" '{print $1}')
          SUBMASK=$(ifconfig $IFACE |  grep inet|grep -v inet6  |  awk  -F "['':]" '{print $4}')
          #SUB6MASK=$(echo $IP6fmt | awk -F"/" '{print $2}' )
          HWADDR=$(ifconfig eth0 | grep -i Hwaddr| awk '{print $5}')
          if [[ -z $IPADD ]] || [[ -z $IP6ADD ]] || [[ -z $SUBMASK ]] || [[ -z $HWADDR ]];then
            IPADD=$(ifconfig $IFACE| grep inet| grep -v inet6 | awk '{print $2}' )
            IP6ADD=$( ifconfig $IFACE| grep inet6 |  awk   '{print $2}')
            SUBMASK=$(ifconfig $IFACE |  grep inet|grep -v inet6  |  awk   '{print $4}')
            HWADDR=$( ifconfig $IFACE |grep -i ether| awk '{print $2}')
          fi
        fi
				DNS=$(cat /etc/sysconfig/network/ifcfg-$IFACE /etc/sysconfig/network-scripts/ifcfg-$IFACE 2>/dev/null | grep ^DNS | uniq | cut -d= -f2| awk '{print $0}' ORS=","| sed 's/"//g'| sed 's/.$//g')
				if [ -z "$DNS" ]; then
					DNS=$(cat /etc/resolv.conf | awk '/nameserver/ {print $2}' ORS=","| sed 's/.$//g')
          DNSdomain=$(cat /etc/resolv.conf | awk '/^search/ {print $2}' ORS=","| sed 's/.$//g')
          if [ -z "$DNSdomain" ]; then
				  	 echo -e "\nDNSdomain for NIC $IFACE: No specific DNSDomain" >> $IFCONFIG_FILE
          else
            echo -e "\nDNSdomain for NIC $IFACE: $DNSdomain" >> $IFCONFIG_FILE
          fi
          which route > /dev/null 2>&1
          if [[ $? -eq 0 ]];then
            DefaultGw=$( route | grep -i $IFACE | grep -i default)
          else
            DefaultGw=$( ip route | grep -i $IFACE | grep -i default | awk '{print $3}')
          fi
					if [ -z "$DNS" ]; then
					 echo -e "\nDNS for NIC $IFACE: No specific DNS" >> $IFCONFIG_FILE
					else
					 echo -e "\nDNS for NIC $IFACE: $DNS" >> $IFCONFIG_FILE
					fi
				else
					echo -e "\nDNS for NIC $IFACE: $DNS" >> $IFCONFIG_FILE
				fi
				ethtype=$(lspci | grep -i ethernet| sed -n "${counter}p"|awk -F"ler:" '{print $2}')
				if [ -z $ethtype ]; then  > /dev/null 2>&1
					echo "NIC Model: Not found in the system"  >> $IFCONFIG_FILE
				else
					echo "NIC Model:"$ethtype >> $IFCONFIG_FILE
				fi
        echo "\"Nic\":\"$IFACE\",\"ConnectionName\":\"\",\"DhcpEnabled\":false,\"DhcpServer\":\"\",\"Ipv4Address\":\"$IPADD\",\"Ipv6Address\":\"$IP6ADD\",\"SubnetMask\":\"$SUBMASK\",\"MacAddress\":\"$HWADDR\",\"DnsServers\":\"$DNS\",\"DefaultGateway\":\"$DefaultGw\",\"DnsDomain\":\"$DNSdomain\"">> IFconfig-fmt.txt
				counter=$((counter+1))
			done
		;;
	esac
  cat $IFCONFIG_FILE
  #error_check "EIFCO"
  error_check "EIFCO"
	# send_data $NETWORKINFO_URL "$(job_json_generator $IFCONFIG_FILE array Lines)"
	#data_json_generator $error $IFCONFIG_FILE array Lines $IsFallback boolean IsFallback > $atatempdir/data-$$.json
	#json_generator $atatempdir/data-$$.json json_file NetworkInformation_Host > $atatempdir/JSON/NetworkInformation_Host.json
  data_json_generator_iteration "$error" IFconfig-fmt.txt objectsArrayParsing Data > $atatempdir/data-$$.json
	json_generator $atatempdir/data-$$.json json_file NicDetails> $atatempdir/JSON/NicDetails.json
  #defining IPN for validation and discovery tar files
  ipn=$( cat  $IFCONFIG_FILE |egrep '(eth|ens)'|grep inet |head -1| awk '{print $2}'|awk -F "/" '{print $1}')
    if [[ -z $ipn ]];then
      ipn=$(ifconfig | egrep '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
    fi
  #firewall
  which iptables > /dev/null 2>&1
  if [ $? = 0 ]; then
  	$SUDO iptables -L -n >> firewall.txt 2>&1
    $SUDO iptables -L -n | grep -iv prot >> firewall-fmt.txt
    rulecount=$($SUDO iptables -L -n | grep -iv prot | sed '/^$/d'| wc -l)
    if [[ $rulecount -gt 3 ]]; then
      while read line;do
        echo $line | grep -iq chain
        if [[ $? -eq 0 ]];then
          chain=$(echo $line | awk '{print $2}')
          chainpolicy=$(echo $line | awk '{print $4}'| awk -F ")" '{print $1}')
        else
          echo $line | awk -v ch=$chain -v chp=$chainpolicy '{print "\"ChainName\":""\x22"ch"\x22,\"ChainPolicy\":""\x22"chp"\x22,\"Target\":""\x22"$1"\x22,\"Proto\":""\x22"$2"\x22,\"Opt\":""\x22"$3"\x22,\"Source\":""\x22"$4"\x22,\"Destination\":""\x22"$5"\x22,\"Port\":""\x22"$7"\x22,\"State\":""\x22"$9"\x22"}'>> firewallparsing.txt
        fi
      done < firewall-fmt.txt
    else
      touch firewallparsing.txt
    fi
  else
  	echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EIPT: Error retrieving firewall information: Command iptables not found." | tee -a $log_file

  	echo "******************" | tee -a $log_file
  	touch firewall.txt 2>&1
    #echo "\"ChainName\":\"\",\"ChainPolicy\":\"\",\"Target\":\"\",\"Proto\":\"\",\"Opt\":\"\",\"Source\":\"\",\"Destination\":\"\",\"Port\":\"\",\"State\":\"\"" >> firewall.txt 2>&1
    touch firewallparsing.txt
  fi

  #error_check "EIPT"
  # send_data $LINUXRULES_URL "$(job_json_generator firewall.txt array Lines)"
  #data_json_generator $error firewall.txt array Lines > $atatempdir/data-$$.json
  #json_generator $atatempdir/data-$$.json json_file FirewallRules_LinuxRules > $atatempdir/JSON/FirewallRules_LinuxRules.json
  data_json_generator_iteration null firewallparsing.txt objectsArrayParsing Data > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file LinuxFirewall > $atatempdir/JSON/LinuxFirewall.json

  #TLSVersion Information
  which openssl > /dev/null 2>&1
  if [ $? = 0 ]; then
    openssl ciphers -v 'ALL:COMPLEMENTOFALL'| awk '{print $2}' | egrep -i '(ssl|tls)' | sort -u| tr '\n' ',' | sed 's/.$/\n/g' >TLSVersion.txt
    openssl ciphers -v 'ALL:COMPLEMENTOFALL'| awk '{print $2" "$1}' | egrep -i '(ssl|tls)' |awk '{print $2}'| sort -u| tr '\n' ',' | sed 's/.$/\n/g' >>TLSVersion.txt
    echo `openssl ciphers -v 'ALL:COMPLEMENTOFALL'| awk '{print $2}' | egrep -i '(ssl|tls)' | sort -u| tr '\n' ','` | sed 's/.$//g' | awk '{ print "\"TLSVersion\":\""$0"\""}' >TLSVersion-fmt1.txt
    echo `openssl ciphers -v 'ALL:COMPLEMENTOFALL'| awk '{print $2" "$1}' | egrep -i '(ssl|tls)' |awk '{print $2}'| sort -u| tr '\n' ',' `| sed 's/.$//g' | awk '{print "\"Ciphers\":\""$0"\""}' >> TLSVersion-fmt1.txt
    cat TLSVersion-fmt1.txt | tr '\n' ','| sed 's/.$//g' >TLSVersion-fmt.txt
  else
    echo "******************" | tee -a $log_file
  	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Error retrieving SSL/TLS information: Command openssl not found." | tee -a $log_file
  	echo "******************" | tee -a $log_file
  	touch TLSVersion.txt 2>&1
    echo "">>TLSVersion-fmt.txt
  fi
  data_json_generator_iteration null TLSVersion-fmt.txt objectsArray Data > $atatempdir/data-$$.json
  #inorder to change the object array to object with comma separated elements

  sed  's/\[/\{/g' $atatempdir/data-$$.json > $atatempdir/data-fmt-$$.json
  sed  's/\]/\}/g' $atatempdir/data-fmt-$$.json > $atatempdir/data-$$.json
  json_generator $atatempdir/data-$$.json json_file TLSVersionDetails > $atatempdir/JSON/TLSVersionDetails.json

  #Database information
  if ps -ef | grep oracle; then
  	#We collect for each Instance name
  	for SID in `cat /etc/oratab |grep -v '^$' | grep -v '^#'| grep -v "ASM"| awk -F ":" '{print $1}' `; do
  		#we get the data for SqlDiscovery.txt
  		hstn=`hostname`
  		orapath=$( cat /etc/oratab |grep $SID | grep -v '^$' | grep -v '^#'| grep -v "ASM"| awk -F ":" '{print $2}' )
  		export ORACLE_SID=$SID
  		export ORACLE_HOME=$orapath
  		oraver=$($orapath/bin/sqlplus -version | grep SQL| awk '{print $3}'|grep -v " ")
  		echo "$hstn|$SID|$oraver|$orapath|ORACLE" >> SqlDiscovery.txt
      #echo "\"InstanceName\":\"$SID\",\"InstanceIp\":null,\"InstalationPath\":\"$orapath\",\"Version\":\"$oraver\",\"DatabaseProviderMasterId\":0,\"IsDelete\":false,\"DatabaseCredentialId\":0,\"Protocol\":\"\",\"PortNumber\":0,\"ServiceName\":\"\",\"DatabaseFilePath\":\"\",\"DatabaseLogPath\":\"\",\"DatabaseFileSize\":\"\",\"IsIndividualDatabaseInstance\":null",>SqlDBDiscovery-fmt.txt
      echo "\"InstanceName\":\"$SID\",\"InstalationPath\":\"$orapath\",\"Version\":\"$oraver\"">SqlDBDiscovery-fmt.txt

      #we get the data for SqlDBDiscovery.txt
  		#$orapath/bin/sqlplus -s "/ as sysdba" <<-EOF >> $atatempdir/SqlDBDiscovery.txt
  		#set heading off feedback off verify off linesize 32000
  		#select dbaUser.USERNAME ||'|'|| sys_context('userenv','db_name')||'|'|| nvl(sum(dbaSegments.BYTES)/1024/1024,0)||' MB|||||||ORACLE' ALLCOLUMN from DBA_USERS dbaUser left join dba_segments dbaSegments on dbaSegments.OWNER = dbaUser.USERNAME group  by dbaUser.USERNAME;
  		#exit
  		#EOF
    done
  fi
  #sed -i '/^$/d' $atatempdir/SqlDiscovery.txt

  if [[ -f SqlDiscovery.txt ]]; then
     #send_data $DBINSTANCEDETAILS_URL "$(job_json_generator SqlDiscovery.txt array Lines)"
     #data_json_generator null SqlDiscovery.txt array Lines > $atatempdir/data-$$.json
     #json_generator $atatempdir/data-$$.json json_file InstanceDetails_Database > $atatempdir/JSON/InstanceDetails_Database.json
     data_json_generator_iteration null SqlDBDiscovery-fmt.txt objectsArrayParsing Data > $atatempdir/data-$$.json
     json_generator $atatempdir/data-$$.json json_file DatabaseInstanceDetails > $atatempdir/JSON/DatabaseInstanceDetails.json
  fi

  # Database Listener Status
 	if ps -ef | grep oracle; then
 	  if ps -ef | grep -i pmon; then
 		  ps -ef | grep -i pmon| awk '{print $NF}' | awk -F "_" '{print $3}' > active_listeners
 			sed -i '/^$/d' active_listeners
      cat active_listeners | awk '{print "\"Name\":""\x22"$1"\x22"",\"Status\":\"running\""}' > database_listener.txt
 		 egrep_invar=$(awk '{printf ("'%s'| ", $0)}' active_listeners)
 		 egrep_finvar=$(echo "'($egrep_invar)'")
 	  fi
 	for SID in `cat /etc/oratab |grep -v '^$' | grep -v '^#'| grep -v "ASM"| awk -F ":" '{print $1}' `; do
     orapath=$( cat /etc/oratab |grep $SID | grep -v '^$' | grep -v '^#'| grep -v "ASM"| awk -F ":" '{print $2}' )
 		  if [[ -f $orapath/network/admin/listener.ora ]]; then
 			  cat $orapath/network/admin/listener.ora | grep -iB1 list | egrep -iv '(sid|description|address|--|^#|^[[:space:]]*$)' | sort -u | awk '{print $1}' > configured_listeners
 				 if eval $(echo "cat configured_listeners | egrep -iv $egrep_finvar |sort -u | awk '{print \$1}' > configured_listeners"); then
               if [[ -s configured_listeners ]]; then
 					     cat configured_listeners | awk '{print "\"Name\":""\x22"$1"\x22"",\"Status\":\"stopped\""}' >> database_listener.txt
               fi
 					fi
 				fi
   done
   fi

   if [[ -f database_listener.txt ]]; then
   data_json_generator_iteration null database_listener.txt objectsArrayParsing Data > $atatempdir/data-$$.json
   json_generator $atatempdir/data-$$.json json_file Oracledblisteners > $atatempdir/JSON/Oracledblisteners.json
   fi

##########################apache dicovery #########################
if [[ $WEBDISCOVERY == 'True' ]]; then
  /bin/bash $DIR/discoverywebserver.sh
fi
 ###########################################


  if [[ ${DISCOVERYTYPE} == "MANUAL" ]]; then
      data_json_generator_hostname null HostName.txt file Hostname > $atatempdir/data-$$.json
      json_generator $atatempdir/data-$$.json json_file ServerDetails > $atatempdir/JSON/ServerDetails.json

  fi
  for i in $(echo ${atatempdir}/JSON/*.json); do awk -F "{" '{print $3}' $i | awk -F "," '{print $2}'| sed '/^$/d'; done >${atatempdir}/iteration_error.txt
  grep -iqv "null" ${atatempdir}/iteration_error.txt
  itstat=$(echo $?)
  if [[ $itstat -eq 0 ]]; then
      has_Error=true
  else
     has_Error=false
  fi
  # Creating final data_collection json and sending it to the console
  bulk_data_collection_json=$atatempdir/bulk_data_collection.json
  first=true
  echo "{" > $bulk_data_collection_json
  echo "\"BulkDiscovery\":{">> $bulk_data_collection_json
  for i in $(find ${atatempdir}/JSON/ -type f); do
    if ! $first; then
      echo "," >> $bulk_data_collection_json
    fi
    first=false
    sed 's/{ \(.*\) }/\1/' $i >> $bulk_data_collection_json
    # docker_array_data="${docker_array_data}$(docker_json_data $i)"
    # [[ ! -z $DOCKER_DATA ]] && send_data $DOCKER_URL $DOCKER_DATA
  done
  echo  ",">> $bulk_data_collection_json
  echo "\"DiscoveryIteration\":null,">> $bulk_data_collection_json
  echo   "\"ServerId\":$SERVER_ID,">> $bulk_data_collection_json
  echo    "\"HasError\":$has_Error" >> $bulk_data_collection_json
  echo "}" >>$bulk_data_collection_json
  echo "}" >>$bulk_data_collection_json

if [[ $JOB_NAME_ID -eq $VALIDATION ]] ; then
  send_data $DATA_COLLECTION_BULK_URL $bulk_data_collection_json
else
  if [[ "${DISCOVERYTYPE}" == "MANUAL" ]]; then
    Mdate=$(date +%s)
    cp $bulk_data_collection_json ${atatempdir}/MANUAL/Validation_Bulk-${Mdate}-00.json
  else
    TYPE_DATA=1
		DiscoveryCount=0
    send_data $AFFINITY_BULK_URL $bulk_data_collection_json
  fi
fi

  echo "******************" | tee -a $log_file
  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Completed retrieving validation data" | tee -a $log_file
  echo "******************" | tee -a $log_file
if [[ $JOB_NAME_ID -eq $DISCOVERY  ]]; then
  send_data $JOBEVENT_STATUS_URL "$(job_json_generator  50 number DiscoveryStatus 40 number DiscoveryLastStatus null nullvalue ErrorDescription 0 number IterationProgressPercent)"
fi

}

affinity_report() {
  # Running network and performance information
  cd $atatempdir/NETSTAT/
  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Started retrieving network and performance information" | tee -a $log_file
  echo "******************" | tee -a $log_file
  R=$discovery_repeat_nr

	while [ $R -le $REPEATS ]
	do
    # reset job vars
    iterstart=$(date +%s)
    JOB_STATUS=$RUNNING
    JOB_ERROR_DESCRIPTION="null"

		#date=`date +%m_%d_%y_%H_%M_%S`
    date=$(date +%Y-%m-%dT%H:%M:%S)
    NETSTAT_NA_FILE=$atatempdir/NETSTAT/netstat-na${date}.txt
    NETSTAT_NB_FILE=$atatempdir/NETSTAT/netstat-nb${date}.txt
    NETSTAT_NR_FILE=$atatempdir/NETSTAT/netstat-nr${date}.txt
    IFCONFIG_FILE=$atatempdir/IFConfig.txt
    CPU_JSON=$atatempdir/NETSTAT/CPUPercentage-$$.json
    MEM_JSON=$atatempdir/NETSTAT/MemoryPercentage-$$.json
    PROCS_JSON=$atatempdir/NETSTAT/Processes-$$.json

    ##Pause & Resume functionality, done based on the file creation
    ## variable assignment to log the message once in the generic log
    msg_counter=0

    while [ -f $DIR/PauseDiscovery.txt ]
    do
      msg_counter=$((msg_counter+1))
        if [ $msg_counter -eq 1 ]; then
        echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Discovery has been paused from the console during iteration $R"  | tee -a $log_file
        send_data $JOBEVENT_PAUSE_STATUS_URL "$(job_json_generator  50 number DiscoveryStatus 40 number DiscoveryLastStatus null nullvalue ErrorDescription 0 number IterationProgressPercent)"
        fi
      sleep 10
    done

    if [ $msg_counter -gt 1 ]; then
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Discovery has been resumed from the console during iteration $R"  | tee -a $log_file
      send_data $JOBEVENT_RESUME_STATUS_URL "$(job_json_generator  50 number DiscoveryStatus 40 number DiscoveryLastStatus null nullvalue ErrorDescription 0 number IterationProgressPercent)"
    fi

		echo "******************" | tee -a $log_file
		echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Running network and performance information $R out of $REPEATS" | tee -a $log_file
		echo "******************" | tee -a $log_file
    IsFallback=false
    which ip 2> /dev/null 2>&1
    ipcstatus=$?
    which netstat 2> /dev/null 2>&1
    if [ $? -eq 0 ]; then
      if [[ $R -le 4 ]];then
        netstat -nr >> $NETSTAT_NR_FILE
        netstat -na >> $NETSTAT_NA_FILE
      fi
      netstat -na | awk  '$6=="LISTEN" { print $4 }' | awk -F":" '{print "\"PortNumber\":""\x22"$NF"\x22"}' | sort -u  >ListeningPort-list-fmt.txt
      $SUDO netstat --programs -an >> $NETSTAT_NB_FILE
      $SUDO netstat --programs -na --inet -t
      $SUDO netstat --programs -na --inet -t | egrep -iv "unix|Proto|tcp6|udp6|address|active" | sed 's/ /,/g'| sed 's/,\{2,\}/,/g' | awk -F "[,:/]" '{print "\"IpUsed\":""\x22"$4"\x22,\"PortUsed\":""\x22"$5"\x22,\"RemoteIp\":""\x22"$6"\x22,\"RemotePort\":""\x22"$7"\x22,\"ProgramUsed\":""\x22"$10"\x22,\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":""\x22"$1"\x22"}' > ConnectionInformation-fmt.txt
      $SUDO netstat --programs -na --inet -u | egrep -iv "unix|Proto|tcp6|udp6|address|active" | sed 's/ /,/g'| sed 's/,\{2,\}/,/g' | awk -F "[,:/]" '{print "\"IpUsed\":""\x22"$4"\x22,\"PortUsed\":""\x22"$5"\x22,\"RemoteIp\":""\x22"$6"\x22,\"RemotePort\":""\x22"$7"\x22,\"ProgramUsed\":""\x22"$9"\x22,\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":""\x22"$1"\x22"}' >> ConnectionInformation-fmt.txt
      $SUDO netstat --programs -na --inet6 -t | egrep -iv "unix|Proto|address|active" > ipv6-conn.txt
      if [[ -s ipv6-conn.txt ]]; then
        while read line; do
          ipportlocal=$(echo $line | egrep -iv "unix|Proto|address|active" | awk '{print $4}')
          ipportremote=$(echo $line | egrep -iv "unix|Proto|address|active" | awk '{print $5}')
          programused=$(echo $line | egrep -iv "unix|Proto|address|active" | awk '{print $NF}')
          programused=${programused#\"}
          programused=${programused%\"}
          echo -e "\"IpUsed\":"\"${ipportlocal%:*}\","\"PortUsed\":"\"${ipportlocal##*:}\","\"RemoteIp\":"\"${ipportremote%:*}\",\"RemotePort\":\"${ipportremote##*:}\",\"ProgramUsed\":\"${programused#*/}\",\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":\"tcp6\""" >>ConnectionInformation-fmt.txt

        done <ipv6-conn.txt

      fi
      $SUDO netstat --programs -na --inet6 -u | egrep -iv "unix|Proto|address|active" > ipv6-conn.txt
      if [[ -s ipv6-conn.txt ]]; then

        while read line; do
          ipportlocal=$(echo $line | egrep -iv "unix|Proto|address|active" | awk '{print $4}')
          ipportremote=$( echo $line | egrep -iv "unix|Proto|Listen|address|active" | awk '{print $5}')
          programused=$(echo $line | egrep -iv "unix|Proto|Listen|address|active" | awk '{print $NF}')
          programused=${programused#\"}
          programused=${programused%\"}
          echo -e "\"IpUsed\":"\"${ipportlocal%:*}\","\"PortUsed\":"\"${ipportlocal##*:}\","\"RemoteIp\":"\"${ipportremote%:*}\",\"RemotePort\":\"${ipportremote##*:}\",\"ProgramUsed\":\"${programused#*/}\",\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":\"udp6\""" >>ConnectionInformation-fmt.txt
        done < ipv6-conn.txt
      fi
   elif [ $ipcstatus -eq 0 ]; then
      IsFallback=true
      if [[ $R -le 4 ]];then
       ip route >> $NETSTAT_NR_FILE
       ss -na >> $NETSTAT_NA_FILE
      fi
      ss -na | awk '$2=="LISTEN" { print $5}'| grep -i ^[0-9[*]  |  awk -F":" '{print "\"PortNumber\":""\x22"$NF"\x22"}' |sort -u >ListeningPort-list-fmt.txt
      #ss -npa --ipv4| egrep -iv "unix|Proto|Listen|tcp6|udp6|eth" | egrep -i "tcp|udp" | sed 's/ /,/g'| sed 's/,\{2,\}/,/g' |  awk -F "[,:/(]" '{print "\"IpUsed\":""\x22"$5"\x22,\"PortUsed\":""\x22"$6"\x22,\"RemoteIp\":""\x22"$7"\x22,\"RemotePort\":""\x22"$8"\x22,\"ProgramUsed\":""\x22"$12"\x22,\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":""\x22"$1"\x22"}' >ConnectionInformation-fmt.txt
      $SUDO ss -npa --ipv4 -t | egrep -iv "address|unix|Proto|tcp6|udp6|eth" | sed 's/ /,/g'| sed 's/,\{2,\}/,/g' | sed 's/\"//g' | awk -F "[,:/(]" '{print "\"IpUsed\":""\x22"$4"\x22,\"PortUsed\":""\x22"$5"\x22,\"RemoteIp\":""\x22"$6"\x22,\"RemotePort\":""\x22"$7"\x22,\"ProgramUsed\":""\x22"$11"\x22,\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":\"tcp\""}' >ConnectionInformation-fmt.txt
      $SUDO  ss -npa --ipv4 -u | egrep -iv "address|unix|Proto|tcp6|udp6|eth" | sed 's/ /,/g'| sed 's/,\{2,\}/,/g' | sed 's/\"//g' | awk -F "[,:/(]" '{print "\"IpUsed\":""\x22"$4"\x22,\"PortUsed\":""\x22"$5"\x22,\"RemoteIp\":""\x22"$6"\x22,\"RemotePort\":""\x22"$7"\x22,\"ProgramUsed\":""\x22"$11"\x22,\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":\"udp\""}'>>ConnectionInformation-fmt.txt

      $SUDO ss -npa --ipv6 -t  | egrep -iv "unix|Proto|address|active"  > ipv6-conn.txt
      if [[ -s ipv6-conn.txt ]];then
        while read line;do
          ipportlocal=$(echo $line| egrep -iv "unix|Proto|address|active" | awk '{print $4}')
          ipportremote=$(echo $line | egrep -iv "unix|Proto|address|active"| awk '{print $5}')
          programused=$(echo $line | egrep -iv "unix|Proto|address|active"|  awk -F"[(,]" '{print $3}')
          programused=${programused#\"}
          programused=${programused%\"}
          echo -e "\"IpUsed\":"\"${ipportlocal%:*}\","\"PortUsed\":"\"${ipportlocal##*:}\","\"RemoteIp\":"\"${ipportremote%:*}\",\"RemotePort\":\"${ipportremote##*:}\",\"ProgramUsed\":\"${programused#*/}\",\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":\"udp6\""" >>ConnectionInformation-fmt.txt
        done <ipv6-conn.txt
      fi
      $SUDO ss -npa --ipv6 -u  | egrep -iv "unix|Proto|address|active" > ipv6-conn.txt
      if [[ -s ipv6-conn.txt ]]; then
        while read line;do
          ipportlocal=$(echo $line | egrep -iv "unix|Proto|address|active" | awk '{print $4}')
          ipportremote=$(echo $line | egrep -iv "unix|Proto|address|active"| awk '{print $5}')
          programused=$(echo $line | egrep -iv "unix|Proto|address|active"|  awk -F"[(,]" '{print $3}')
          programused=${programused#\"}
          programused=${programused%\"}
          echo -e "\"IpUsed\":"\"${ipportlocal%:*}\","\"PortUsed\":"\"${ipportlocal##*:}\","\"RemoteIp\":"\"${ipportremote%:*}\",\"RemotePort\":\"${ipportremote##*:}\",\"ProgramUsed\":\"${programused#*/}\",\"ProgramPath\":\"\",\"ParentProgram\":\"\",\"ParentPath\":\"\",\"ConnectionCount\":"1",\"Protocol\":\"udp6\""" >>ConnectionInformation-fmt.txt
        done < ipv6-conn.txt
      fi
      ss -npa >> $NETSTAT_NB_FILE
    else
      echo "******************" | tee -a $log_file
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) ENETS Error Command netstat/ip is not found" | tee -a $log_file
      echo "******************" | tee -a $log_file
      echo "null" >> $NETSTAT_NR_FILE
      echo "null" >> $NETSTAT_NA_FILE
      echo "null" >> $NETSTAT_NB_FILE
    fi

    error_check "ENETS"
		#data_json_generator $error $IFCONFIG_FILE array Lines $NETSTAT_NR_FILE array NetstatLines $IsFallback boolean IsFallback > $atatempdir/data-$$.json
    #json_generator $atatempdir/data-$$.json json_file NetworkInformation_Host > $atatempdir/NETSTAT/JSON/NetworkInformation_Host.json
    data_json_generator_iteration "$error" ListeningPort-list-fmt.txt objectsArrayParsing Data > $atatempdir/data-$$.json
    json_generator $atatempdir/data-$$.json json_file ListeningPortList > $atatempdir/NETSTAT/JSON/ListeningPortList.json
	#	data_json_generator $error $NETSTAT_NA_FILE array Lines $IsFallback boolean IsFallback > $atatempdir/data-$$.json
    #json_generator $atatempdir/data-$$.json json_file Netstat_ReadContainerListeningPortInfo > $atatempdir/NETSTAT/JSON/Netstat_ReadContainerListeningPortInfo.json
    data_json_generator_iteration "$error" ConnectionInformation-fmt.txt objectsArrayParsing Data  > $atatempdir/data-$$.json
    json_generator $atatempdir/data-$$.json json_file ConnectionInformation > $atatempdir/NETSTAT/JSON/ConnectionInformation.json

    which ps > /dev/null 2>&1
    if [ $? = 0 ]; then
      cpuper=$(ps aux | awk {'sum+=$3;print sum'} | tail -n 1)
      cpupercent=$(echo ${cpuper%.*})
      if [[ $cpupercent -gt 100 ]]; then
        cpupercent=$(echo ${cpuper%.*} | awk -v a=$cpucores '{print $0/a}')
        if [[ $cpupercent -gt 100 ]]; then
          cpupercent=100
          echo $cpupercent >> CPUPercentage${date}.txt
        else
          echo $cpupercent >> CPUPercentage${date}.txt
        fi
      else
        echo $cpupercent >> CPUPercentage${date}.txt
      fi

    else
      echo "******************" | tee -a $log_file
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EPS: Error retrieving running processes information: Command ps not found." | tee -a $log_file
      echo "******************" | tee -a $log_file
      cpupercent="0"
    fi


    which free > /dev/null 2>&1
    if [ $? = 0 ]; then
		  rampercent=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    else
      echo "******************" | tee -a $log_file
    	echo "($(date -u +"%m/%d/%Y %H:%M:%S")) EFREE: Error retrieving memory free information: Command free not found." | tee -a $log_file
    	echo "******************" | tee -a $log_file
      rampercent="0"
    fi
		echo $rampercent >> MemoryPercentage${date}.txt

    # generate auxiliar json objects
  #  json_generator "${cpuper}" number CpuPercentage "${date}" literal DataCollectionTimeFormat > $CPU_JSON
  #  json_generator "${rampercent}" number MemoryPercentage "${date}" literal DataCollectionTimeFormat > $MEM_JSON
    json_generator "${cpupercent}" number CpuPercentage "${date}" literal DataCollectionTime > $CPU_JSON
    error_check "EPS"
    data_json_generator_iteration "$error" $CPU_JSON json_file Data > cpuusage-fmt.txt
    json_generator "${rampercent}" number MemoryPercentage "${date}" literal DataCollectionTime > $MEM_JSON
    error_check "EFREE"
    data_json_generator_iteration "$error" $MEM_JSON json_file Data > memory-usage-fmt.txt

    #error_check
  #  error_check "EPS"
    #data_json_generator $error $CPU_JSON objectsArray Data > $atatempdir/data-$$.json
    #json_generator $atatempdir/data-$$.json json_file Processor_CPUUsageLinux > $atatempdir/NETSTAT/JSON/Processor_CPUUsageLinux.json
    json_generator cpuusage-fmt.txt json_file CPUUsage > $atatempdir/NETSTAT/JSON/CPUUsage.json

    #error_check
  #  error_check "EFREE"
	#	data_json_generator $error $MEM_JSON objectsArray Data > $atatempdir/data-$$.json
  #  json_generator $atatempdir/data-$$.json json_file MemoryInfo_MemoryUsage > $atatempdir/NETSTAT/JSON/MemoryInfo_MemoryUsage.json
    json_generator memory-usage-fmt.txt json_file MemoryUsage > $atatempdir/NETSTAT/JSON/MemoryUsage.json

		#Process list
    cat /dev/null > $PROCS_JSON
		IFS=$'\n'       # make newlines the only separator
		for line in `ps -eo pid,ppid,cmd| grep -v CMD`; do
      process=$(echo $line | awk '{print $1}')
      parent=$(echo $line | awk '{print $2}')
      cmd=$(echo $line | awk '{ print substr($0, index($0,$3)) }')
      path=$(readlink -f /proc/${process}/exe | sed "s/(deleted)//")
			if [[ -z $path ]]; then
				if echo $cmd | grep "\["; then
					path="Path not detected"
				else
					path=$(echo $cmd| awk '{print $1}')
				fi
			fi
      echo ${process},${parent},${cmd},${path}

      # generate auxiliar json objects
      json_generator ${process} literal ProcessId ${parent} literal ParentId ${cmd} literal ProcessName ${path} literal ProcessPath >> $PROCS_JSON
		done >> Processes_${date}.txt
		unset IFS

    #error_check
    error_check "ENETS"
		#data_json_generator $error $NETSTAT_NB_FILE array Lines $PROCS_JSON objectsArray ProcessLines $IsFallback boolean IsFallback > $atatempdir/data-$$.json
    #json_generator $atatempdir/data-$$.json json_file Netstat_LinuxServerConnections > $atatempdir/NETSTAT/JSON/Netstat_LinuxServerConnections.json
		#here we start collecting info for docker
		which docker > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			unset image
			mkdir -p $atatempdir/DOCKER/NETSTAT/BULK
      # just some auxiliar json files
      DOCKER_CPU_JSON=$atatempdir/DOCKER/NETSTAT/CPUPercentage-$$.json
      DOCKER_MEM_JSON=$atatempdir/DOCKER/NETSTAT/MemoryPercentage-$$.json
      DOCKER_PROCS_JSON=$atatempdir/DOCKER/NETSTAT/Processes-$$.json

			for image in $(docker ps | grep -v COMMAND| awk '{print $1}'); do
				mkdir -p $atatempdir/DOCKER/NETSTAT/JSON
        DOCKER_NETSTAT_NA_FILE=$atatempdir/DOCKER/NETSTAT/netstat-na${date}-${image}.txt
        DOCKER_NETSTAT_NB_FILE=$atatempdir/DOCKER/NETSTAT/netstat-nb${date}-${image}.txt

        # containers may not have netstat command
				docker exec ${image} netstat -nr >> $atatempdir/DOCKER/NETSTAT/netstat-nr${date}-${image}.txt
				docker exec ${image} netstat -na >> $DOCKER_NETSTAT_NA_FILE
        DOCKER_NETSTAT_NA_STATUS=$?
				docker exec --privileged=true ${image} netstat --programs -an >> $DOCKER_NETSTAT_NB_FILE
        DOCKER_NETSTAT_NB_STATUS=$?
				cpuper=$(docker exec ${image} ps aux | awk {'sum+=$3;print sum'} | tail -n 1)
				echo $cpuper >> $atatempdir/DOCKER/NETSTAT/CPUPercentage${date}-${image}.txt
				rampercent=$(docker exec ${image} free | grep Mem | awk '{print $3/$2 * 100.0}')
				echo $rampercent >> $atatempdir/DOCKER/NETSTAT/MemoryPercentage${date}-${image}.txt

        # generate auxiliar json objects
				json_generator "${cpuper}" number CpuPercentage "${date}" literal DataCollectionTimeFormat > $DOCKER_CPU_JSON
        json_generator $DOCKER_CPU_JSON objectsArray CpuPercentage > $atatempdir/DOCKER/NETSTAT/JSON/docker-cpu-json-${image}.json

        json_generator "${rampercent}" number MemoryPercentage "${date}" literal DataCollectionTimeFormat > $DOCKER_MEM_JSON
        json_generator $DOCKER_MEM_JSON objectsArray MemoryPercentage > $atatempdir/DOCKER/NETSTAT/JSON/docker-mem-json-${image}.json

        # send_data $PROCESSOR_URL "$(job_json_generator ${image} literal ContainerId $DOCKER_CPU_JSON objectsArray Data)"
        # send_data $MEMORY_URL "$(job_json_generator ${image} literal ContainerId $DOCKER_MEM_JSON objectsArray Data)"

        #Process list
				IFS=$'\n'       # make newlines the only separator
				for line in `docker exec ${image} ps -eo pid,ppid,cmd`; do
					process=$(echo $line | awk '{print $1}')
					parent=$(echo $line | awk '{print $2}')
					cmd=$(echo $line | awk '{ print substr($0, index($0,$3)) }')
					path=$(docker exec --privileged=true ${image} readlink -f /proc/${process}/exe | sed "s/(deleted)//")
					[[ -z "$path" ]] && path="unknown"
					echo ${process},${parent},${cmd},${path}

          # generate auxiliar json objects
          json_generator ${process} literal ProcessId ${parent} literal ParentId ${cmd} literal ProcessName ${path} literal ProcessPath >> $DOCKER_PROCS_JSON
				done >> $atatempdir/DOCKER/NETSTAT/Processes_${date}-${image}.txt
				unset IFS

				json_generator $DOCKER_PROCS_JSON objectsArray Processes > $atatempdir/DOCKER/NETSTAT/JSON/procs-json-${image}.json

				# parse data only if it was possible to retrieve it from container
        if [[ $DOCKER_NETSTAT_NA_STATUS -eq 0 ]]; then
          json_generator ${date} literal Date $DOCKER_NETSTAT_NA_FILE array Lines > $atatempdir/DOCKER/NETSTAT/netstat-na-$$.json
          json_generator $atatempdir/DOCKER/NETSTAT/netstat-na-$$.json json_file netstat_na > $atatempdir/DOCKER/NETSTAT/JSON/netstat-na-json-${image}.json
        fi

        if [[ $DOCKER_NETSTAT_NB_STATUS -eq 0 ]]; then
          json_generator ${date} literal Date $DOCKER_NETSTAT_NB_FILE array Lines > $atatempdir/DOCKER/NETSTAT/netstat-nb-$$.json
          json_generator $atatempdir/DOCKER/NETSTAT/netstat-nb-$$.json json_file netstat_nb > $atatempdir/DOCKER/NETSTAT/JSON/netstat-nb-json-${image}.json
        fi

        docker_array_data="{"
        for i in $(find $atatempdir/DOCKER/NETSTAT/JSON/ -type f ); do
          [[ $docker_array_data != "{" ]] && docker_array_data="${docker_array_data},"
          docker_array_data="${docker_array_data}$(sed 's/{ \(.*\) }/\1/' $i)"
        done
        docker_array_data="${docker_array_data}}"
        echo $docker_array_data > $atatempdir/DOCKER/NETSTAT/JSON/docker-data-$image.json
        json_generator $image literal ContainerId $atatempdir/DOCKER/NETSTAT/JSON/docker-data-$image.json json_file Data > $atatempdir/DOCKER/NETSTAT/BULK/disks-iops-json-${image}.json
        rm -rf $atatempdir/DOCKER/NETSTAT/JSON
			done

			docker_array_data="["
          for i in $(find $atatempdir/DOCKER/NETSTAT/BULK/ -type f ); do
            [[ $docker_array_data != "[" ]] && docker_array_data="${docker_array_data},"
            docker_array_data="${docker_array_data}$(cat $i)"
          done
          docker_array_data="${docker_array_data}]"
          echo $docker_array_data > $atatempdir/discovery-docker-data.json
          data_json_generator null $atatempdir/discovery-docker-data.json json_file Data > $atatempdir/discovery-docker-data-pre.json
          json_generator $atatempdir/discovery-docker-data-pre.json json_file docker_info > $atatempdir/NETSTAT/JSON/docker-json-${image}.json

	  fi

    #Adding the logic to collect the disk growth in defined intervals

    if [ $DISKGROWTHINTERVAL -gt 0 ] && [ $(($R%$DiskIterVal)) == 0 ]; then

      df -TP -B1 |grep -iv cifs| grep -Ev ':|\/\/|tmpfs|Filesystem' | sed -e 's/ \+/\ \,\ /g' | awk -v a=$ext -v DCT=$date -F " , " '{print "\"VolumeName\":""\x22"$1"\x22"",\"UsedSpace\":"$4",\"DataCollectionTime\":\""DCT"\""}' > DiskGrowth.txt

      data_json_generator_iteration null DiskGrowth.txt objectsArrayParsing Data > $atatempdir/data-$$.json
      json_generator $atatempdir/data-$$.json json_file DiskGrowthDetails > $atatempdir/NETSTAT/JSON/DiskGrowthDetails.json

   fi

		#Here we colletc the IOPS affinity data
    if [ "${distro}" != "el2" ] && [ "${distro}" != "el3" ] ; then
      IOPS_JSON=IOPS-$$.json
			IOT=1
			while [ $IOT -lt 60 ]; do
				for disko in `$SUDO cat /proc/partitions | grep -v major | awk 'NF'|grep -iv emcpower | grep -v 'dm-' |grep -v loop| grep -iv ram| sort -k 2 | grep -vi mapper | grep -iv ram|awk '{print $4}'|eval ${grepvar}`; do
					rws1=$(cat /proc/diskstats | grep -w $disko | awk '{print $4}')
					wrs1=$(cat /proc/diskstats | grep -w $disko | awk '{print $8}')
					echo "$disko;$rws1;$wrs1" >> tempIOPS1.out
				done
				sleep 5
				for disko in `$SUDO cat /proc/partitions | grep -v major | awk 'NF'|grep -iv emcpower | grep -v 'dm-' |grep -v loop| grep -iv ram| sort -k 2 | grep -vi mapper | grep -iv ram|awk '{print $4}'|eval ${grepvar}`; do
					rws1=$(cat tempIOPS1.out | grep -w $disko | awk -F";" '{print $2}')
					wrs1=$(cat tempIOPS1.out | grep -w $disko | awk -F";" '{print $3}')

					rws2=$(cat /proc/diskstats | grep -w $disko | awk '{print $4}')
					wrs2=$(cat /proc/diskstats | grep -w $disko | awk '{print $8}')

					#Divide by 5 to get the number in seconds and multiple by 512 due to values in /proc/diskstat are in sectores (512)
					rwt=$(( ( $rws2 - $rws1 ) / 5 * 512 ))
					wrt=$(( ( $wrs2 - $wrs1 ) / 5  * 512 ))

					#Set the first time
					if [ $IOT -eq "1" ]; then
						eval ${disko}_rwt=0
						eval ${disko}_wrt=0
					fi

					#Write to disk variable for each disk
					if [ $rwt -gt "$(eval echo \$${disko}_rwt)" ]; then
						eval ${disko}_rwt=$rwt
					fi
					if [ $wrt -gt "$(eval echo \$${disko}_wrt)" ]; then
						eval ${disko}_wrt=$wrt
					fi
				done
				rm -rf tempIOPS1.out
				IOT=$(( IOT+1 ))
			done
			#Print the arrays to the file
			for disko in `$SUDO cat /proc/partitions | grep -v major | awk 'NF'|grep -iv emcpower | grep -v 'dm-' |grep -v loop| grep -iv ram| sort -k 2 | grep -vi mapper | grep -iv ram|awk '{print $4}'|eval ${grepvar}`; do
				echo "$disko;"$(eval echo \$${disko}_rwt)";"$(eval echo \$${disko}_wrt)"" >> IOPS_${date}.txt
			done

      cat /dev/null > $IOPS_JSON
      IFS=";"
      while read line; do
        set -- $line
        json_generator $1 literal DiskName $2 number ReadPerSec $3 number WritePerSec $date literal DataCollectionTime >> $IOPS_JSON
        #echo "\"DiskName\":\"$1\",\"ReadPerSec\":$2,\"WritePerSec\":$3,\"DataCollectionTime\":\"$date\"" >> $IOPS_JSON
      done < IOPS_${date}.txt
      unset IFS

		#	data_json_generator null $IOPS_JSON objectsArray Data > $atatempdir/data-$$.json
      data_json_generator_iteration null $IOPS_JSON objectsArray Data > $atatempdir/data-$$.json

    #  data_json_generator_iteration null $IOPS_JSON objectsArrayParsing Data > $atatempdir/data-$$.json
    #  json_generator $atatempdir/data-$$.json json_file Disks_Iops > $atatempdir/NETSTAT/JSON/disks-iops-json-${image}.json
      json_generator $atatempdir/data-$$.json json_file DiskIOPS > $atatempdir/NETSTAT/JSON/DiskIOPS-json.json

    fi

		#checking any errors on the affinity
    for i in $(echo ${atatempdir}/NETSTAT/JSON/*.json); do awk -F "{" '{print $3}' $i | awk -F "," '{print $2}' | sed '/^$/d'; done >${atatempdir}/iteration_error.txt
    grep -iqv "null" ${atatempdir}/iteration_error.txt
    itstat=$(echo $?)
    if [[ $itstat -eq 0 ]]; then
        errorcal=$(grep -iv "null" ${atatempdir}/iteration_error.txt  | awk -F ":" '{print $2}')
        error=$(echo -e "${errorcal// /\\n}"|sort -u | tail -1)
        json_generator $R number Iteration > ${atatempdir}/iteration-count.json
        data_json_generator_iteration $error ${atatempdir}/iteration-count.json json_file Data >$atatempdir/job-$$.json
    else
        json_generator $R number Iteration > ${atatempdir}/iteration-count.json
        data_json_generator_iteration null ${atatempdir}/iteration-count.json json_file Data >$atatempdir/job-$$.json
    fi

    json_generator $atatempdir/job-$$.json json_file DiscoveryIteration > $atatempdir/NETSTAT/JSON/DiscoveryIteration.json
    #job statsu cal

    if [[ $R -eq 1 ]];then
      failedPercentage=0
      failedRuncount=0
    fi
    errorcount=$(grep "ERROR" ${atatempdir}/iteration_error.txt  | awk -F ":" '{print $2}' | wc -l)
    if [[ $errorcount -ge 1 ]];then
      failedRuncount=$(($failedRuncount+1))
      failedPercentage=$((($failedRuncount*100)/$REPEATS))
      if [[ $failedPercentage -ge $DISCOVERY_FAIL_THRESHOLD ]];then
        JOB_ERROR_DESCRIPTION="Number of failed runs exceeded threshold value while running Vision on targeted Host"
        if [[ "${DISCOVERYTYPE}" == "MANUAL" ]]; then
          Mdate=$(date +%s)
          echo "$(json_generator $JOB_ID number JobId $SERVER_ID number ServerDetailId $DISCOVERY_ERROR number Status "$JOB_ERROR_DESCRIPTION" literal ErrorDescription)" > ${atatempdir}/MANUAL/Finalstatus_${Mdate}.json
          cd $DIR
          #ipn=$(ip a | grep eth|grep inet |head -1| awk '{print $2}'|awk -F "/" '{print $1}')
           #tar -cf ${ipn}_${OS}_${HOURS}.tar ${atatempdir}/MANUAL/*.json
          cd ${atatempdir}/MANUAL/
          tar -cf ${ipn}_${OS}_${JOB_ID}.tar *.json
          mv ${ipn}_${OS}_${JOB_ID}.tar ${atatempdir}/
          discovery_monitor_exit 1
        else
          send_data $JOB_COMPLETION_URL "$(json_generator $JOB_ID number JobId $SERVER_ID number ServerDetailId $DISCOVERY_ERROR number Status "$JOB_ERROR_DESCRIPTION" literal ErrorDescription)" "PUT"
          if [ ! -f /tmp/atadebug ]; then
            cd $DIR
            find $atatempdir -mindepth 1 -maxdepth 1 \( ! -iname "*-log*.txt"  ! -iname "*.tar" \) -exec rm -rf {} \;
            \rm -- "$0" # remove itself
          fi
          discovery_monitor_exit 1
        fi
      fi
    fi

    # here I send bulk discovery data for this iteration
    discovery_bulk_json=$atatempdir/discovery_bulk.json
    first=true
    echo "{" > $discovery_bulk_json
    echo "\"BulkDiscovery\":{" >>  $discovery_bulk_json
    for i in $(find ${atatempdir}/NETSTAT/JSON/ -type f); do
      if ! $first; then
        echo "," >> $discovery_bulk_json
      fi
      first=false
      sed 's/{ \(.*\) }/\1/' $i >> $discovery_bulk_json
      # docker_array_data="${docker_array_data}$(docker_json_data $i)"
      # [[ ! -z $DOCKER_DATA ]] && send_data $DOCKER_URL $DOCKER_DATA
    done
    echo   ",\"ServerId\":$SERVER_ID,">> $discovery_bulk_json
    echo    "\"HasError\":false" >> $discovery_bulk_json

    echo "}" >> $discovery_bulk_json
    echo "}" >> $discovery_bulk_json

    if [[ "${DISCOVERYTYPE}" == "MANUAL" ]]; then
       Mdate=$(date +%s)
       cp $discovery_bulk_json ${atatempdir}/MANUAL/discovery_bulk_iter_${R}_${Mdate}.json
    else
       #checking connectivity of hostapi
       offline_discovery
       #Sending affinity data to console_post
       TYPE_DATA=2
			 DiscoveryCount=$R
       send_data $AFFINITY_BULK_URL $discovery_bulk_json
    fi
    echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Checking discovery iteration status" | tee -a $log_file
    if [[ $JOB_STATUS -ne $RUNNING ]]; then
      JOB_STATUS=$DISCOVERY_ERROR
      JOB_ERROR_DESCRIPTION="Error while running Discovery on targeted Host"
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) A job failed. Stop processing discovery" | tee -a $log_file
      break
    fi

    # to delete the DiskGrowthDetails json once it is sent back to the console.
    if [ -f $atatempdir/NETSTAT/JSON/DiskGrowthDetails.json ]; then
      rm -f $atatempdir/NETSTAT/JSON/DiskGrowthDetails.json
    fi

    iterend=$(date +%s)
    itertime=$((iterend-iterstart))
    if [[ $itertime -gt $SECS_INTERVAL ]]; then
     SCS_INTERVAL=0
       echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Iteration time taken more than interval time $INTERVAL mins," | tee -a $log_file
    else
     SCS_INTERVAL=$(($SECS_INTERVAL-$itertime))
    fi
    INTERVAL_TIME=$(($SCS_INTERVAL/60))
    #End of affinity data collection
    if [ $R -lt $REPEATS ]; then
      echo "******************" | tee -a $log_file
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Application is idle for $INTERVAL_TIME mins after $R run" | tee -a $log_file
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Application is idle for $INTERVAL_TIME mins after $R run" >>  $full_log_file
      echo "******************" | tee -a $log_file
      if [ $R -eq 2 ] && [ ! -f /tmp/atadebug ]; then
        set +x
        exec >>/dev/null
      fi
      R=$(( R+1 ))
      echo "$R" > ${stepfile}
      sleep $SCS_INTERVAL
    else
      sleep $SCS_INTERVAL
      echo "******************" | tee -a $log_file
      echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Completed retrieving network and performance information" | tee -a $log_file
      echo "******************" | tee -a $log_file
      R=$(( R+1 ))
    fi
    #creating Full tar of discovery
    cd ${atatempdir}
    tar -cf discovery-${JOB_ID}-full.tar *
    cd $atatempdir/NETSTAT/
    # disable debugging after second iteration

  done

}

##########################################################
#####################---MAIN---###########################
##########################################################
# Start main process

# OS validation
OS=$(uname)
[[ $OS != "Linux" ]] && echo "Discovery is not running in a Linux machine. Please select the correct OS" && exit 1

# arguments validation
echo "discovery script was run with args: ${*}"
[[ $# -lt 3 || $# -gt 9 ]] && usage && exit 1

variable_definition "$@" # send all arguments to variable definition function

echo "discovery script was run with args: ${*}" | tee -a $log_file

mkdir -p $atatempdir/NETSTAT/JSON $atatempdir/JSON  $atatempdir/OFFLN $atatempdir/OFFLNBACKUP $atatempdir/MANUAL $webserverdir

# Check if another instance of discovery is running
if [ -f $LOCK_FILE ]; then
  PROCESS=$(cat $LOCK_FILE)
  ps aux | grep $PROCESS | grep -v grep
  if [ $? -eq 0 ]; then
		echo "******************" | tee -a $log_file
    echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Discovery process is already running. exiting..." | tee -a $log_file
		echo "******************" | tee -a $log_file
    exit 1
  fi
fi


# Full log
set -x
exec >> $full_log_file
exec 2>&1

# create lock file
echo $$ > $LOCK_FILE

# trap exit and fail if lock file was not yet removed
trap "{ \rm $LOCK_FILE 2>/dev/null && exit 255; }" SIGINT EXIT

# here we start the information grab
echo "Script version 2.00.81" 2>&1  | tee -a $log_file
if [[ ${DISCOVERYTYPE} != "MANUAL" ]]; then

   curl_ssl_test # test if curl works or hsa ssl issues, then replace it with go alternative
else
  echo "This is a Manual discovery" 2>&1 | tee -a $log_file
fi

cd $atatempdir

echo "******************" | tee -a $log_file
echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Starting discovery..." | tee -a $log_file
echo "******************" | tee -a $log_file


# checking if it is a discovery (affinityJob) and creating crontab accordingly...
if [[ $JOB_NAME_ID -eq $DISCOVERY  ]]; then
  echo "creating crontab line to continue migration if interrupted"
  if ! crontab -l 2>/dev/null | grep -q discovery_monitor; then
    (crontab -l 2>/dev/null ; echo "*/5 * * * * ${DIR}/discovery_monitor") | crontab -
  fi

  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Checking if discovery (affinity report) was interrupted" | tee -a $log_file
  if [ ! -f ${stepfile} ]; then
    echo "1" > ${stepfile}
  fi
  discovery_repeat_nr=$(cat "${stepfile}")

  if [[ $discovery_repeat_nr -eq 1 ]]; then
    discovery_monitor ${*}
  fi
fi

if [[ $JOB_NAME_ID -eq $VALIDATION ]]; then
  discovery_repeat_nr=1
fi

# avoid running validation and data_collection if it was restarted
if [[ $discovery_repeat_nr -eq 1 ]]; then
  validation_process
  # start data collection
  data_collection
  echo "1" > ${stepfile} # pre affinity completed. Will not be run again
fi

# if executing a discovery job but validation part failed, do not continue with discovery
if [[ $JOB_NAME_ID -eq $DISCOVERY  ]]; then
  if [[ $JOB_STATUS -eq $RUNNING ]];then
    affinity_report
  else
    echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Do not continue with discovery. Validation failed." | tee -a $log_file
    JOB_ERROR_DESCRIPTION="Validation failed. We do not continue with discovery"
  fi
fi

if [[ $JOB_NAME_ID -eq $VALIDATION ]]; then
  cd $DIR
  tar -cf validation-${JOB_ID}-full.tar ${atatempdir}/
  mv validation-${JOB_ID}-full.tar ${atatempdir}/
  cd ${atatempdir}
  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Notifying validation job status to console" | tee -a $log_file
  if [[ $JOB_STATUS -eq $RUNNING ]]; then
    FINAL_STATUS=$SUCCESS
  else
    FINAL_STATUS=$FAILED
    JOB_ERROR_DESCRIPTION="Error while running Validation on targeted Host"
  fi
else
  echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Notifying discovery job status to console" | tee -a $log_file
  [[ $JOB_STATUS -eq $RUNNING ]] && FINAL_STATUS=$SCAN_COMPLETE || FINAL_STATUS=$DISCOVERY_ERROR
fi

echo "******************" | tee -a $log_file
echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Completed scan and zipped output at $atatempdir" | tee -a $log_file
echo "($(date -u +"%m/%d/%Y %H:%M:%S")) Completed scan and zipped output at $atatempdir" >>  $full_log_file
echo "******************" | tee -a $log_file
#ipn=$(ip a |egrep '(eth|ens)'|grep inet |head -1| awk '{print $2}'|awk -F "/" '{print $1}')
if [[ "${DISCOVERYTYPE}" == "MANUAL" ]]; then
  Mdate=$(date +%s)
  echo "$(json_generator $JOB_ID number JobId $SERVER_ID number ServerDetailId $FINAL_STATUS number Status "$JOB_ERROR_DESCRIPTION" literal ErrorDescription)" > ${atatempdir}/MANUAL/Finalstatus_${Mdate}.json
  cd $DIR
  #ipn=$(ip a | grep eth|grep inet |head -1| awk '{print $2}'|awk -F "/" '{print $1}')
   #tar -cf ${ipn}_${OS}_${HOURS}.tar ${atatempdir}/MANUAL/*.json
  tar -cf discovery-${JOB_ID}-full.tar ${atatempdir}/
  mv discovery-${JOB_ID}-full.tar ${atatempdir}/
  cd ${atatempdir}/MANUAL/
  tar -cf ${ipn}_${OS}_${JOB_ID}.tar *.json
  mv ${ipn}_${OS}_${JOB_ID}.tar ${atatempdir}/
else
  send_data $JOB_COMPLETION_URL "$(json_generator $JOB_ID number JobId $SERVER_ID number ServerDetailId $FINAL_STATUS number Status "$JOB_ERROR_DESCRIPTION" literal ErrorDescription)" "PUT"
  cd ${atatempdir}/OFFLN/
  tar -cf ${ipn}_${OS}_${JOB_ID}.tar *.json
  mv ${ipn}_${OS}_${JOB_ID}.tar ${atatempdir}/
fi
if [ ! -f /tmp/atadebug ]; then
  cd $DIR
  find $atatempdir -mindepth 1 -maxdepth 1 \( ! -iname "*-log*.txt"  ! -iname "*.tar" \) -exec rm -rf {} \;
  \rm -- "$0" # remove itself
fi

discovery_monitor_exit 0
